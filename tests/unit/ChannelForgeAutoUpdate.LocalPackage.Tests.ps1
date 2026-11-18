# Local-package update path (-PackageRoot / -PackagePath with -Apply), the path
# the bundle's "Update ChannelForge.cmd" and "Install ChannelForge.cmd" use.
# The orchestrator runs in a child pwsh against temp folders only. Proves:
#   - a failed start after the files were replaced restores the previous
#     application files byte for byte and leaves state untouched
#   - state/source-enrollment.json and state/managed-sources are byte-identical
#     after a successful update and after a failed one
#   - a backup failure stops the update before any application file changes
#   - a package that is older or equal fails closed unless -AllowDowngrade is given
#
# Run with: Invoke-Pester -Path .\tests\unit\ChannelForgeAutoUpdate.LocalPackage.Tests.ps1

BeforeAll {
    $script:OrchestratorPath = Join-Path $PSScriptRoot '..\..\tools\Invoke-ChannelForgeAutoUpdate.ps1'
    $script:Pwsh = (Get-Command pwsh).Source
    # A real Windows executable that ignores the updater's arguments and exits
    # non-zero. It stands in for runtime\pwsh\pwsh.exe so the "start" step fails.
    $script:FailingExe = Join-Path ([Environment]::SystemDirectory) 'where.exe'

    function Set-TestFile {
        param([string]$Root, [string]$Relative, [byte[]]$Bytes)
        $path = Join-Path $Root ($Relative -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [IO.File]::WriteAllBytes($path, $Bytes)
    }

    function ConvertTo-TestBytes {
        param([string]$Text)
        return , [Text.Encoding]::ASCII.GetBytes($Text)
    }

    # Writes the files every install and every package needs; returns the root.
    function New-TestTree {
        param([string]$Name, [string]$Version, [string]$Marker)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N'))
        Set-TestFile $root 'VERSION' (ConvertTo-TestBytes $Version)
        Set-TestFile $root 'src/app.ps1' (ConvertTo-TestBytes "app $Marker")
        Set-TestFile $root 'scripts/Start-ChannelForge.ps1' (ConvertTo-TestBytes "start $Marker")
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'runtime\pwsh') | Out-Null
        Copy-Item -LiteralPath $script:FailingExe -Destination (Join-Path $root 'runtime\pwsh\pwsh.exe')
        Set-TestFile $root 'data/rules/aliases.json' (ConvertTo-TestBytes '{"aliases":[]}')
        Set-TestFile $root 'data/lineup/numbering_blocks.json' (ConvertTo-TestBytes '{"blocks":[]}')
        return $root
    }

    function New-TestInstall {
        param([string]$Version = '1.0.0')
        $root = New-TestTree -Name 'install' -Version $Version -Marker 'old'
        Set-TestFile $root 'src/old-only.ps1' (ConvertTo-TestBytes 'only in the old install')
        # Real state files: CRLF, NUL and 0xFF bytes so a text round trip would change them.
        Set-TestFile $root 'state/source-enrollment.json' ([byte[]](0x7B, 0x0D, 0x0A, 0x22, 0x76, 0x22, 0x3A, 0x32, 0x0D, 0x0A, 0x00, 0xFF, 0x7D))
        Set-TestFile $root ('state/managed-sources/' + ('a' * 64) + '.m3u') ([byte[]](0x23, 0x45, 0x58, 0x54, 0x4D, 0x33, 0x55, 0x0D, 0x0A, 0xFF, 0x00))
        return $root
    }

    function New-TestPackage {
        param([string]$Version = '2.0.0')
        $root = New-TestTree -Name 'package' -Version $Version -Marker 'new'
        Set-TestFile $root 'src/new-only.ps1' (ConvertTo-TestBytes 'only in the new package')
        # A package built from a dev tree can carry state; the updater must not apply it.
        Set-TestFile $root 'state/source-enrollment.json' (ConvertTo-TestBytes 'package state must not win')
        $files = foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName)) {
            [ordered]@{
                Path       = [IO.Path]::GetRelativePath($root, $item.FullName).Replace('\', '/')
                ByteLength = [int64]$item.Length
                Sha256     = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        $manifest = [ordered]@{
            SchemaVersion            = 'windows-package/v1'
            PackageTarget            = 'windows-x64-portable-server'
            ChannelForgeVersion      = $Version
            SourceCommitSha          = ('a' * 40)
            BundledPowerShellVersion = '7.6.6'
            BundledPowerShellHash    = ('b' * 64)
            Files                    = @($files)
        }
        Set-TestFile $root 'package-manifest.json' (ConvertTo-TestBytes ($manifest | ConvertTo-Json -Depth 10 -Compress))
        return $root
    }

    # "relative path = sha256" for every file under a folder; UpdateBackups is the updater's own output.
    function Get-TreeSnapshot {
        param([string]$Root, [string]$Filter = '*')
        $base = (Resolve-Path -LiteralPath $Root).ProviderPath
        $lines = foreach ($file in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
            $relative = [IO.Path]::GetRelativePath($base, $file.FullName).Replace('\', '/')
            if ($relative -like 'UpdateBackups/*' -or $relative -notlike $Filter) { continue }
            '{0} = {1}' -f $relative, (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        return (@($lines) | Sort-Object) -join "`n"
    }

    function Invoke-TestLocalUpdate {
        param([string]$Package, [string]$Install, [switch]$SkipRestart, [switch]$AllowDowngrade)
        $arguments = @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:OrchestratorPath,
            '-PackageRoot', $Package, '-InstallRoot', $Install,
            '-VersionFile', (Join-Path $Install 'VERSION'), '-Apply'
        )
        if ($SkipRestart) { $arguments += '-SkipRestart' }
        if ($AllowDowngrade) { $arguments += '-AllowDowngrade' }
        $output = & $script:Pwsh @arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

Describe 'Local package update' {
    It 'restores the previous application files byte for byte and leaves state untouched when the new start fails' {
        $install = New-TestInstall
        $package = New-TestPackage
        $before = Get-TreeSnapshot -Root $install
        $stateBefore = Get-TreeSnapshot -Root $install -Filter 'state/*'

        $run = Invoke-TestLocalUpdate -Package $package -Install $install

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*Updated ChannelForge failed its startup health check*'
        $run.Output | Should -Not -BeLike '*Update installed successfully*'
        # Whole install tree is identical: old files back, new-only files gone, state intact.
        Get-TreeSnapshot -Root $install | Should -BeExactly $before
        Get-TreeSnapshot -Root $install -Filter 'state/*' | Should -BeExactly $stateBefore
        Test-Path -LiteralPath (Join-Path $install 'src\new-only.ps1') | Should -BeFalse
    }

    It 'keeps state byte-identical after a successful update and installs the new files' {
        $install = New-TestInstall
        $package = New-TestPackage
        $stateBefore = Get-TreeSnapshot -Root $install -Filter 'state/*'
        $stateBefore | Should -BeLike '*state/source-enrollment.json*'
        $stateBefore | Should -BeLike "*state/managed-sources/$('a' * 64).m3u*"

        $run = Invoke-TestLocalUpdate -Package $package -Install $install -SkipRestart

        $run.ExitCode | Should -Be 0
        $run.Output | Should -BeLike '*Update installed successfully: 2.0.0*'
        $run.Output | Should -BeLike '*no published SHA-256 is checked on this path*'
        Get-TreeSnapshot -Root $install -Filter 'state/*' | Should -BeExactly $stateBefore
        Get-TreeSnapshot -Root $install -Filter 'src/app.ps1' | Should -BeExactly (Get-TreeSnapshot -Root $package -Filter 'src/app.ps1')
        [IO.File]::ReadAllText((Join-Path $install 'VERSION')) | Should -BeExactly '2.0.0'
    }

    It 'stops before replacing any application file when the backup cannot be made' {
        $install = New-TestInstall
        $package = New-TestPackage
        # A file where the backup folder must go makes the backup fail.
        Set-TestFile $install 'UpdateBackups' (ConvertTo-TestBytes 'not a folder')
        $before = Get-TreeSnapshot -Root $install

        $run = Invoke-TestLocalUpdate -Package $package -Install $install -SkipRestart

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Not -BeLike '*Update installed successfully*'
        Get-TreeSnapshot -Root $install | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $install 'package-manifest.json') | Should -BeFalse
    }

    It 'refuses a package that is older than the installed version and changes nothing' {
        $install = New-TestInstall -Version '3.0.0'
        $package = New-TestPackage -Version '2.0.0'
        $before = Get-TreeSnapshot -Root $install

        $run = Invoke-TestLocalUpdate -Package $package -Install $install -SkipRestart

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*This package (2.0.0) is not newer than the installed version (3.0.0). Nothing was changed.*'
        $run.Output | Should -Not -BeLike '*Update installed successfully*'
        Get-TreeSnapshot -Root $install | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $install 'UpdateBackups') | Should -BeFalse
    }

    It 'refuses a package with the same version as the installed one and changes nothing' {
        $install = New-TestInstall -Version '2.0.0'
        $package = New-TestPackage -Version '2.0.0'
        $before = Get-TreeSnapshot -Root $install

        $run = Invoke-TestLocalUpdate -Package $package -Install $install -SkipRestart

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -BeLike '*is not newer than the installed version*'
        Get-TreeSnapshot -Root $install | Should -BeExactly $before
    }

    It 'installs an older package when -AllowDowngrade is given' {
        $install = New-TestInstall -Version '3.0.0'
        $package = New-TestPackage -Version '2.0.0'

        $run = Invoke-TestLocalUpdate -Package $package -Install $install -SkipRestart -AllowDowngrade

        $run.ExitCode | Should -Be 0
        $run.Output | Should -BeLike '*Update installed successfully: 2.0.0*'
        [IO.File]::ReadAllText((Join-Path $install 'VERSION')) | Should -BeExactly '2.0.0'
    }

    It 'still installs when there is no installed VERSION yet (first install)' {
        $install = New-TestInstall
        Remove-Item -LiteralPath (Join-Path $install 'VERSION')
        $package = New-TestPackage -Version '2.0.0'

        $run = Invoke-TestLocalUpdate -Package $package -Install $install -SkipRestart

        $run.ExitCode | Should -Be 0
        [IO.File]::ReadAllText((Join-Path $install 'VERSION')) | Should -BeExactly '2.0.0'
    }
}
