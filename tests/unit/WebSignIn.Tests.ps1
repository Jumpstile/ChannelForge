BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Password = 'test-password-one'

    function Start-TestServer {
        param([int]$Port, [string]$Root, [string]$Config, [switch]$SignIn, [string]$LogPath)
        $launcher = Join-Path $Root "server-$Port.ps1"
        $extra = if ($SignIn) { " -RequireSignIn -ConfigRoot '$Config'" } else { '' }
        @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $Port -RepositoryRoot '$Root'$extra") | Set-Content -LiteralPath $launcher
        $startArguments = @{ FilePath = (Get-Command pwsh).Source; ArgumentList = @('-NoProfile', '-File', $launcher); WorkingDirectory = $script:RepoRoot; PassThru = $true }
        if (-not [string]::IsNullOrWhiteSpace($LogPath)) { $startArguments.RedirectStandardOutput = $LogPath; $startArguments.RedirectStandardError = "$LogPath.err" }
        $process = Start-Process @startArguments
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            if ($process.HasExited) { break }
            $tcp = [Net.Sockets.TcpClient]::new()
            try { $tcp.Connect('127.0.0.1', $Port); return $process } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
        }
        throw 'Test server did not start.'
    }

    function Invoke-TestRequest {
        param([int]$Port, [string]$Path, [string]$Method = 'GET', [string]$Body = $null, [string]$Cookie = '')
        $headers = @{}
        if ($Cookie) { $headers['Cookie'] = $Cookie }
        $arguments = @{ Uri = "http://127.0.0.1:$Port$Path"; Method = $Method; Headers = $headers; SkipHttpErrorCheck = $true }
        if ($null -ne $Body) { $arguments.Body = $Body; $arguments.ContentType = 'application/json' }
        Invoke-WebRequest @arguments
    }

    function Get-TestSetCookie {
        param($Response)
        return [string]($Response.Headers['Set-Cookie'] | Select-Object -First 1)
    }

    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null
    & (Get-Module ChannelForge) {
        param($Config, $Password)
        Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000) | Out-Null
    } $script:Config $script:Password
    $script:OnPort = 18871
    $script:OffPort = 18872
    # The sign-in server's log files live outside the test folder so cleanup of the test folder can never be blocked by them.
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-signin-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $script:OnLog = Join-Path $script:LogDir 'on.log'
    $script:OnServer = Start-TestServer -Port $script:OnPort -Root $script:Root -Config $script:Config -SignIn -LogPath $script:OnLog
    $script:OffServer = Start-TestServer -Port $script:OffPort -Root $script:Root -Config $script:Config
}

AfterAll {
    foreach ($server in @($script:OnServer, $script:OffServer)) {
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill() }
        # Wait until each server has really stopped so its log files are released before the test folder is removed.
        if ($null -ne $server) { $server.WaitForExit(10000) | Out-Null; $server.Dispose() }
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'Sign-in mode off (the default)' {
    It 'serves existing routes with no sign-in' {
        (Invoke-TestRequest -Port $script:OffPort -Path '/health').StatusCode | Should -Be 200
        (Invoke-TestRequest -Port $script:OffPort -Path '/api/status').StatusCode | Should -Be 200
        (Invoke-TestRequest -Port $script:OffPort -Path '/api/lineup/channels').StatusCode | Should -Not -Be 401
        (Invoke-TestRequest -Port $script:OffPort -Path '/api/auth/session').StatusCode | Should -Be 404
    }
}

Describe 'Sign-in mode on' {
    It 'refuses a data route with no cookie, with no data' {
        $response = Invoke-TestRequest -Port $script:OnPort -Path '/api/status'
        $response.StatusCode | Should -Be 401
        ($response.Content | ConvertFrom-Json).Message | Should -Be 'Sign in is required.'
        $response.Content | Should -Not -Match 'LineupStatus'
    }

    It 'serves the health route without sign-in and without data' {
        $response = Invoke-TestRequest -Port $script:OnPort -Path '/health'
        $response.StatusCode | Should -Be 200
        ($response.Content | ConvertFrom-Json).Status | Should -Be 'ok'
    }

    It 'refuses a wrong password with the same message every time and sets no cookie' {
        $first = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body '{"password":"wrong-one"}'
        $second = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body '{"password":"another-wrong"}'
        $garbage = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body 'not json'
        foreach ($response in @($first, $second, $garbage)) {
            $response.StatusCode | Should -Be 401
            ($response.Content | ConvertFrom-Json).Message | Should -Be 'That password did not work.'
            Get-TestSetCookie $response | Should -BeNullOrEmpty
        }
        $second.Content | Should -Be $first.Content
    }

    It 'signs in with the right password, opens the data route, and sign-out closes it again' {
        $signIn = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body (@{ password = $script:Password } | ConvertTo-Json -Compress)
        $signIn.StatusCode | Should -Be 200
        $setCookie = Get-TestSetCookie $signIn
        $setCookie | Should -Match '; HttpOnly'
        $setCookie | Should -Match '; SameSite=Strict'
        $setCookie | Should -Not -Match 'Secure'
        $cookie = ($setCookie -split ';')[0]
        $cookie | Should -Match '^cf_session=[A-Za-z0-9_-]{43}$'

        (Invoke-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie $cookie).StatusCode | Should -Be 200
        (Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/session' -Cookie $cookie).Content | Should -Match '"SignedIn":true'

        $signOut = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-out' -Method POST -Body '{}' -Cookie $cookie
        $signOut.StatusCode | Should -Be 200
        Get-TestSetCookie $signOut | Should -Match 'Max-Age=0'
        (Invoke-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie $cookie).StatusCode | Should -Be 401
        (Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/session' -Cookie $cookie).Content | Should -Match '"SignedIn":false'
    }

    It 'refuses an unknown or tampered token' {
        $signIn = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body (@{ password = $script:Password } | ConvertTo-Json -Compress)
        $token = (((Get-TestSetCookie $signIn) -split ';')[0] -split '=', 2)[1]
        $tampered = $token.Substring(0, 42) + $(if ($token[42] -eq 'A') { 'B' } else { 'A' })
        (Invoke-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie "cf_session=$tampered").StatusCode | Should -Be 401
        (Invoke-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie ('cf_session=' + ('x' * 43))).StatusCode | Should -Be 401
        (Invoke-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie "cf_session=$token").StatusCode | Should -Be 200
    }

    It 'keeps the password, token and cookie out of every 401 body and out of the server log' {
        $signIn = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body (@{ password = $script:Password } | ConvertTo-Json -Compress)
        $token = (((Get-TestSetCookie $signIn) -split ';')[0] -split '=', 2)[1]
        $signIn.Content | Should -Not -Match ([regex]::Escape($token))
        $failure = Invoke-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Body '{"password":"wrong-password-marker"}'
        $failure.Content | Should -Not -Match 'wrong-password-marker'
        $denied = Invoke-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie 'cf_session=cookie-marker-value'
        $denied.Content | Should -Not -Match 'cookie-marker-value'
        $log = (Get-Content -Raw -LiteralPath $script:OnLog) + (Get-Content -Raw -LiteralPath "$($script:OnLog).err")
        foreach ($secret in @($script:Password, $token, 'wrong-password-marker', 'cookie-marker-value')) {
            $log | Should -Not -Match ([regex]::Escape($secret))
        }
    }
}

Describe 'Session expiry' {
    It 'refuses a session that was idle too long or has lived too long' {
        $results = & (Get-Module ChannelForge) {
            $store = @{}
            $start = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
            $limits = Get-ChannelForgeWebSessionLimits
            $idle = New-ChannelForgeWebSession -Store $store -Now $start
            $long = New-ChannelForgeWebSession -Store $store -Now $start
            $fresh = New-ChannelForgeWebSession -Store $store -Now $start
            [pscustomobject]@{
                IdleExpired = $null -eq (Get-ChannelForgeWebSession -Store $store -Token $idle -Now ($start + $limits.IdleTimeout + [TimeSpan]::FromSeconds(1)))
                # Keep using the second session so it is never idle (11h45m), then pass the maximum age.
                KeptAlive = & { $alive = $true; for ($minute = 20; $minute -le 705 -and $alive; $minute += 20) { $alive = $null -ne (Get-ChannelForgeWebSession -Store $store -Token $long -Now ($start + [TimeSpan]::FromMinutes($minute))) }; $alive }
                MaxExpired = $null -eq (Get-ChannelForgeWebSession -Store $store -Token $long -Now ($start + $limits.MaximumLifetime + [TimeSpan]::FromSeconds(1)))
                FreshStillValid = $null -ne (Get-ChannelForgeWebSession -Store $store -Token $fresh -Now ($start + [TimeSpan]::FromMinutes(20)))
            }
        }
        $results.IdleExpired | Should -BeTrue
        $results.KeptAlive | Should -BeTrue
        $results.MaxExpired | Should -BeTrue
        $results.FreshStillValid | Should -BeTrue
    }
}
