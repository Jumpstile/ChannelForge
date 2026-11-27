BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Password = 'test-password-one'
    $script:NewPassword = 'test-password-two-new'
    $script:Port = 18879
    $script:ResetPort = 18880
    $script:Servers = @()

    function Start-TestServer {
        param([int]$Port, [string]$Root, [string]$Config, [string]$LogPath)
        $launcher = Join-Path $Root "server-$Port.ps1"
        @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $Port -RepositoryRoot '$Root' -RequireSignIn -ConfigRoot '$Config'") | Set-Content -LiteralPath $launcher
        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput $LogPath -RedirectStandardError "$LogPath.err"
        $script:Servers += $process
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            if ($process.HasExited) { break }
            $tcp = [Net.Sockets.TcpClient]::new()
            try { $tcp.Connect('127.0.0.1', $Port); return $process } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
        }
        throw 'Test server did not start.'
    }

    function Invoke-TestPost {
        param([int]$Port, [string]$Path, [hashtable]$Body, [string]$Cookie = '')
        $headers = @{ Origin = "http://127.0.0.1:$Port" }
        if ($Cookie) { $headers.Cookie = $Cookie }
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port$Path" -Method POST -Headers $headers -Body ($Body | ConvertTo-Json -Compress) -ContentType 'application/json' -SkipHttpErrorCheck
    }

    function Get-TestSession {
        # Signs in and returns the cookie to send back, or $null when sign-in fails.
        param([string]$Password)
        $r = Invoke-TestPost -Port $script:Port -Path '/api/auth/sign-in' -Body @{ password = $Password }
        if ($r.StatusCode -ne 200) { return $null }
        return (@($r.Headers['Set-Cookie'])[0] -split ';')[0]
    }

    function Test-TestSignedIn {
        param([string]$Cookie)
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:Port)/api/auth/session" -Headers @{ Cookie = $Cookie } -SkipHttpErrorCheck
        return [bool]($r.Content | ConvertFrom-Json).SignedIn
    }

    function Send-Change {
        param([string]$Cookie, [string]$Current, [string]$New)
        Invoke-TestPost -Port $script:Port -Path '/api/auth/change-password' -Cookie $Cookie -Body @{ currentPassword = $Current; newPassword = $New }
    }

    function New-TestRecord {
        param([string]$Config, [string]$Password)
        & (Get-Module ChannelForge) {
            param($Config, $Password)
            Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000) | Out-Null
        } $Config $Password
    }

    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null
    New-TestRecord -Config $script:Config -Password $script:Password
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-change-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    Start-TestServer -Port $script:Port -Root $script:Root -Config $script:Config -LogPath (Join-Path $script:LogDir 'main.log') | Out-Null
}

AfterAll {
    foreach ($server in $script:Servers) {
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill($true) }
        if ($null -ne $server) { $server.WaitForExit(10000) | Out-Null; $server.Dispose() }
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'Change password' {
    It 'is refused without a session' {
        $r = Send-Change -Cookie '' -Current $script:Password -New $script:NewPassword
        $r.StatusCode | Should -Be 401
        (Get-TestSession -Password $script:Password) | Should -Not -BeNullOrEmpty
    }

    It 'refuses a short or a common new password with a plain message and keeps the old password' {
        $cookie = Get-TestSession -Password $script:Password
        $short = Send-Change -Cookie $cookie -Current $script:Password -New 'short'
        $short.StatusCode | Should -Be 400
        $short.Content | Should -Match 'at least 12'
        $common = Send-Change -Cookie $cookie -Current $script:Password -New 'password12345'
        $common.StatusCode | Should -Be 400
        $common.Content | Should -Match 'too common'
        $short.Content + $common.Content | Should -Not -Match 'password12345|short"|test-password'
        (Get-TestSession -Password $script:Password) | Should -Not -BeNullOrEmpty
    }

    It 'changes the password, ends other sessions and keeps the changing session' {
        $mine = Get-TestSession -Password $script:Password
        $other = Get-TestSession -Password $script:Password
        $r = Send-Change -Cookie $mine -Current $script:Password -New $script:NewPassword
        $r.StatusCode | Should -Be 200
        Test-TestSignedIn -Cookie $mine | Should -BeTrue
        Test-TestSignedIn -Cookie $other | Should -BeFalse
        (Get-TestSession -Password $script:Password) | Should -BeNullOrEmpty
        (Get-TestSession -Password $script:NewPassword) | Should -Not -BeNullOrEmpty
    }

    It 'refuses a wrong current password uniformly, counts it, and never echoes a password' {
        $cookie = Get-TestSession -Password $script:NewPassword
        $codes = 1..5 | ForEach-Object { (Send-Change -Cookie $cookie -Current 'wrong-password-x' -New 'another-new-password').StatusCode }
        $codes | Should -Be @(401, 401, 401, 401, 401)
        $wait = Send-Change -Cookie $cookie -Current $script:NewPassword -New 'another-new-password'
        $wait.StatusCode | Should -Be 429
        $wait.Content | Should -Not -Match 'wrong-password-x|another-new-password|test-password'
    }
}

Describe 'Reset-ChannelForgeAdminPassword' {
    BeforeAll {
        function New-TestUsers {
            # users.json with the given name/role/disabled entries, all with the test password.
            param([string]$Config, [object[]]$Spec)
            & (Get-Module ChannelForge) {
                param($Config, $Spec, $Password)
                $users = @($Spec | ForEach-Object {
                        $user = New-ChannelForgeUserRecord -Name $_.Name -Role $_.Role -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000)
                        $user.Disabled = [bool]$_.Disabled
                        $user
                    })
                Write-ChannelForgeUserStore -ConfigRoot $Config -User $users | Out-Null
            } $Config $Spec $script:Password
        }
        function Get-TestUsers { param([string]$Config) (Get-Content -Raw -LiteralPath (Join-Path $Config 'users.json') | ConvertFrom-Json -DateKind String).Users }
        function Invoke-TestReset {
            # Runs the console reset; returns the result and the temporary password the console showed.
            param([string]$Config, [string]$Name = '')
            $all = @(Reset-ChannelForgeAdminPassword -ConfigRoot $Config -Name $Name -Confirm:$false 6>&1)
            $line = @($all | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })[0]
            [pscustomobject]@{ Result = @($all | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })[0]; Temporary = if ($line) { ([string]$line.MessageData.Message -split ': ')[-1] } else { '' } }
        }
        function Test-TestPasswordMatches {
            param([string]$Config, [string]$Name, [string]$Candidate)
            & (Get-Module ChannelForge) { param($c, $n, $p) Test-ChannelForgeAdminPassword -Password $p -Record (@((Read-ChannelForgeUserStore -ConfigRoot $c).Users | Where-Object Name -ieq $n)[0]).Password } $Config $Name $Candidate
        }
        function Get-TestNamedSession {
            param([int]$Port, [string]$Name, [string]$Password)
            $r = Invoke-TestPost -Port $Port -Path '/api/auth/sign-in' -Body @{ name = $Name; password = $Password }
            if ($r.StatusCode -ne 200) { return $null }
            return (@($r.Headers['Set-Cookie'])[0] -split ';')[0]
        }
        function Test-TestSessionActive {
            param([int]$Port, [string]$Cookie)
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/auth/session" -Headers @{ Cookie = $Cookie } -SkipHttpErrorCheck
            return [bool]($r.Content | ConvertFrom-Json).SignedIn
        }
        function Get-TestRefusal {
            param([scriptblock]$Action)
            try { & $Action; return '' } catch { return $_.Exception.Message }
        }
    }
    BeforeEach {
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $true }
        $script:ResetConfig = Join-Path $TestDrive ('reset-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:ResetConfig | Out-Null
        Set-Content -LiteralPath (Join-Path $script:ResetConfig 'lineup.json') -Value '{"keep":true}'
    }

    It 'resets one named Admin, keeps every other user exactly, and audits without a password' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' }, @{ Name = 'Dad'; Role = 'admin' }, @{ Name = 'kid'; Role = 'viewer' })
        $before = Get-TestUsers -Config $script:ResetConfig
        $run = Invoke-TestReset -Config $script:ResetConfig -Name 'mom'
        $run.Result.Reset | Should -BeTrue
        $run.Temporary | Should -Match '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$'
        $after = Get-TestUsers -Config $script:ResetConfig
        $after.Count | Should -Be 3
        $after[0].MustChange | Should -BeTrue
        $after[0].PasswordChangedUtc | Should -Not -Be $before[0].PasswordChangedUtc
        Test-TestPasswordMatches -Config $script:ResetConfig -Name 'Mom' -Candidate $run.Temporary | Should -BeTrue
        Test-TestPasswordMatches -Config $script:ResetConfig -Name 'Mom' -Candidate $script:Password | Should -BeFalse
        ($after[1] | ConvertTo-Json -Depth 5 -Compress) | Should -Be ($before[1] | ConvertTo-Json -Depth 5 -Compress)
        ($after[2] | ConvertTo-Json -Depth 5 -Compress) | Should -Be ($before[2] | ConvertTo-Json -Depth 5 -Compress)
        $audit = Get-Content -Raw -LiteralPath (Join-Path $script:ResetConfig 'audit.jsonl')
        $audit | Should -Match '"Event":"console-reset"'
        $audit | Should -Match '"ActorName":"console"'
        $audit | Should -Match '"TargetName":"Mom"'
        $audit | Should -Not -Match ([regex]::Escape($run.Temporary))
        $audit | Should -Not -Match 'Hash|Salt'
        (Get-Content -Raw -LiteralPath (Join-Path $script:ResetConfig 'users.json')) | Should -Not -Match ([regex]::Escape($run.Temporary))
    }

    It 'uses the only Admin when -Name is missing' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' }, @{ Name = 'kid'; Role = 'viewer' })
        $run = Invoke-TestReset -Config $script:ResetConfig
        $run.Result.Reset | Should -BeTrue
        Test-TestPasswordMatches -Config $script:ResetConfig -Name 'Mom' -Candidate $run.Temporary | Should -BeTrue
    }

    It 'refuses several Admins without -Name, lists only Admin names, and changes nothing' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' }, @{ Name = 'Dad'; Role = 'admin' }, @{ Name = 'kid'; Role = 'viewer' })
        $file = Join-Path $script:ResetConfig 'users.json'
        $hash = (Get-FileHash -LiteralPath $file).Hash
        $message = Get-TestRefusal { Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Confirm:$false }
        $message | Should -Match 'Dad, Mom'
        $message | Should -Match '-Name'
        $message | Should -Not -Match 'kid'
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $hash
    }

    It 'refuses a user who is not an Admin and a name that does not exist' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' }, @{ Name = 'kid'; Role = 'viewer' })
        $file = Join-Path $script:ResetConfig 'users.json'
        $hash = (Get-FileHash -LiteralPath $file).Hash
        { Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Name 'kid' -Confirm:$false } | Should -Throw '*not an Admin*'
        { Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Name 'nobody' -Confirm:$false } | Should -Throw '*no user named*'
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $hash
    }

    It 'recovers a disabled Admin' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin'; Disabled = $true }, @{ Name = 'Dad'; Role = 'admin' })
        (Invoke-TestReset -Config $script:ResetConfig -Name 'Mom').Result.Reset | Should -BeTrue
        $after = Get-TestUsers -Config $script:ResetConfig
        $after[0].Disabled | Should -BeFalse
        $after[0].MustChange | Should -BeTrue
    }

    It 'refuses an old session, accepts the temporary password, and needs no server restart' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' }, @{ Name = 'kid'; Role = 'viewer' })
        $port = $script:ResetPort
        Start-TestServer -Port $port -Root $script:Root -Config $script:ResetConfig -LogPath (Join-Path $script:LogDir 'named.log') | Out-Null
        $old = Get-TestNamedSession -Port $port -Name 'Mom' -Password $script:Password
        $kid = Get-TestNamedSession -Port $port -Name 'kid' -Password $script:Password
        $old | Should -Not -BeNullOrEmpty
        $run = Invoke-TestReset -Config $script:ResetConfig -Name 'Mom'
        Test-TestSessionActive -Port $port -Cookie $old | Should -BeFalse
        Get-TestNamedSession -Port $port -Name 'Mom' -Password $script:Password | Should -BeNullOrEmpty
        Get-TestNamedSession -Port $port -Name 'Mom' -Password $run.Temporary | Should -Not -BeNullOrEmpty
        Test-TestSessionActive -Port $port -Cookie $kid | Should -BeTrue
    }

    It 'with -RemoveAllSignInData removes only the sign-in files, audits it, and the next start is in setup state' {
        New-TestRecord -Config $script:ResetConfig -Password $script:Password
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' })
        Set-Content -LiteralPath (Join-Path $script:ResetConfig 'admin-password.json.migrated') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:ResetConfig 'user-settings.json') -Value '{}'
        $result = Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -RemoveAllSignInData -Confirm:$false
        $result.Reset | Should -BeTrue
        $result.Message | Should -Match 'restart'
        foreach ($gone in 'users.json', 'admin-password.json', 'admin-password.json.migrated') {
            Test-Path -LiteralPath (Join-Path $script:ResetConfig $gone) | Should -BeFalse
        }
        foreach ($kept in 'lineup.json', 'user-settings.json') {
            Test-Path -LiteralPath (Join-Path $script:ResetConfig $kept) | Should -BeTrue
        }
        (Get-Content -Raw -LiteralPath (Join-Path $script:ResetConfig 'audit.jsonl')) | Should -Match '"Event":"console-reset".*"TargetName":"all"'
        Start-TestServer -Port ($script:ResetPort + 1) -Root $script:Root -Config $script:ResetConfig -LogPath (Join-Path $script:LogDir 'reset.log') | Out-Null
        $page = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:ResetPort + 1)/first-run" -SkipHttpErrorCheck
        $page.StatusCode | Should -Be 200
        $page.Content | Should -Match 'first-time setup'
    }

    It 'says so and changes nothing when there is no sign-in file' {
        $result = Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Confirm:$false
        $result.Reset | Should -BeFalse
        $result.Message | Should -Match 'no sign-in file'
        (Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -RemoveAllSignInData -Confirm:$false).Reset | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:ResetConfig 'lineup.json') | Should -BeTrue
    }

    It 'refuses when not elevated and leaves the file' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' })
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $false }
        { Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Confirm:$false } | Should -Throw '*administrator*'
        Test-Path -LiteralPath (Join-Path $script:ResetConfig 'users.json') | Should -BeTrue
    }

    It 'does nothing under -WhatIf' {
        New-TestUsers -Config $script:ResetConfig -Spec @(@{ Name = 'Mom'; Role = 'admin' })
        $hash = (Get-FileHash -LiteralPath (Join-Path $script:ResetConfig 'users.json')).Hash
        (Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -WhatIf).Reset | Should -BeFalse
        (Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -RemoveAllSignInData -WhatIf).Reset | Should -BeFalse
        (Get-FileHash -LiteralPath (Join-Path $script:ResetConfig 'users.json')).Hash | Should -Be $hash
    }
}
