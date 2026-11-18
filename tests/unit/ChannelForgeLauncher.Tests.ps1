BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:StartPath = Join-Path $repoRoot 'scripts\Start-ChannelForge.ps1'
    $script:Roots = [Collections.Generic.List[string]]::new()

    function Get-FreePort {
        $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $probe.Start()
        try { return ([Net.IPEndPoint]$probe.LocalEndpoint).Port } finally { $probe.Stop() }
    }

    # Temp install tree. The runtime is a junction to the running PowerShell
    # so the launcher starts a real pwsh.exe; the web server script is a fake.
    # It lives outside TestDrive: the launcher keeps its log files open while
    # this process runs, which would break TestDrive cleanup.
    function New-FakeInstall([string]$ServerBody) {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('cf-launcher-' + [guid]::NewGuid().ToString('N'))
        foreach ($dir in 'runtime', 'scripts', 'src\ChannelForge', 'gui\dist') {
            New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null
        }
        New-Item -ItemType Junction -Path (Join-Path $root 'runtime\pwsh') -Target $PSHOME | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'src\ChannelForge\ChannelForge.psd1') -Value 'x' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'gui\dist\index.html') -Value 'x' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'scripts\Start-ChannelForgeWebServer.ps1') -Value $ServerBody
        $script:Roots.Add($root)
        return $root
    }

    $script:ListeningServer = @'
param([int]$Port, [string]$BindAddress)
Set-Content -LiteralPath (Join-Path $PSScriptRoot '..\server.args.txt') -Value "$BindAddress $Port" -NoNewline
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://${BindAddress}:$Port/")
$listener.Start()
while ($true) {
    $context = $listener.GetContext()
    $context.Response.StatusCode = 200
    $context.Response.Close()
}
'@

    $script:SilentServer = 'Start-Sleep -Seconds 120'

    # Records the real pwsh.exe in a package-manifest.json; override a value to fake a swapped runtime.
    function Write-RuntimeManifest([string]$Root, [string]$Sha256 = '', [Int64]$ByteLength = -1) {
        $exe = Join-Path $PSHOME 'pwsh.exe'
        if ($Sha256 -eq '') { $Sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() }
        if ($ByteLength -lt 0) { $ByteLength = (Get-Item -LiteralPath $exe).Length }
        $files = @([ordered]@{ Path = 'runtime/pwsh/pwsh.exe'; ByteLength = $ByteLength; Sha256 = $Sha256 })
        Set-Content -LiteralPath (Join-Path $Root 'package-manifest.json') -Value (@{ Files = $files } | ConvertTo-Json -Depth 4)
    }
}

Describe 'Start-ChannelForge launcher' {
    AfterEach {
        foreach ($root in $script:Roots) {
            Get-Process pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($root + '*') } | Stop-Process -Force
            $junction = Join-Path $root 'runtime\pwsh'
            if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:Roots.Clear()
    }

    It 'names every missing runtime file and points to the logs' {
        $root = New-FakeInstall $script:SilentServer
        [IO.Directory]::Delete((Join-Path $root 'runtime\pwsh'))
        Remove-Item -LiteralPath (Join-Path $root 'gui\dist\index.html') -Force
        $message = ''
        try { & $script:StartPath -InstallRoot $root -Port (Get-FreePort) -NoBrowser } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*installation is incomplete*'
        $message | Should -BeLike '*pwsh.exe*'
        $message | Should -BeLike '*index.html*'
        $message | Should -BeLike '*Logs are in*state*runtime*'
    }

    It 'gives up within the timeout and says where the logs are when the server never answers' {
        $root = New-FakeInstall $script:SilentServer
        $message = ''
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try { & $script:StartPath -InstallRoot $root -Port (Get-FreePort) -NoBrowser -HealthTimeoutSeconds 2 } catch { $message = $_.Exception.Message }
        $watch.Stop()
        $message | Should -BeLike '*could not start*did not answer /health*'
        $message | Should -BeLike '*Check the logs in*state*runtime*'
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 30
        Test-Path -LiteralPath (Join-Path $root 'state\runtime\server.pid') | Should -BeFalse
    }

    It 'binds the server to 127.0.0.1 and opens http://127.0.0.1:<port>/' {
        $root = New-FakeInstall $script:ListeningServer
        $port = Get-FreePort
        Mock Start-Process { if ($FilePath -notlike 'http*') { & (Get-Command Start-Process -CommandType Cmdlet) @PesterBoundParameters } }
        $output = & $script:StartPath -InstallRoot $root -Port $port
        (Get-Content -LiteralPath (Join-Path $root 'server.args.txt') -Raw) | Should -Be "127.0.0.1 $port"
        Should -Invoke Start-Process -Exactly 1 -ParameterFilter { $FilePath -ceq "http://127.0.0.1:$port/" }
        "$output" | Should -BeLike "*http://127.0.0.1:$port/*"
    }

    It 'starts when package-manifest.json matches the bundled pwsh.exe' {
        $root = New-FakeInstall $script:ListeningServer
        Write-RuntimeManifest $root
        $port = Get-FreePort
        Mock Start-Process { if ($FilePath -notlike 'http*') { & (Get-Command Start-Process -CommandType Cmdlet) @PesterBoundParameters } }
        "$(& $script:StartPath -InstallRoot $root -Port $port -NoBrowser)" | Should -BeLike "*http://127.0.0.1:$port/*"
    }

    It 'stops with a plain message and starts nothing when pwsh.exe does not match the manifest' {
        $root = New-FakeInstall $script:ListeningServer
        Write-RuntimeManifest $root -Sha256 ('0' * 64)
        $message = ''
        try { & $script:StartPath -InstallRoot $root -Port (Get-FreePort) -NoBrowser } catch { $message = $_.Exception.Message }
        $message | Should -Be 'The bundled PowerShell does not match this ChannelForge package. Reinstall ChannelForge.'
        Test-Path -LiteralPath (Join-Path $root 'state\runtime\server.pid') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'server.args.txt') | Should -BeFalse
    }

    It 'stops when the manifest records a different length for pwsh.exe' {
        $root = New-FakeInstall $script:ListeningServer
        Write-RuntimeManifest $root -ByteLength 1
        $message = ''
        try { & $script:StartPath -InstallRoot $root -Port (Get-FreePort) -NoBrowser } catch { $message = $_.Exception.Message }
        $message | Should -BeLike 'The bundled PowerShell does not match*'
    }
}
