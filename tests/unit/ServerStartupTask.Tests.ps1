$discoveryGood = @(
    [pscustomobject]@{ Sid = 'S-1-5-32-544'; Rights = 2032127; Type = 'Allow'; Inherited = $false },
    [pscustomobject]@{ Sid = 'S-1-5-18'; Rights = 2032127; Type = 'Allow'; Inherited = $false }
)

BeforeAll {
    $script:Good = @(
        [pscustomobject]@{ Sid = 'S-1-5-32-544'; Rights = 2032127; Type = 'Allow'; Inherited = $false },
        [pscustomobject]@{ Sid = 'S-1-5-18'; Rights = 2032127; Type = 'Allow'; Inherited = $false },
        [pscustomobject]@{ Sid = 'S-1-5-19'; Rights = 197055; Type = 'Allow'; Inherited = $false }
    )
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $script:Root 'src\ChannelForge\Private'
    foreach ($name in 'Test-ChannelForgeElevated', 'Read-ChannelForgeAdminPasswordFile', 'Get-ChannelForgeStartGuard', 'Initialize-ChannelForgeServerTask') {
        . (Join-Path $private ($name + '.ps1'))
    }
    function New-DataRoot {
        param([switch]$WithPassword)
        $d = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null
        if ($WithPassword) { [IO.File]::WriteAllText((Join-Path $d 'admin-password.json'), '{"Schema":1,"Salt":"c2FsdA==","Hash":"aGFzaA=="}') }
        $d
    }
}

Describe 'Server start-up task install' {
    BeforeEach {
        Mock Test-ChannelForgeElevated { $true }
        Mock Get-ChannelForgeServerRuntimePath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
        Mock Set-ChannelForgeServerDataAcl { }
        Mock Get-ChannelForgeServerDataAccess { $script:Good }
        Mock Get-ChannelForgeServerTaskInfo { $null }
        Mock Register-ChannelForgeServerTask { $script:Xml = $Xml }
        Mock Start-ChannelForgeServerTask { }
        Mock Invoke-ChannelForgeNetsh { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock Add-ChannelForgeServerFirewallRule { $script:Spec = $Spec }
        Mock Invoke-ChannelForgeServerFirstRun { }
        $script:Xml = $null
        $script:Spec = $null
    }

    It 'refuses without an administrator window and changes nothing' {
        Mock Test-ChannelForgeElevated { $false }
        { Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) } | Should -Throw '*administrator window*'
        Should -Invoke Register-ChannelForgeServerTask -Times 0
        Should -Invoke Set-ChannelForgeServerDataAcl -Times 0
    }
    It 'refuses a network address when sign-in is not set up' {
        { Install-ChannelForgeServerTask -Root 'C:\CF' -BindAddress 0.0.0.0 -AllowedHost 10.0.0.5 -DataRoot (New-DataRoot) } | Should -Throw '*sign-in set up first*'
        Should -Invoke Invoke-ChannelForgeNetsh -Times 0
        Should -Invoke Register-ChannelForgeServerTask -Times 0
    }
    It 'refuses a network address with no -AllowedHost' {
        { Install-ChannelForgeServerTask -Root 'C:\CF' -BindAddress 0.0.0.0 -DataRoot (New-DataRoot -WithPassword) } | Should -Throw '*-AllowedHost*'
        Should -Invoke Register-ChannelForgeServerTask -Times 0
    }
    It 'defines a start-up task for LOCAL SERVICE with restarts and no time limit' {
        Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) | Out-Null
        $x = [xml]$script:Xml
        $ns = [Xml.XmlNamespaceManager]::new($x.NameTable); $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
        $x.SelectSingleNode('//t:BootTrigger', $ns) | Should -Not -BeNullOrEmpty
        $x.SelectSingleNode('//t:Principal/t:UserId', $ns).InnerText | Should -Be 'S-1-5-19'
        $x.SelectSingleNode('//t:Principal/t:LogonType', $ns).InnerText | Should -Be 'ServiceAccount'
        $x.SelectSingleNode('//t:RestartOnFailure/t:Count', $ns).InnerText | Should -Be '3'
        $x.SelectSingleNode('//t:RestartOnFailure/t:Interval', $ns).InnerText | Should -Be 'PT1M'
        $x.SelectSingleNode('//t:ExecutionTimeLimit', $ns).InnerText | Should -Be 'PT0S'
        $x.SelectSingleNode('//t:Arguments', $ns).InnerText | Should -Match '-BindAddress 127\.0\.0\.1'
    }
    It 'on a loopback install adds no urlacl and no firewall rule' {
        Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) | Out-Null
        Should -Invoke Invoke-ChannelForgeNetsh -Times 0
        Should -Invoke Add-ChannelForgeServerFirewallRule -Times 0
    }
    It 'on a network install reserves the address for LOCAL SERVICE and opens Private and Domain only' {
        Install-ChannelForgeServerTask -Root 'C:\CF' -BindAddress 0.0.0.0 -AllowedHost 10.0.0.5 -DataRoot (New-DataRoot -WithPassword) 3>$null | Out-Null
        Should -Invoke Invoke-ChannelForgeNetsh -Times 1 -ParameterFilter { $Argument -contains 'urlacl' -and $Argument -contains 'add' -and $Argument -contains 'user=NT AUTHORITY\LOCAL SERVICE' -and $Argument -contains 'url=http://+:47850/' }
        Should -Invoke Add-ChannelForgeServerFirewallRule -Times 1
        $script:Spec.Profile | Should -Be 'Private,Domain'
        $script:Spec.Profile | Should -Not -Match 'Public|Any'
    }
    It 'starts first-run in the window only when no password exists, and never registers without one' {
        $d = New-DataRoot
        { Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot $d } | Should -Throw '*Sign-in is not set up*'
        Should -Invoke Invoke-ChannelForgeServerFirstRun -Times 1
        Should -Invoke Register-ChannelForgeServerTask -Times 0
        Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) | Out-Null
        Should -Invoke Invoke-ChannelForgeServerFirstRun -Times 1
    }
    It 'fails closed when the folder permissions are broader than intended' {
        Mock Get-ChannelForgeServerDataAccess { $script:Good + [pscustomobject]@{ Sid = 'S-1-5-32-545'; Rights = 1179817; Type = 'Allow'; Inherited = $false } }
        { Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) } | Should -Throw '*broader than ChannelForge allows*'
        Should -Invoke Register-ChannelForgeServerTask -Times 0
    }
    It 'treats <Name> permissions as too broad' -ForEach @(
        @{ Name = 'inherited'; Entry = @($discoveryGood[0], $discoveryGood[1], [pscustomobject]@{ Sid = 'S-1-5-19'; Rights = 197055; Type = 'Allow'; Inherited = $true }) },
        @{ Name = 'LOCAL SERVICE full control'; Entry = @($discoveryGood[0], $discoveryGood[1], [pscustomobject]@{ Sid = 'S-1-5-19'; Rights = 2032127; Type = 'Allow'; Inherited = $false }) },
        @{ Name = 'missing LOCAL SERVICE'; Entry = @($discoveryGood[0], $discoveryGood[1]) }
    ) {
        { Assert-ChannelForgeServerDataAccess -Entry $Entry } | Should -Throw '*broader*'
    }
    It 'refuses a program folder that ordinary users can change, and accepts a read-only one' {
        $users = [pscustomobject]@{ Sid = 'S-1-5-32-545'; Rights = 1245631; Type = 'Allow'; Inherited = $true }
        { Assert-ChannelForgeServerProgramFolder -Entry @($script:Good + $users) } | Should -Throw '*Ordinary users can change*'
        $readOnly = [pscustomobject]@{ Sid = 'S-1-5-32-545'; Rights = 1179817; Type = 'Allow'; Inherited = $true }
        { Assert-ChannelForgeServerProgramFolder -Entry @($script:Good + $readOnly) } | Should -Not -Throw
        Mock Get-ChannelForgeServerDataAccess { $script:Good + $users }
        { Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) } | Should -Throw '*Ordinary users can change*'
        Should -Invoke Register-ChannelForgeServerTask -Times 0
    }
    It 'refuses a PowerShell 7 that lives in a user folder' {
        Mock Get-ChannelForgeServerRuntimePath { 'C:\Users\someone\AppData\Local\pwsh.exe' }
        { Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) } | Should -Throw '*user folder*'
        Should -Invoke Register-ChannelForgeServerTask -Times 0
    }
    It 'accepts the intended permissions' {
        { Assert-ChannelForgeServerDataAccess -Entry $script:Good } | Should -Not -Throw
    }
    It 'refuses a task that ChannelForge did not make' {
        Mock Get-ChannelForgeServerTaskInfo { [pscustomobject]@{ Description = 'something else' } }
        { Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) } | Should -Throw '*not made by ChannelForge*'
    }
    It 'does nothing with -WhatIf' {
        Install-ChannelForgeServerTask -Root 'C:\CF' -DataRoot (New-DataRoot -WithPassword) -WhatIf | Out-Null
        Should -Invoke Register-ChannelForgeServerTask -Times 0
        Should -Invoke Set-ChannelForgeServerDataAcl -Times 0
    }
    It 'writes only an install record next to the password file, with no secret in it' {
        $d = New-DataRoot -WithPassword
        Install-ChannelForgeServerTask -Root 'C:\CF' -BindAddress 0.0.0.0 -AllowedHost 10.0.0.5 -DataRoot $d 3>$null | Out-Null
        (Get-ChildItem -LiteralPath $d -File).Name | Sort-Object | Should -Be @('admin-password.json', 'server-install.json')
        $text = Get-Content -LiteralPath (Join-Path $d 'server-install.json') -Raw
        $text | Should -Not -Match 'Hash|Salt|setup code|password'
        $script:Xml | Should -Not -Match 'Hash|Salt|setup code'
    }
}

Describe 'Server start-up task uninstall' {
    BeforeEach {
        Mock Test-ChannelForgeElevated { $true }
        Mock Get-ChannelForgeServerTaskInfo { [pscustomobject]@{ Description = 'ChannelForge server at start-up' } }
        Mock Unregister-ChannelForgeServerTask { }
        Mock Invoke-ChannelForgeNetsh { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock Remove-ChannelForgeServerFirewallRule { $script:Removed = $DisplayName }
        $script:Removed = $null
        $script:D = New-DataRoot -WithPassword
        '{"Schema":1,"Port":47850,"UrlAcl":"http://+:47850/","FirewallRule":true}' | Set-Content -LiteralPath (Join-Path $script:D 'server-install.json')
    }

    It 'removes the task, the reservation and the rule it added, and keeps the data' {
        (Uninstall-ChannelForgeServerTask -DataRoot $script:D).DataKept | Should -BeTrue
        Should -Invoke Unregister-ChannelForgeServerTask -Times 1
        Should -Invoke Invoke-ChannelForgeNetsh -Times 1 -ParameterFilter { $Argument -contains 'delete' -and $Argument -contains 'url=http://+:47850/' }
        $script:Removed | Should -Be 'ChannelForge Server (TCP 47850)'
        Test-Path -LiteralPath (Join-Path $script:D 'admin-password.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:D 'server-install.json') | Should -BeFalse
    }
    It 'removes nothing it did not add when the record says loopback only' {
        '{"Schema":1,"Port":47850,"UrlAcl":null,"FirewallRule":false}' | Set-Content -LiteralPath (Join-Path $script:D 'server-install.json')
        Uninstall-ChannelForgeServerTask -DataRoot $script:D | Out-Null
        Should -Invoke Invoke-ChannelForgeNetsh -Times 0
        Should -Invoke Remove-ChannelForgeServerFirewallRule -Times 0
    }
    It 'asks before erasing data and erases it with -Force' {
        Mock Read-Host { 'no' }
        { Uninstall-ChannelForgeServerTask -DataRoot $script:D -RemoveData } | Should -Throw '*Not confirmed*'
        Test-Path -LiteralPath $script:D | Should -BeTrue
        Uninstall-ChannelForgeServerTask -DataRoot $script:D -RemoveData -Force | Out-Null
        Test-Path -LiteralPath $script:D | Should -BeFalse
    }
    It 'will not erase a folder that has no install record' {
        Remove-Item -LiteralPath (Join-Path $script:D 'server-install.json')
        { Uninstall-ChannelForgeServerTask -DataRoot $script:D -RemoveData -Force } | Should -Throw '*no ChannelForge install record*'
        Test-Path -LiteralPath (Join-Path $script:D 'admin-password.json') | Should -BeTrue
    }
    It 'refuses without an administrator window' {
        Mock Test-ChannelForgeElevated { $false }
        { Uninstall-ChannelForgeServerTask -DataRoot $script:D } | Should -Throw '*administrator window*'
        Should -Invoke Unregister-ChannelForgeServerTask -Times 0
    }
}
