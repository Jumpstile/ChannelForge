BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Password = 'test-password-one'
    $script:Servers = @()

    function Start-TestServer {
        param([int]$Port, [string]$Root, [string]$Config, [switch]$SignIn)
        $launcher = Join-Path $Root "server-$Port.ps1"
        $options = if ($SignIn) { " -RequireSignIn -ConfigRoot '$Config'" } else { " -ConfigRoot '$Config'" }
        @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $Port -RepositoryRoot '$Root'$options") | Set-Content -LiteralPath $launcher
        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru
        $script:Servers += $process
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            if ($process.HasExited) { break }
            $tcp = [Net.Sockets.TcpClient]::new()
            try { $tcp.Connect('127.0.0.1', $Port); return } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
        }
        throw 'Test server did not start.'
    }

    function Send-RawRequest {
        param([int]$Port, [string]$Method = 'GET', [string]$Path = '/api/settings', [hashtable]$Headers = @{}, [string]$Body = $null)
        $lines = @("$Method $Path HTTP/1.1", "Host: 127.0.0.1:$Port", 'Connection: close')
        foreach ($name in $Headers.Keys) { $lines += "${name}: $($Headers[$name])" }
        $bytes = if ($null -ne $Body) { [Text.Encoding]::UTF8.GetBytes($Body) } else { [byte[]]@() }
        if ($Method -in @('POST', 'PUT', 'PATCH', 'DELETE')) { $lines += "Content-Length: $($bytes.Length)" }
        $head = [Text.Encoding]::ASCII.GetBytes((($lines -join "`r`n") + "`r`n`r`n"))
        $tcp = [Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
        try {
            $stream = $tcp.GetStream()
            $stream.Write($head, 0, $head.Length)
            if ($bytes.Length -gt 0) { $stream.Write($bytes, 0, $bytes.Length) }
            $text = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8).ReadToEnd()
        }
        finally { $tcp.Dispose() }
        $headerText, $content = $text -split "`r`n`r`n", 2
        [pscustomobject]@{ Status = [int](($headerText -split ' ')[1]); Headers = $headerText; Content = $content }
    }

    function Send-Put {
        param([int]$Port, [string]$Body, [hashtable]$Extra = @{})
        $headers = @{ 'Content-Type' = 'application/json'; Origin = "http://127.0.0.1:$Port" }
        foreach ($key in $Extra.Keys) { $headers[$key] = $Extra[$key] }
        Send-RawRequest -Port $Port -Method PUT -Headers $headers -Body $Body
    }

    function Get-FolderHash {
        param([string]$Folder)
        (Get-ChildItem -LiteralPath $Folder -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.Name)=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join ';'
    }
}

AfterAll {
    foreach ($server in @($script:Servers)) {
        if ($null -ne $server -and -not $server.HasExited) { $server.Kill() }
        if ($null -ne $server) { $server.WaitForExit(10000) | Out-Null; $server.Dispose() }
    }
}

Describe 'Settings file' {
    BeforeEach { $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }

    It 'defaults to system when there is no file' {
        $result = & (Get-Module ChannelForge) { param($f) Read-ChannelForgeSettings -Folder $f } $script:Folder
        $result.Status | Should -Be 'Missing'
        $result.Appearance | Should -Be 'system'
    }

    It 'saves and reads each valid value, with a schema version' {
        foreach ($value in 'light', 'dark', 'system') {
            & (Get-Module ChannelForge) { param($f, $v) Save-ChannelForgeSettings -Folder $f -Appearance $v } $script:Folder $value
            (& (Get-Module ChannelForge) { param($f) Read-ChannelForgeSettings -Folder $f } $script:Folder).Appearance | Should -Be $value
        }
        (Get-Content -LiteralPath (Join-Path $script:Folder 'settings.json') -Raw | ConvertFrom-Json).schema | Should -Be 1
    }

    It 'refuses an unknown value and leaves the saved file alone' {
        & (Get-Module ChannelForge) { param($f) Save-ChannelForgeSettings -Folder $f -Appearance 'dark' } $script:Folder
        $before = Get-FolderHash $script:Folder
        { & (Get-Module ChannelForge) { param($f) Save-ChannelForgeSettings -Folder $f -Appearance 'purple' } $script:Folder } | Should -Throw
        Get-FolderHash $script:Folder | Should -Be $before
    }

    It 'leaves the old file or the new file, never a mix, and no temp file behind' {
        & (Get-Module ChannelForge) { param($f) Save-ChannelForgeSettings -Folder $f -Appearance 'dark' } $script:Folder
        & (Get-Module ChannelForge) { param($f) Save-ChannelForgeSettings -Folder $f -Appearance 'light' } $script:Folder
        (Get-Content -LiteralPath (Join-Path $script:Folder 'settings.json') -Raw | ConvertFrom-Json).appearance | Should -Be 'light'
        @(Get-ChildItem -LiteralPath $script:Folder -Force | Where-Object Name -like '*.tmp').Count | Should -Be 0
    }

    It 'uses defaults for an unreadable file, keeps it aside on the next save, and never deletes it' {
        New-Item -ItemType Directory -Force -Path $script:Folder | Out-Null
        $path = Join-Path $script:Folder 'settings.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        $read = & (Get-Module ChannelForge) { param($f) Read-ChannelForgeSettings -Folder $f } $script:Folder
        $read.Status | Should -Be 'Corrupt'
        $read.Appearance | Should -Be 'system'
        & (Get-Module ChannelForge) { param($f) Save-ChannelForgeSettings -Folder $f -Appearance 'dark' } $script:Folder
        $kept = @(Get-ChildItem -LiteralPath $script:Folder -Filter 'settings.json.bad-*')
        $kept.Count | Should -Be 1
        (Get-Content -LiteralPath $kept[0].FullName -Raw).Trim() | Should -Be '{ not json'
        (& (Get-Module ChannelForge) { param($f) Read-ChannelForgeSettings -Folder $f } $script:Folder).Appearance | Should -Be 'dark'
    }

    It 'treats a file with an unknown value or extra field as unreadable' {
        New-Item -ItemType Directory -Force -Path $script:Folder | Out-Null
        $path = Join-Path $script:Folder 'settings.json'
        foreach ($text in '{"schema":1,"appearance":"purple"}', '{"schema":1,"appearance":"dark","extra":1}', '{"schema":2,"appearance":"dark"}') {
            Set-Content -LiteralPath $path -Value $text
            (& (Get-Module ChannelForge) { param($f) Read-ChannelForgeSettings -Folder $f } $script:Folder).Status | Should -Be 'Corrupt'
        }
    }
}

Describe 'Settings route (sign-in off)' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'root'
        $script:Config = Join-Path $TestDrive 'config-off'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'state\accepted'), (Join-Path $script:Root 'output'), $script:Config | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Root 'state\accepted\accepted-state.json') -Value '{"kept":true}'
        [IO.File]::WriteAllBytes((Join-Path $script:Root 'output\lineup.m3u'), [byte[]](35, 69, 88, 84, 77, 51, 85, 10))
        $script:OffPort = 18925
        Start-TestServer -Port $script:OffPort -Root $script:Root -Config $script:Config
    }

    It 'answers GET with the default' {
        $response = Send-RawRequest -Port $script:OffPort
        $response.Status | Should -Be 200
        $body = $response.Content | ConvertFrom-Json
        $body.appearance | Should -Be 'system'
        $body.saved | Should -BeFalse
    }

    It 'saves a valid value and GET returns it' {
        (Send-Put -Port $script:OffPort -Body '{"appearance":"dark"}').Status | Should -Be 200
        $body = (Send-RawRequest -Port $script:OffPort).Content | ConvertFrom-Json
        $body.appearance | Should -Be 'dark'
        $body.saved | Should -BeTrue
    }

    It 'rejects a bad field, a bad value, bad JSON and a missing body with plain errors, and keeps the saved value' {
        foreach ($bad in '{"theme":"dark"}', '{"appearance":"dark","theme":"x"}', '{"appearance":"purple"}', '{"appearance":5}', '[]', 'nope') {
            $response = Send-Put -Port $script:OffPort -Body $bad
            $response.Status | Should -Be 400
            ($response.Content | ConvertFrom-Json).Error | Should -Be 'invalid-settings'
        }
        (Send-Put -Port $script:OffPort -Body '').Status | Should -Be 400
        ((Send-RawRequest -Port $script:OffPort).Content | ConvertFrom-Json).appearance | Should -Be 'dark'
    }

    It 'refuses a body over the size limit' {
        $response = Send-Put -Port $script:OffPort -Body ('{"appearance":"' + ('x' * 2000) + '"}')
        $response.Status | Should -Be 413
        ($response.Content | ConvertFrom-Json).Error | Should -Be 'request-too-large'
    }

    It 'refuses a non-JSON body and other methods' {
        (Send-RawRequest -Port $script:OffPort -Method PUT -Headers @{ 'Content-Type' = 'text/plain' } -Body '{"appearance":"dark"}').Status | Should -Be 415
        (Send-RawRequest -Port $script:OffPort -Method DELETE -Headers @{ 'Content-Type' = 'application/json' } -Body '{}').Status | Should -Be 405
    }

    It 'reports an unreadable settings file plainly and uses the default' {
        Set-Content -LiteralPath (Join-Path $script:Config 'settings.json') -Value '{ bad'
        $body = (Send-RawRequest -Port $script:OffPort).Content | ConvertFrom-Json
        $body.appearance | Should -Be 'system'
        $body.problem | Should -Match 'could not read'
        Test-Path -LiteralPath (Join-Path $script:Config 'settings.json') | Should -BeTrue
    }

    It 'does not touch accepted state or generated output' {
        $before = Get-FolderHash $script:Root
        (Send-Put -Port $script:OffPort -Body '{"appearance":"light"}').Status | Should -Be 200
        Get-FolderHash $script:Root | Should -Be $before
    }

    It 'keeps existing responses the same' {
        (Send-RawRequest -Port $script:OffPort -Path '/health').Status | Should -Be 200
        (Send-RawRequest -Port $script:OffPort -Path '/api/auth/session').Status | Should -Be 404
        (Send-RawRequest -Port $script:OffPort -Method PUT -Path '/api/status' -Headers @{ 'Content-Type' = 'application/json' } -Body '{}').Status | Should -Be 405
    }
}

Describe 'Settings route (sign-in on)' {
    BeforeAll {
        $script:OnRoot = Join-Path $TestDrive 'root-on'
        $script:OnConfig = Join-Path $TestDrive 'config-on'
        New-Item -ItemType Directory -Force -Path $script:OnRoot, $script:OnConfig | Out-Null
        & (Get-Module ChannelForge) {
            param($Config, $Password)
            Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000) | Out-Null
        } $script:OnConfig $script:Password
        $script:OnPort = 18926
        Start-TestServer -Port $script:OnPort -Root $script:OnRoot -Config $script:OnConfig -SignIn
        $signIn = Send-RawRequest -Port $script:OnPort -Method POST -Path '/api/auth/sign-in' -Headers @{ 'Content-Type' = 'application/json'; Origin = "http://127.0.0.1:$($script:OnPort)" } -Body (@{ password = $script:Password } | ConvertTo-Json -Compress)
        $script:Cookie = [regex]::Match($signIn.Headers, 'cf_session=[A-Za-z0-9_-]+').Value
    }

    It 'requires sign-in to read or change settings' {
        (Send-RawRequest -Port $script:OnPort).Status | Should -Be 401
        (Send-Put -Port $script:OnPort -Body '{"appearance":"dark"}').Status | Should -Be 401
        Test-Path -LiteralPath (Join-Path $script:OnConfig 'settings.json') | Should -BeFalse
    }

    It 'refuses a change from another origin even when signed in' {
        $response = Send-Put -Port $script:OnPort -Body '{"appearance":"dark"}' -Extra @{ Cookie = $script:Cookie; Origin = 'http://evil.example.test' }
        $response.Status | Should -Be 403
        Test-Path -LiteralPath (Join-Path $script:OnConfig 'settings.json') | Should -BeFalse
    }

    It 'lets a signed-in same-origin user read and change settings, kept in the config folder' {
        (Send-Put -Port $script:OnPort -Body '{"appearance":"dark"}' -Extra @{ Cookie = $script:Cookie }).Status | Should -Be 200
        $body = (Send-RawRequest -Port $script:OnPort -Headers @{ Cookie = $script:Cookie }).Content | ConvertFrom-Json
        $body.appearance | Should -Be 'dark'
        Test-Path -LiteralPath (Join-Path $script:OnConfig 'settings.json') | Should -BeTrue
    }
}
