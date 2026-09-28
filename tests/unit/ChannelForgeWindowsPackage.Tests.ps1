BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'tools\ChannelForgeAutoUpdate.Core.psm1') -Force
    $script:UninstallPath = Join-Path $repoRoot 'scripts\Uninstall-ChannelForgeWindowsBundle.ps1'
    $script:StartPath = Join-Path $repoRoot 'scripts\Start-ChannelForge.ps1'

    function New-TestWindowsPackage {
        $root = Join-Path $TestDrive ('package-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'src') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'src\app.ps1') -Value 'Write-Output app' -NoNewline
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data\rules'), (Join-Path $root 'data\lineup') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data\rules\aliases.json') -Value '{"aliases":[]}' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'data\lineup\numbering_blocks.json') -Value '{"blocks":[]}' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value '0.1.0' -NoNewline
        $files = foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName)) {
            [ordered]@{
                Path = [IO.Path]::GetRelativePath($root, $item.FullName).Replace('\', '/')
                ByteLength = [int64]$item.Length
                Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        $manifest = [ordered]@{
            SchemaVersion = 'windows-package/v1'
            PackageTarget = 'windows-x64-portable-server'
            ChannelForgeVersion = '0.1.0'
            SourceCommitSha = ('a' * 40)
            BundledPowerShellVersion = '7.6.6'
            BundledPowerShellHash = ('b' * 64)
            Files = @($files)
        }
        Set-Content -LiteralPath (Join-Path $root 'package-manifest.json') -Value ($manifest | ConvertTo-Json -Depth 10 -Compress) -NoNewline
        return $root
    }
}

Describe 'Test-ChannelForgeWindowsPackage' {
    It 'accepts a complete package manifest and hashes' {
        $root = New-TestWindowsPackage
        $result = Test-ChannelForgeWindowsPackage -PackageRoot $root
        $result.FileCount | Should -Be 4
        @($result.Manifest.Files.Path) | Should -Contain 'data/rules/aliases.json'
        @($result.Manifest.Files.Path) | Should -Contain 'data/lineup/numbering_blocks.json'
        @($result.Manifest.Files.Path) | Should -Not -Contain 'data/providers/mybunny.json'
    }

    It 'rejects a package missing either required runtime data file' {
        foreach ($relativePath in @('data\rules\aliases.json', 'data\lineup\numbering_blocks.json')) {
            $root = New-TestWindowsPackage
            Remove-Item -LiteralPath (Join-Path $root $relativePath) -Force
            { Test-ChannelForgeWindowsPackage -PackageRoot $root } | Should -Throw '*Required package runtime data is missing*'
        }
    }

    It 'rejects a tampered manifest file' {
        $root = New-TestWindowsPackage
        Set-Content -LiteralPath (Join-Path $root 'src\app.ps1') -Value 'tampered' -NoNewline
        { Test-ChannelForgeWindowsPackage -PackageRoot $root } | Should -Throw '*mismatch*'
    }

    It 'rejects an unmanifested application file' {
        $root = New-TestWindowsPackage
        Set-Content -LiteralPath (Join-Path $root 'src\extra.ps1') -Value 'extra' -NoNewline
        { Test-ChannelForgeWindowsPackage -PackageRoot $root } | Should -Throw '*unmanifested*'
    }

    It 'allows protected state only for an installed-root validation' {
        $root = New-TestWindowsPackage
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'state') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'state\marker.txt') -Value 'retain' -NoNewline
        { Test-ChannelForgeWindowsPackage -PackageRoot $root -AllowProtectedState -AllowUnmanifestedFiles } | Should -Not -Throw
    }
}

Describe 'Uninstall-ChannelForgeWindowsBundle' {
    It 'removes application files, retains state, then purges explicitly' {
        $oldLocalAppData = $env:LOCALAPPDATA
        $local = Join-Path $TestDrive 'local-app-data'
        $env:LOCALAPPDATA = $local
        try {
            $root = Join-Path $local 'ChannelForge'
            New-Item -ItemType Directory -Force -Path (Join-Path $root 'src'), (Join-Path $root 'state') | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'src\app.ps1') -Value 'app' -NoNewline
            Set-Content -LiteralPath (Join-Path $root 'state\marker.txt') -Value 'retain' -NoNewline

            & $script:UninstallPath -InstallRoot $root
            Test-Path -LiteralPath (Join-Path $root 'src') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'state\marker.txt') | Should -BeTrue

            & $script:UninstallPath -InstallRoot $root -PurgeData -ConfirmPurge
            Test-Path -LiteralPath $root | Should -BeFalse
        } finally {
            $env:LOCALAPPDATA = $oldLocalAppData
        }
    }
}

Describe 'Start-ChannelForge' {
    It 'preserves a live server ownership record when another port is requested' {
        $root = Join-Path $TestDrive ('live-owner-' + [guid]::NewGuid().ToString('N'))
        $requiredFiles = @(
            (Join-Path $root 'runtime/pwsh/pwsh.exe')
            (Join-Path $root 'scripts/Start-ChannelForgeWebServer.ps1')
            (Join-Path $root 'src/ChannelForge/ChannelForge.psd1')
            (Join-Path $root 'gui/dist/index.html')
        )
        foreach ($file in $requiredFiles) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            Set-Content -LiteralPath $file -Value 'test' -NoNewline
        }

        $runtimeState = Join-Path $root 'state/runtime'
        New-Item -ItemType Directory -Force -Path $runtimeState | Out-Null
        $pidPath = Join-Path $runtimeState 'server.pid'
        Set-Content -LiteralPath $pidPath -Value ([string]$PID) -NoNewline

        $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $portProbe.Start()
        $port = ([Net.IPEndPoint]$portProbe.LocalEndpoint).Port
        $portProbe.Stop()

        {
            & $script:StartPath -InstallRoot $root -Port $port -NoBrowser
        } | Should -Throw "*already has a running server process*"

        (Get-Content -LiteralPath $pidPath -Raw).Trim() | Should -Be ([string]$PID)
    }

    It 'fails without taking over a requested loopback port held by another process' {
        $root = Join-Path $TestDrive ('occupied-port-' + [guid]::NewGuid().ToString('N'))
        $requiredFiles = @(
            (Join-Path $root 'runtime\pwsh\pwsh.exe')
            (Join-Path $root 'scripts\Start-ChannelForgeWebServer.ps1')
            (Join-Path $root 'src\ChannelForge\ChannelForge.psd1')
            (Join-Path $root 'gui\dist\index.html')
        )
        foreach ($file in $requiredFiles) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            Set-Content -LiteralPath $file -Value 'test' -NoNewline
        }

        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        try {
            $listener.Start()
            $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
            {
                & $script:StartPath -InstallRoot $root -Port $port -NoBrowser
            } | Should -Throw "*Port $port is already in use by another process*"

            Test-Path -LiteralPath (Join-Path $root 'state\runtime\server.pid') | Should -BeFalse
            $listener.Server.IsBound | Should -BeTrue
        } finally {
            $listener.Stop()
        }
    }
}
