BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Password = 'test-password-one'

    function Start-TestServer {
        param([int]$Port, [string]$Root, [string]$Config, [string]$LogPath)
        $launcher = Join-Path $Root "server-$Port.ps1"
        @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $Port -RepositoryRoot '$Root' -RequireSignIn -ConfigRoot '$Config'") | Set-Content -LiteralPath $launcher
        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput $LogPath -RedirectStandardError "$LogPath.err"
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            if ($process.HasExited) { break }
            $tcp = [Net.Sockets.TcpClient]::new()
            try { $tcp.Connect('127.0.0.1', $Port); return $process } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
        }
        throw 'Test server did not start.'
    }

    function Get-TestSetupCode {
        param([string]$LogPath)
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            $text = if (Test-Path -LiteralPath $LogPath) { [string](Get-Content -Raw -LiteralPath $LogPath) } else { '' }
            if ($text -match 'setup code: ([A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4})') { return $Matches[1] }
            Start-Sleep -Milliseconds 100
        }
        throw 'No setup code in the console output.'
    }

    function Invoke-TestRequest {
        param([int]$Port, [string]$Path, [string]$Body)
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port$Path" -Method POST -Headers @{ Origin = "http://127.0.0.1:$Port" } -Body $Body -ContentType 'application/json' -SkipHttpErrorCheck
    }

    function Send-SignIn {
        param([string]$Password)
        Invoke-TestRequest -Port $script:SignInPort -Path '/api/auth/sign-in' -Body (@{ password = $Password } | ConvertTo-Json -Compress)
    }

    function Send-Setup {
        param([string]$Code)
        Invoke-TestRequest -Port $script:SetupPort -Path '/first-run/submit' -Body (@{ code = $Code; password = 'test-first-password-1' } | ConvertTo-Json -Compress)
    }

    $script:Root = Join-Path $TestDrive 'root'
    $script:SignInConfig = Join-Path $TestDrive 'config-signin'
    $script:SetupConfig = Join-Path $TestDrive 'config-setup'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:SignInConfig, $script:SetupConfig | Out-Null
    & (Get-Module ChannelForge) {
        param($Config, $Password)
        Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000) | Out-Null
    } $script:SignInConfig $script:Password
    $script:SignInPort = 18875
    $script:SetupPort = 18876
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-limit-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $script:SignInServer = Start-TestServer -Port $script:SignInPort -Root $script:Root -Config $script:SignInConfig -LogPath (Join-Path $script:LogDir 'signin.log')
    $script:SetupLog = Join-Path $script:LogDir 'setup.log'
    $script:SetupServer = Start-TestServer -Port $script:SetupPort -Root $script:Root -Config $script:SetupConfig -LogPath $script:SetupLog
    $script:Code = Get-TestSetupCode -LogPath $script:SetupLog
}

AfterAll {
    foreach ($server in @($script:SignInServer, $script:SetupServer)) {
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill() }
        if ($null -ne $server) { $server.WaitForExit(10000) | Out-Null; $server.Dispose() }
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'Repeated wrong passwords' {
    It 'lets 4 wrong tries and then the right password sign in' {
        1..4 | ForEach-Object { (Send-SignIn -Password 'wrong-password').StatusCode | Should -Be 401 }
        (Send-SignIn -Password $script:Password).StatusCode | Should -Be 200
    }

    It 'starts a wait on the 5th wrong try, refuses even the right password, then recovers' {
        1..5 | ForEach-Object { (Send-SignIn -Password 'wrong-password').StatusCode | Should -Be 401 }
        $refused = Send-SignIn -Password 'wrong-password'
        $refused.StatusCode | Should -Be 429
        [int]($refused.Headers['Retry-After'] | Select-Object -First 1) | Should -BeGreaterThan 0
        $refused.Content | Should -Not -Match 'wrong-password'
        $refused.Content | Should -Not -Match '127\.0\.0\.1'
        $correct = Send-SignIn -Password $script:Password
        $correct.StatusCode | Should -Be 429
        $correct.Content | Should -Not -Match $script:Password
        Start-Sleep -Milliseconds 1500
        (Send-SignIn -Password $script:Password).StatusCode | Should -Be 200
        # The count was cleared, so a wrong try is an ordinary 401 again.
        (Send-SignIn -Password 'wrong-password').StatusCode | Should -Be 401
    }
}

Describe 'Repeated wrong setup codes' {
    It 'limits wrong codes on first-run submit and still accepts the right code afterwards' {
        1..5 | ForEach-Object { (Send-Setup -Code 'AAAA-AAAA-AAAA').StatusCode | Should -Be 401 }
        $refused = Send-Setup -Code 'AAAA-AAAA-AAAA'
        $refused.StatusCode | Should -Be 429
        $refused.Content | Should -Not -Match '127\.0\.0\.1'
        $refused.Content | Should -Not -Match $script:Code
        $refused.Content | Should -Not -Match 'AAAA-AAAA-AAAA'
        (Send-Setup -Code $script:Code).StatusCode | Should -Be 429
        Start-Sleep -Milliseconds 1500
        (Send-Setup -Code $script:Code).StatusCode | Should -Be 200
    }
}

Describe 'Limiter rules' {
    It 'doubles the wait up to the cap and does not block a second address' {
        $result = & (Get-Module ChannelForge) {
            $settings = Get-ChannelForgeSignInLimitSettings
            $limiter = New-ChannelForgeSignInLimiter
            $now = [datetime]'2026-01-01T00:00:00Z'
            $waits = foreach ($try in 1..($settings.FailureThreshold + 14)) {
                Register-ChannelForgeSignInFailure -Limiter $limiter -Address 'a' -Now $now -Settings $settings
                Get-ChannelForgeSignInWaitSeconds -Limiter $limiter -Address 'a' -Now $now
            }
            [pscustomobject]@{ Waits = @($waits); Other = (Get-ChannelForgeSignInWaitSeconds -Limiter $limiter -Address 'b' -Now $now); Cap = $settings.CapSeconds }
        }
        $result.Waits[3] | Should -Be 0
        $result.Waits[4] | Should -Be 1
        $result.Waits[5] | Should -Be 2
        $result.Waits[6] | Should -Be 4
        ($result.Waits | Measure-Object -Maximum).Maximum | Should -Be $result.Cap
        $result.Other | Should -Be 0
    }

    It 'slows every address when many addresses fail' {
        $wait = & (Get-Module ChannelForge) {
            $settings = Get-ChannelForgeSignInLimitSettings
            $limiter = New-ChannelForgeSignInLimiter
            $now = [datetime]'2026-01-01T00:00:00Z'
            foreach ($n in 1..$settings.GlobalFailureThreshold) { Register-ChannelForgeSignInFailure -Limiter $limiter -Address "addr$n" -Now $now -Settings $settings }
            Get-ChannelForgeSignInWaitSeconds -Limiter $limiter -Address 'a-new-address' -Now $now
        }
        $wait | Should -BeGreaterThan 0
    }

    It 'keeps the everyone-wait short and forgets old wrong tries after a quiet period' {
        $result = & (Get-Module ChannelForge) {
            $settings = Get-ChannelForgeSignInLimitSettings
            $limiter = New-ChannelForgeSignInLimiter
            $now = [datetime]'2026-01-01T00:00:00Z'
            foreach ($n in 1..400) { Register-ChannelForgeSignInFailure -Limiter $limiter -Address "addr$n" -Now $now -Settings $settings }
            $busy = Get-ChannelForgeSignInWaitSeconds -Limiter $limiter -Address 'admin-address' -Now $now
            $later = $now.AddSeconds($settings.QuietResetSeconds + 1)
            Register-ChannelForgeSignInFailure -Limiter $limiter -Address 'admin-address' -Now $later -Settings $settings
            [pscustomobject]@{ Busy = $busy; GlobalCap = $settings.GlobalCapSeconds; After = (Get-ChannelForgeSignInWaitSeconds -Limiter $limiter -Address 'admin-address' -Now $later); Count = $limiter.GlobalFailures }
        }
        $result.Busy | Should -BeGreaterThan 0
        $result.Busy | Should -BeLessOrEqual $result.GlobalCap
        $result.Count | Should -Be 1
        $result.After | Should -Be 0
    }

    It 'keeps at most the allowed number of tracked addresses' {
        $count = & (Get-Module ChannelForge) {
            $settings = Get-ChannelForgeSignInLimitSettings
            $limiter = New-ChannelForgeSignInLimiter
            $now = [datetime]'2026-01-01T00:00:00Z'
            foreach ($n in 1..($settings.MaxTrackedAddresses + 25)) { Register-ChannelForgeSignInFailure -Limiter $limiter -Address "addr$n" -Now $now.AddSeconds($n) -Settings $settings }
            $limiter.Addresses.Count
        }
        $count | Should -Be 1000
    }
}
