BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:GoodPassword = 'test-first-password-1'

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
        param([int]$Port, [string]$Path, [string]$Method = 'GET', [string]$Body = $null, [string]$Cookie = '')
        $arguments = @{ Uri = "http://127.0.0.1:$Port$Path"; Method = $Method; Headers = @{}; SkipHttpErrorCheck = $true }
        if ($Method -ne 'GET') { $arguments.Headers['Origin'] = "http://127.0.0.1:$Port" }
        if ($Cookie) { $arguments.Headers['Cookie'] = $Cookie }
        if ($null -ne $Body) { $arguments.Body = $Body; $arguments.ContentType = 'application/json' }
        Invoke-WebRequest @arguments
    }

    function Send-TestSetup {
        param([string]$Code, [string]$Password)
        Invoke-TestRequest -Port $script:SetupPort -Path '/first-run/submit' -Method POST -Body (@{ code = $Code; password = $Password } | ConvertTo-Json -Compress)
    }

    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null
    $script:SetupPort = 18873
    $script:OffPort = 18874
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-firstrun-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $script:SetupLog = Join-Path $script:LogDir 'setup.log'
    $script:SetupServer = Start-TestServer -Port $script:SetupPort -Root $script:Root -Config $script:Config -LogPath $script:SetupLog
    $script:Code = Get-TestSetupCode -LogPath $script:SetupLog
    $script:PasswordFile = Join-Path $script:Config 'admin-password.json'
    # Mode off: a plain server with no sign-in.
    $offLauncher = Join-Path $script:Root 'off.ps1'
    function Wait-TestPort {
        param([int]$Port)
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            $tcp = [Net.Sockets.TcpClient]::new()
            try { $tcp.Connect('127.0.0.1', $Port); return } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
        }
    }
    @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $script:OffPort -RepositoryRoot '$script:Root'") | Set-Content -LiteralPath $offLauncher
    $script:OffServer = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $offLauncher) -WorkingDirectory $script:RepoRoot -PassThru -WindowStyle Hidden
    Wait-TestPort -Port $script:OffPort
}

AfterAll {
    foreach ($server in @($script:SetupServer, $script:OffServer)) {
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill() }
        if ($null -ne $server) { $server.WaitForExit(10000) | Out-Null; $server.Dispose() }
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'First-run with sign-in mode off' {
    It 'does not serve the first-run page and changes nothing else' {
        (Invoke-TestRequest -Port $script:OffPort -Path '/first-run').StatusCode | Should -Be 404
        (Invoke-TestRequest -Port $script:OffPort -Path '/health').StatusCode | Should -Be 200
    }
}

Describe 'Setup state' {
    It 'answers 401 to data routes, and health still works with no data' {
        (Invoke-TestRequest -Port $script:SetupPort -Path '/api/status').StatusCode | Should -Be 401
        (Invoke-TestRequest -Port $script:SetupPort -Path '/api/auth/sign-in' -Method POST -Body '{"password":"x"}').StatusCode | Should -Be 401
        $health = Invoke-TestRequest -Port $script:SetupPort -Path '/health'
        $health.StatusCode | Should -Be 200
        ($health.Content | ConvertFrom-Json).Status | Should -Be 'ok'
    }

    It 'serves the first-run page in plain words' {
        $page = Invoke-TestRequest -Port $script:SetupPort -Path '/first-run'
        $page.StatusCode | Should -Be 200
        $page.Content | Should -Match 'printed on the server console'
        $page.Content | Should -Match 'There is no email reset'
        $page.Content | Should -Match 'reset needs access to the server machine'
        $page.Content | Should -Match 'plain HTTP'
        $page.Content | Should -Match 'reverse proxy with HTTPS'
        $page.Content | Should -Not -Match 'class="warn"><b>'
        $page.Content | Should -Not -Match ([regex]::Escape($script:Code))
    }

    It 'warns when the page is opened from a network address over HTTP' {
        $page = & (Get-Module ChannelForge) {
            (Get-ChannelForgeFirstRunResponse -Method GET -RequestPath '/first-run' -Store @{} -Setup @{} -ConfigRoot (Join-Path ([IO.Path]::GetTempPath()) 'cf-no-such-config') -CookieFormat 'x{0}' -RequestHost '192.168.1.20').Body
        }
        $page | Should -Match 'class="warn"><b>Warning:'
    }

    It 'refuses wrong codes with one message every time and writes no file' {
        $first = Send-TestSetup -Code 'AAAA-AAAA-AAAA' -Password $script:GoodPassword
        $second = Send-TestSetup -Code 'not a code' -Password $script:GoodPassword
        $first.StatusCode | Should -Be 401
        ($first.Content | ConvertFrom-Json).Message | Should -Be 'That setup code did not work.'
        $second.Content | Should -Be $first.Content
        Test-Path -LiteralPath $script:PasswordFile | Should -BeFalse
    }

    It 'refuses a short or common password with the rule message and keeps the code usable' {
        $short = Send-TestSetup -Code $script:Code -Password 'short'
        $short.StatusCode | Should -Be 400
        ($short.Content | ConvertFrom-Json).Message | Should -Be 'Use at least 12 characters.'
        $common = Send-TestSetup -Code $script:Code -Password 'password12345'
        ($common.Content | ConvertFrom-Json).Message | Should -Be 'That password is too common. Choose another.'
        Test-Path -LiteralPath $script:PasswordFile | Should -BeFalse
    }

    It 'saves the password, signs in, and then refuses the same code and closes the first-run routes' {
        $done = Send-TestSetup -Code $script:Code -Password $script:GoodPassword
        $done.StatusCode | Should -Be 200
        Test-Path -LiteralPath $script:PasswordFile | Should -BeTrue
        $cookie = ([string]($done.Headers['Set-Cookie'] | Select-Object -First 1) -split ';')[0]
        $cookie | Should -Match '^cf_session=[A-Za-z0-9_-]{43}$'
        (Invoke-TestRequest -Port $script:SetupPort -Path '/api/status' -Cookie $cookie).StatusCode | Should -Be 200

        $before = (Get-FileHash -LiteralPath $script:PasswordFile).Hash
        (Send-TestSetup -Code $script:Code -Password 'a-different-password-2').StatusCode | Should -Be 401
        (Invoke-TestRequest -Port $script:SetupPort -Path '/first-run').StatusCode | Should -Be 401
        (Get-FileHash -LiteralPath $script:PasswordFile).Hash | Should -Be $before

        $everything = $done.Content + (Get-Content -Raw -LiteralPath $script:SetupLog) + (Get-Content -Raw -LiteralPath "$($script:SetupLog).err" -ErrorAction SilentlyContinue)
        $everything | Should -Not -Match ([regex]::Escape($script:GoodPassword))
        $everything | Should -Not -Match ([regex]::Escape(($cookie -split '=')[1]))
        $record = Get-Content -Raw -LiteralPath $script:PasswordFile | ConvertFrom-Json
        $everything | Should -Not -Match ([regex]::Escape($record.Hash))
        # The code is printed once on the console only; no other output holds it.
        ([regex]::Matches((Get-Content -Raw -LiteralPath $script:SetupLog), [regex]::Escape($script:Code))).Count | Should -Be 1
    }
}

Describe 'Setup code rules' {
    It 'refuses an expired code' {
        $result = & (Get-Module ChannelForge) {
            $setup = @{}
            $start = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
            $code = New-ChannelForgeSetupCode -Setup $setup -Now $start
            [pscustomobject]@{
                Fresh   = Test-ChannelForgeSetupCode -Setup $setup -Code $code -Now ($start.AddMinutes(14))
                Expired = Test-ChannelForgeSetupCode -Setup $setup -Code $code -Now ($start.AddMinutes(16))
                Format  = $code -match '^[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}$'
            }
        }
        $result.Fresh | Should -BeTrue
        $result.Expired | Should -BeFalse
        $result.Format | Should -BeTrue
    }

    It 'never treats a corrupt password file as setup and never changes it' {
        $config = Join-Path $TestDrive 'corrupt'
        New-Item -ItemType Directory -Force -Path $config | Out-Null
        $file = Join-Path $config 'admin-password.json'
        Set-Content -LiteralPath $file -Value '{ broken'
        $before = (Get-FileHash -LiteralPath $file).Hash
        $state = & (Get-Module ChannelForge) { param($Config) Test-ChannelForgeSetupState -ConfigRoot $Config } $config
        $state | Should -BeFalse
        $response = & (Get-Module ChannelForge) { param($Config) Get-ChannelForgeWebSignInResponse -Store @{} -Setup @{} -Method GET -Path '/first-run' -CookieHeader '' -ConfigRoot $Config } $config
        $response.StatusCode | Should -Be 401
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $before
    }

    It 'keeps the code unused when the password file cannot be written' {
        $result = & (Get-Module ChannelForge) {
            param($Blocker)
            # A plain file where the config folder should be makes the write fail.
            Set-Content -LiteralPath $Blocker -Value 'not a folder'
            $setup = @{}
            $code = New-ChannelForgeSetupCode -Setup $setup
            $body = [Text.Encoding]::UTF8.GetBytes((@{ code = $code; password = 'test-first-password-1' } | ConvertTo-Json -Compress))
            $response = Invoke-ChannelForgeFirstRunSubmit -Store @{} -Setup $setup -BodyStream ([IO.MemoryStream]::new($body)) -ContentLength $body.Length -ConfigRoot $Blocker -CookieFormat 'cf_session={0}'
            [pscustomobject]@{ Status = $response.StatusCode; Message = ($response.Body | ConvertFrom-Json).Message; Used = $setup.Used }
        } (Join-Path $TestDrive 'blocker')
        $result.Status | Should -Be 500
        $result.Message | Should -Match 'could not be saved'
        $result.Used | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $TestDrive 'blocker\admin-password.json') | Should -BeFalse
    }
}
