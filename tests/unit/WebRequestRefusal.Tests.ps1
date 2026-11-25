BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Password = 'test-password-one'
    $script:Servers = @()

    function Start-TestServer {
        param([int]$Port, [string]$Root, [string]$Config, [switch]$SignIn, [string]$Extra = '')
        $launcher = Join-Path $Root "server-$Port.ps1"
        $options = if ($SignIn) { " -RequireSignIn -ConfigRoot '$Config'" } else { '' }
        @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $Port -RepositoryRoot '$Root'$options$Extra") | Set-Content -LiteralPath $launcher
        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru
        $script:Servers += $process
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            if ($process.HasExited) { break }
            $tcp = [Net.Sockets.TcpClient]::new()
            try { $tcp.Connect('127.0.0.1', $Port); return } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
        }
        throw 'Test server did not start.'
    }

    # Sends a raw request so the test controls Host, Origin and Content-Type exactly.
    function Send-RawRequest {
        param([int]$Port, [string]$Method = 'GET', [string]$Path = '/health', [string]$HostValue, [hashtable]$Headers = @{}, [string]$Body = $null)
        if (-not $PSBoundParameters.ContainsKey('HostValue')) { $HostValue = "127.0.0.1:$Port" }
        $lines = @("$Method $Path HTTP/1.1", "Host: $HostValue", 'Connection: close')
        foreach ($name in $Headers.Keys) { $lines += "${name}: $($Headers[$name])" }
        $bytes = if ($null -ne $Body) { [Text.Encoding]::UTF8.GetBytes($Body) } else { [byte[]]@() }
        if ($Method -in @('POST', 'PUT', 'PATCH', 'DELETE')) { $lines += "Content-Length: $($bytes.Length)" }
        $head = [Text.Encoding]::ASCII.GetBytes((($lines -join "`r`n") + "`r`n`r`n"))
        $tcp = [Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
        try {
            $stream = $tcp.GetStream()
            $stream.Write($head, 0, $head.Length)
            if ($bytes.Length -gt 0) { $stream.Write($bytes, 0, $bytes.Length) }
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
            $text = $reader.ReadToEnd()
        }
        finally { $tcp.Dispose() }
        $headerText, $content = $text -split "`r`n`r`n", 2
        [pscustomobject]@{ Status = [int](($headerText -split ' ')[1]); Headers = $headerText; Content = $content }
    }

    $json = @{ 'Content-Type' = 'application/json' }
    function Get-PostHeaders { param([int]$Port, [hashtable]$Extra = @{}) $h = @{ 'Content-Type' = 'application/json'; Origin = "http://127.0.0.1:$Port" }; foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] }; $h }

    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null
    & (Get-Module ChannelForge) {
        param($Config, $Password)
        Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000) | Out-Null
    } $script:Config $script:Password
    $script:OnPort = 18875
    $script:OffPort = 18876
    Start-TestServer -Port $script:OnPort -Root $script:Root -Config $script:Config -SignIn -Extra " -AllowedHost 'cf.example.test','lan.example.test:9000'"
    Start-TestServer -Port $script:OffPort -Root $script:Root -Config $script:Config
}

AfterAll {
    foreach ($server in @($script:Servers)) {
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill() }
        if ($null -ne $server) { $server.WaitForExit(10000) | Out-Null; $server.Dispose() }
    }
}

Describe 'Host check (sign-in mode on)' {
    It 'serves the loopback names with the listening port' {
        foreach ($name in @('127.0.0.1', 'localhost')) {
            (Send-RawRequest -Port $script:OnPort -HostValue "${name}:$($script:OnPort)").Status | Should -Be 200
        }
    }

    It 'refuses a wrong Host on every route, including health, and never repeats it' {
        foreach ($path in @('/health', '/first-run', '/api/auth/session')) {
            $response = Send-RawRequest -Port $script:OnPort -Path $path -HostValue 'evil.example.test'
            $response.Status | Should -Be 403
            $response.Content | Should -Match 'That request was not allowed\.'
            $response.Content | Should -Not -Match 'evil'
            $response.Headers | Should -Not -Match 'evil'
        }
    }

    It 'refuses the right name on the wrong port' {
        (Send-RawRequest -Port $script:OnPort -HostValue 'localhost:9999').Status | Should -Be 403
    }

    It 'accepts -AllowedHost entries, with or without a port, and refuses look-alikes' {
        (Send-RawRequest -Port $script:OnPort -HostValue 'cf.example.test').Status | Should -Be 200
        (Send-RawRequest -Port $script:OnPort -HostValue "cf.example.test:$($script:OnPort)").Status | Should -Be 200
        (Send-RawRequest -Port $script:OnPort -HostValue 'lan.example.test:9000').Status | Should -Be 200
        foreach ($lookAlike in @('cf.example.test.evil.test', 'xcf.example.test', 'lan.example.test:9001', 'evil.test/cf.example.test')) {
            (Send-RawRequest -Port $script:OnPort -HostValue $lookAlike).Status | Should -BeIn @(400, 403)
        }
    }
}

Describe 'Origin and content type (sign-in mode on)' {
    BeforeAll {
        $script:SignInBody = @{ password = $script:Password } | ConvertTo-Json -Compress
        $script:SignInPath = '/api/auth/sign-in'
    }

    It 'allows a same-origin POST and sets a HttpOnly, SameSite=Strict cookie without Secure' {
        $response = Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers (Get-PostHeaders -Port $script:OnPort) -Body $script:SignInBody
        $response.Status | Should -Be 200
        $response.Headers | Should -Match 'Set-Cookie: cf_session=[A-Za-z0-9_-]{43}; Path=/; HttpOnly; SameSite=Strict\r?\n?'
        $response.Headers | Should -Not -Match 'Secure'
    }

    It 'allows a same-origin POST that names an allowed host' {
        $headers = Get-PostHeaders -Port $script:OnPort -Extra @{ Origin = 'http://lan.example.test:9000' }
        (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -HostValue 'lan.example.test:9000' -Headers $headers -Body $script:SignInBody).Status | Should -Be 200
    }

    It 'refuses a cross-origin POST, even with the right password, and never repeats the Origin' {
        $headers = Get-PostHeaders -Port $script:OnPort -Extra @{ Origin = 'http://attacker.example.test' }
        $response = Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $headers -Body $script:SignInBody
        $response.Status | Should -Be 403
        $response.Headers | Should -Not -Match 'Set-Cookie'
        $response.Content | Should -Not -Match 'attacker'
        $response.Headers | Should -Not -Match 'attacker'
    }

    It 'refuses a different port or scheme on the Origin' {
        foreach ($origin in @('http://127.0.0.1:9999', 'https://127.0.0.1:18875')) {
            $headers = Get-PostHeaders -Port $script:OnPort -Extra @{ Origin = $origin }
            (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $headers -Body $script:SignInBody).Status | Should -Be 403
        }
    }

    It 'refuses Origin null' {
        $headers = Get-PostHeaders -Port $script:OnPort -Extra @{ Origin = 'null' }
        (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $headers -Body $script:SignInBody).Status | Should -Be 403
    }

    It 'refuses a POST with no Origin and no Referer, and accepts a same-origin Referer instead' {
        (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $json -Body $script:SignInBody).Status | Should -Be 403
        $headers = $json + @{ Referer = "http://127.0.0.1:$($script:OnPort)/" }
        (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $headers -Body $script:SignInBody).Status | Should -Be 200
        $headers = $json + @{ Referer = 'http://attacker.example.test/' }
        (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $headers -Body $script:SignInBody).Status | Should -Be 403
    }

    It 'refuses a cross-origin POST to an existing change route' {
        $headers = Get-PostHeaders -Port $script:OnPort -Extra @{ Origin = 'http://attacker.example.test' }
        (Send-RawRequest -Port $script:OnPort -Method POST -Path '/api/sources/remove' -Headers $headers -Body '{}').Status | Should -Be 403
    }

    It 'still serves a GET with no Origin' {
        (Send-RawRequest -Port $script:OnPort -Path '/health').Status | Should -Be 200
    }

    It 'gives 415 to a state-changing request that is not application/json' {
        foreach ($type in @('application/x-www-form-urlencoded', 'text/plain')) {
            $headers = Get-PostHeaders -Port $script:OnPort -Extra @{ 'Content-Type' = $type }
            (Send-RawRequest -Port $script:OnPort -Method POST -Path $script:SignInPath -Headers $headers -Body 'password=x').Status | Should -Be 415
        }
    }

    It 'answers a preflight with 405 and no Access-Control headers' {
        $headers = @{ Origin = 'http://attacker.example.test'; 'Access-Control-Request-Method' = 'POST' }
        $response = Send-RawRequest -Port $script:OnPort -Method OPTIONS -Path $script:SignInPath -Headers $headers
        $response.Status | Should -Be 405
        $response.Headers | Should -Not -Match 'Access-Control'
    }
}

Describe 'Sign-in mode off (the default)' {
    It 'does not check Host, Origin or content type' {
        (Send-RawRequest -Port $script:OffPort -HostValue 'anything.example.test').Status | Should -Be 200
        $response = Send-RawRequest -Port $script:OffPort -Method POST -Path '/api/sources/remove' -Headers @{ Origin = 'http://attacker.example.test' } -Body '{}'
        $response.Content | Should -Not -Match 'That request was not allowed'
    }
}
