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
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill() }
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
    BeforeEach {
        $script:ResetConfig = Join-Path $TestDrive ('reset-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:ResetConfig | Out-Null
        Set-Content -LiteralPath (Join-Path $script:ResetConfig 'lineup.json') -Value '{"keep":true}'
    }

    It 'removes only the password file and the next start is in setup state' {
        New-TestRecord -Config $script:ResetConfig -Password $script:Password
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $true }
        $result = Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Confirm:$false
        $result.Reset | Should -BeTrue
        $result.Message | Should -Match 'admin password reset'
        $result.Message | Should -Match 'restart'
        Test-Path -LiteralPath (Join-Path $script:ResetConfig 'admin-password.json') | Should -BeFalse
        Get-Content -Raw -LiteralPath (Join-Path $script:ResetConfig 'lineup.json') | Should -Match 'keep'
        $log = Join-Path $script:LogDir 'reset.log'
        Start-TestServer -Port $script:ResetPort -Root $script:Root -Config $script:ResetConfig -LogPath $log | Out-Null
        $page = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:ResetPort)/first-run" -SkipHttpErrorCheck
        $page.StatusCode | Should -Be 200
        $page.Content | Should -Match 'first-time setup'
    }

    It 'says so and changes nothing when there is no password file' {
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $true }
        $result = Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Confirm:$false
        $result.Reset | Should -BeFalse
        $result.Message | Should -Match 'no admin password file'
        Test-Path -LiteralPath (Join-Path $script:ResetConfig 'lineup.json') | Should -BeTrue
    }

    It 'refuses when not elevated and leaves the file' {
        New-TestRecord -Config $script:ResetConfig -Password $script:Password
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $false }
        { Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -Confirm:$false } | Should -Throw '*administrator*'
        Test-Path -LiteralPath (Join-Path $script:ResetConfig 'admin-password.json') | Should -BeTrue
    }

    It 'does nothing under -WhatIf' {
        New-TestRecord -Config $script:ResetConfig -Password $script:Password
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $true }
        (Reset-ChannelForgeAdminPassword -ConfigRoot $script:ResetConfig -WhatIf).Reset | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:ResetConfig 'admin-password.json') | Should -BeTrue
    }
}
