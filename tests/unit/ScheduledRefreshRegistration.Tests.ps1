BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Helper = Join-Path $script:Root 'src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1'
    $script:Contract = Join-Path $script:Root 'src/ChannelForge/Private/Get-ChannelForgeScheduledOperationContract.ps1'
    $script:Installer = Join-Path $script:Root 'scripts/Install-ChannelForgeScheduledRefresh.ps1'
    $script:Uninstaller = Join-Path $script:Root 'scripts/Uninstall-ChannelForgeScheduledRefresh.ps1'
    $script:Status = Join-Path $script:Root 'scripts/Get-ChannelForgeScheduledRefreshStatus.ps1'
    $script:PolicyExample = Join-Path $script:Root 'config/scheduled-refresh.example.json'
    $script:PolicySchema = Join-Path $script:Root 'schemas/scheduled-refresh-policy.schema.json'
    $script:RegistrationSchema = Join-Path $script:Root 'schemas/scheduled-refresh-registration.schema.json'
    $script:HistorySchema = Join-Path $script:Root 'schemas/scheduled-refresh-history.schema.json'
    . $script:Helper

    function Write-TestJson {
        param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path)
        [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    }

    function New-RegistrationProject {
        $project = Join-Path $TestDrive ('scheduled-registration-' + [guid]::NewGuid().ToString('N'))
        $directories = @('config', 'scripts', 'schemas', 'src/ChannelForge/Private', 'output/operations') | ForEach-Object { Join-Path $project $_ }
        New-Item -ItemType Directory -Force -Path $directories | Out-Null
        Copy-Item -LiteralPath $script:Helper -Destination (Join-Path $project 'src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1')
        Copy-Item -LiteralPath $script:Contract -Destination (Join-Path $project 'src/ChannelForge/Private/Get-ChannelForgeScheduledOperationContract.ps1')
        Copy-Item -LiteralPath (Join-Path $script:Root 'scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1') -Destination (Join-Path $project 'scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1')
        Copy-Item -LiteralPath $script:PolicySchema -Destination (Join-Path $project 'schemas/scheduled-refresh-policy.schema.json')
        Copy-Item -LiteralPath $script:RegistrationSchema -Destination (Join-Path $project 'schemas/scheduled-refresh-registration.schema.json')
        Copy-Item -LiteralPath $script:HistorySchema -Destination (Join-Path $project 'schemas/scheduled-refresh-history.schema.json')
        $policy = Get-Content -LiteralPath $script:PolicyExample -Raw | ConvertFrom-Json
        $policy.Enabled = $true
        $policy.JitterMinutes = 0
        Write-TestJson -Value $policy -Path (Join-Path $project 'config/scheduled-refresh.local.json')
        [pscustomobject]@{ Root = $project; Task = $null }
    }

    function Remove-TestTask {
        param([Parameter(Mandatory)][string]$TaskName)
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\ChannelForge\' -Confirm:$false -ErrorAction SilentlyContinue
    }
}

Describe 'Windows Task Scheduler registration contract' {
    It 'uses the same root digest for case variants of a canonical Windows root' {
        $project = New-RegistrationProject
        $first = Resolve-ChannelForgeScheduledOperationRoot -Root $project.Root
        $second = Resolve-ChannelForgeScheduledOperationRoot -Root $project.Root.ToLowerInvariant()
        $first.Digest | Should -Be $second.Digest
        (Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $first).TaskName | Should -Match '^ScheduledRefresh-[0-9a-f]{16}$'
    }

    It 'installs, reports, and uninstalls exactly one owned task' {
        $project = New-RegistrationProject
        $result = & $script:Installer -Root $project.Root -Approve
        $result.Status | Should -Be 'Installed'
        $task = Get-ScheduledTask -TaskPath '\ChannelForge\' -TaskName $result.TaskName -ErrorAction Stop
        try {
            $status = & $script:Status -Root $project.Root
            $status.Status | Should -Be 'Installed'
            $status.Contract.Compliant | Should -BeTrue
            Test-Json -Path (Join-Path $project.Root 'output/operations/scheduled-refresh-registration.json') -SchemaFile $script:RegistrationSchema | Should -BeTrue
            (Get-Content -LiteralPath (Join-Path $project.Root 'output/operations/scheduled-refresh-registration.json') -Raw) | Should -Not -Match 'https?://|TOKEN|PASSWORD|C:\\\\Users|C:\\\\REPOS'
        }
        finally {
            & $script:Uninstaller -Root $project.Root -Approve | Out-Null
        }
        Get-ScheduledTask -TaskPath '\ChannelForge\' -TaskName $result.TaskName -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'refuses to replace a foreign task with the owned identity' {
        $project = New-RegistrationProject
        $rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $project.Root
        $identity = Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $rootInfo
        $runtime = Get-ChannelForgeScheduledOperationRuntime
        $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours(3))
        $action = New-ScheduledTaskAction -Execute $runtime.Path -Argument '-NoLogo -NoProfile -Command "exit 0"' -WorkingDirectory $rootInfo.FullPath
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew
        $xml = [string](Export-ScheduledTask -InputObject (New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings))
        Register-ScheduledTask -TaskName $identity.TaskName -TaskPath $identity.TaskPath -Xml $xml -ErrorAction Stop | Out-Null
        try { { & $script:Installer -Root $project.Root -Approve } | Should -Throw '*ForeignTask*' }
        finally { Remove-TestTask -TaskName $identity.TaskName }
    }

    It 'stores explicit UTC boundaries unchanged on both sides of a DST boundary' {
        $project = New-RegistrationProject
        $rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $project.Root
        $policyInfo = Get-ChannelForgeScheduledOperationPolicyInfo -Path (Join-Path $project.Root 'config/scheduled-refresh.local.json') -SchemaPath $script:PolicySchema
        $identity = Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $rootInfo
        $runtime = Get-ChannelForgeScheduledOperationRuntime
        $wrapper = Join-Path $project.Root 'scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1'
        $boundaries = @([datetimeoffset]'2027-03-13T03:00:00Z', [datetimeoffset]'2027-11-06T03:00:00Z')
        $names = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($boundary in $boundaries) {
                $xml = New-ChannelForgeScheduledOperationTaskXml -Identity $identity -RootInfo $rootInfo -PolicyInfo $policyInfo -RuntimePath $runtime.Path -WrapperPath $wrapper -StartBoundaryUtc $boundary
                $name = 'ChannelForge-DstContract-' + [guid]::NewGuid().ToString('N')
                Register-ScheduledTask -TaskName $name -TaskPath '\ChannelForge\' -Xml $xml -ErrorAction Stop | Out-Null
                $names.Add($name)
                $saved = Get-ChannelForgeScheduledOperationTaskXml -Task ([pscustomobject]@{ TaskName = $name; TaskPath = '\ChannelForge\' })
                $start = ([xml]$saved).SelectSingleNode('//*[local-name()="StartBoundary"]').InnerText
                $start | Should -Be $boundary.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $start | Should -Match 'Z$'
            }
        }
        finally {
            foreach ($name in $names) { Remove-TestTask -TaskName $name }
        }
    }

    It 'lists no owned task and reports a missing task without mutation' {
        $project = New-RegistrationProject
        $before = Get-ChildItem -LiteralPath $project.Root -Force -Recurse | Select-Object FullName, Length
        $list = & (Join-Path $script:Root 'scripts/Get-ChannelForgeScheduledRefreshTask.ps1') -Root $project.Root
        $status = & $script:Status -Root $project.Root
        $list.OwnedTaskCount | Should -Be 0
        $status.Status | Should -Be 'Missing'
        $after = Get-ChildItem -LiteralPath $project.Root -Force -Recurse | Select-Object FullName, Length
        ($after | ConvertTo-Json -Depth 4) | Should -Be ($before | ConvertTo-Json -Depth 4)
    }
    It 'does not use a nonexistent local-timezone trigger parameter' {
        (Get-Content -LiteralPath $script:Installer -Raw) | Should -Not -Match 'New-ScheduledTaskTrigger[^\r\n]*-TimeZone'
        (Get-Content -LiteralPath $script:Helper -Raw) | Should -Not -Match 'New-ScheduledTaskTrigger[^\r\n]*-TimeZone'
    }
}
