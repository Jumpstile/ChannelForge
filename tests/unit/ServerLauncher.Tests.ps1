BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Launcher = Join-Path $script:RepoRoot 'scripts\Start-ChannelForgeServer.ps1'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Port = 18890
    $script:Password = 'launcher-check-password-one'
    $script:Base = "http://127.0.0.1:$($script:Port)"
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-launcher-srv-' + [guid]::NewGuid().ToString('N'))
    $script:Config = Join-Path $script:LogDir 'config'
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $script:LogPath = Join-Path $script:LogDir 'server.log'

    function Read-Log {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '' }
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { return [IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    }

    $script:Process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $script:Launcher, '-ConfigRoot', $script:Config, '-Port', $script:Port, '-AllowedHost', 'launcher.test') -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput $script:LogPath -RedirectStandardError "$($script:LogPath).err"
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        if ($script:Process.HasExited) { break }
        $tcp = [Net.Sockets.TcpClient]::new()
        try { $tcp.Connect('127.0.0.1', $script:Port); break } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
    }
    $script:Code = $null
    for ($attempt = 0; $attempt -lt 50 -and -not $script:Code; $attempt++) {
        if ((Read-Log $script:LogPath) -match 'setup code: (\S+)') { $script:Code = $Matches[1] } else { Start-Sleep -Milliseconds 100 }
    }
}

AfterAll {
    if ($null -ne $script:Process) {
        if (-not $script:Process.HasExited) { $script:Process.Kill() }
        $script:Process.WaitForExit(10000) | Out-Null
        $script:Process.Dispose()
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'Server launcher' {
    It 'starts with sign-in required and prints a setup code' {
        $script:Code | Should -Not -BeNullOrEmpty
        $status = Invoke-WebRequest -Uri "$($script:Base)/api/status" -SkipHttpErrorCheck
        $status.StatusCode | Should -Be 401
    }

    It 'prints no password, and shows the setup code only once' {
        $first = Invoke-WebRequest -Uri "$($script:Base)/first-run/submit" -Method POST -Headers @{ Origin = $script:Base } -ContentType 'application/json' -Body (@{ code = $script:Code; password = $script:Password } | ConvertTo-Json -Compress) -SkipHttpErrorCheck
        $first.StatusCode | Should -Be 200
        $console = (Read-Log $script:LogPath) + (Read-Log "$($script:LogPath).err")
        $console.Contains($script:Password) | Should -BeFalse
        ([regex]::Matches($console, [regex]::Escape($script:Code))).Count | Should -Be 1
    }

    It 'accepts only the Host names that were allowed' {
        $allowed = Invoke-WebRequest -Uri "$($script:Base)/api/status" -Headers @{ Host = "launcher.test:$($script:Port)" } -SkipHttpErrorCheck
        $allowed.StatusCode | Should -Be 401
        $other = Invoke-WebRequest -Uri "$($script:Base)/api/status" -Headers @{ Host = "other.test:$($script:Port)" } -SkipHttpErrorCheck
        $other.StatusCode | Should -Be 403
    }

    It 'refuses to start without a config folder' {
        $out = & (Get-Command pwsh).Source -NoProfile -NonInteractive -File $script:Launcher -Port 18891 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $out | Should -Not -BeLike '*is running at*'
    }
}

Describe 'Network bind guard' {
    BeforeAll {
        $script:Cfg = Join-Path $script:LogDir 'guard-config'
        New-Item -ItemType Directory -Force -Path $script:Cfg | Out-Null
    }

    It 'refuses a non-loopback address without sign-in' {
        { New-ChannelForgeWebServer -Port 18892 -BindAddress '0.0.0.0' -ConfigRoot $script:Cfg } | Should -Throw '*sign-in turned on*'
    }

    It 'refuses a non-loopback address with sign-in but no config folder' {
        { New-ChannelForgeWebServer -Port 18892 -BindAddress '0.0.0.0' -RequireSignIn } | Should -Throw
    }

    It 'allows a non-loopback address with sign-in and a config folder, without opening it' {
        $server = New-ChannelForgeWebServer -Port 18892 -BindAddress '0.0.0.0' -RequireSignIn -ConfigRoot $script:Cfg
        try {
            $server.RequireSignIn | Should -BeTrue
            $server.Started | Should -BeFalse
        }
        finally { $server.Listener.Close() }
    }

    It 'keeps loopback as the default' {
        $server = New-ChannelForgeWebServer -Port 18893
        try { $server.BindAddress | Should -Be '127.0.0.1' } finally { $server.Listener.Close() }
    }
}

Describe 'Network bind prefix' {
    It 'brackets a bare IPv6 address so the listener prefix is valid' {
        $cfg = Join-Path ([IO.Path]::GetTempPath()) ('cf-v6-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $cfg | Out-Null
        try {
            $server = New-ChannelForgeWebServer -Port 18894 -BindAddress '2001:db8::5' -RequireSignIn -ConfigRoot $cfg
            try { $server.Prefix | Should -Be 'http://[2001:db8::5]:18894/' } finally { $server.Listener.Close() }
        }
        finally { Remove-Item -LiteralPath $cfg -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
