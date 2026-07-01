# Destructive-path validation for tools/Invoke-ChannelForgeAutoUpdate.ps1 and
# tools/ChannelForgeAutoUpdate.Core.psm1. Every scenario below deliberately
# induces a failure (corrupt data, locked files, missing package content) and
# asserts that:
#   - protected data (data/, config/, output/, secrets, env files) is never
#     modified
#   - allowed update files install correctly when the run does succeed
#   - a failure leaves the installation consistent (no partial state)
#   - the backup remains usable
#   - temp files do not leak
#
# Run with: Invoke-Pester -Path .\tests\unit\ChannelForgeAutoUpdate.DestructivePath.Tests.ps1

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\..\tools\ChannelForgeAutoUpdate.Core.psm1'
    $script:OrchestratorPath = Join-Path $PSScriptRoot '..\..\tools\Invoke-ChannelForgeAutoUpdate.ps1'
    Import-Module $script:ModulePath -Force

    function New-DestructiveInstallRoot {
        param([string]$Version = '0.1.0')

        $root = Join-Path $TestDrive ("cf-destructive-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'data\providers') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value $Version -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'src\existing.psm1') -Value 'old code' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Value '{"token":"REAL-USER-SECRET"}' -NoNewline
        return $root
    }

    function New-FixtureZipBytes {
        param(
            [Parameter(Mandatory)][hashtable]$Entries
        )

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cf-fixture-staging-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cf-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
        try {
            foreach ($relativePath in $Entries.Keys) {
                $fullPath = Join-Path $stagingDir $relativePath
                New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
                Set-Content -LiteralPath $fullPath -Value $Entries[$relativePath] -NoNewline
            }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
            return , ([System.IO.File]::ReadAllBytes($zipPath))
        } finally {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-CorruptedFixtureZipBytes {
        param([Parameter(Mandatory)][hashtable]$Entries)

        $bytes = [byte[]](New-FixtureZipBytes -Entries $Entries).Clone()

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $probePath = Join-Path ([System.IO.Path]::GetTempPath()) ("cf-corrupt-probe-" + [guid]::NewGuid().ToString('N') + '.zip')
        [System.IO.File]::WriteAllBytes($probePath, $bytes)
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($probePath)
            $entry = $zip.Entries[0]
            $compressedLength = $entry.CompressedLength
            $zip.Dispose()
        } finally {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }

        if ($compressedLength -eq 0) {
            throw 'Test fixture error: entry has zero compressed length.'
        }

        $filenameLen = [System.BitConverter]::ToUInt16($bytes, 26)
        $extraLen = [System.BitConverter]::ToUInt16($bytes, 28)
        $dataStart = 30 + $filenameLen + $extraLen

        for ($i = $dataStart; $i -lt ($dataStart + $compressedLength); $i++) {
            $bytes[$i] = $bytes[$i] -bxor 0xFF
        }

        return , $bytes
    }

    function Invoke-ChannelForgeApplyWithMockedRelease {
        param(
            [Parameter(Mandatory)][string]$InstallRoot,
            [Parameter(Mandatory)][scriptblock]$WebRequestMock,
            [string]$AssetName = 'ChannelForge.zip'
        )

        # Get-ChannelForgeLatestReleaseInfo is called directly by the
        # orchestrator script, which runs outside the module -- Mock
        # -ModuleName only intercepts calls made by code running *inside*
        # the module, so mocking that entry point directly has no effect on
        # this call site (verified empirically). Mock the internal
        # dependency it calls instead (Invoke-GitHubJsonRequest), which is
        # invoked from Get-ChannelForgeLatestReleaseInfo's own module-scoped
        # function body and so is reachable.
        Mock -ModuleName ChannelForgeAutoUpdate.Core Invoke-GitHubJsonRequest {
            [pscustomobject]@{
                tag_name = 'v0.2.0'
                assets   = @([pscustomobject]@{
                    name                  = $AssetName
                    browser_download_url = "https://github.com/Jumpstile/ChannelForge/releases/download/v0.2.0/$AssetName"
                })
            }
        }.GetNewClosure()
        Mock -ModuleName ChannelForgeAutoUpdate.Core Invoke-WebRequest $WebRequestMock

        $versionFile = Join-Path $InstallRoot 'VERSION'
        $errorOutput = $null
        $stdout = $null
        try {
            $stdout = & $script:OrchestratorPath -Apply -VersionFile $versionFile -InstallRoot $InstallRoot -Owner 'Jumpstile' -Repository 'ChannelForge' *>&1
        } catch {
            $errorOutput = $_
        }

        return [pscustomobject]@{
            StdOut = $stdout
            Error  = $errorOutput
        }
    }
}

Describe '1. Corrupt ZIP' {
    It 'leaves the install root untouched, preserves the backup, and reports a clear error' {
        $root = New-DestructiveInstallRoot
        $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
            param($Uri, $Headers, $OutFile, $UseBasicParsing)
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1..64 | ForEach-Object { Get-Random -Maximum 255 }))
        }

        $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        (Get-Content -LiteralPath (Join-Path $root 'src\existing.psm1') -Raw) | Should -Be 'old code'
        (Get-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Raw) | Should -Match 'REAL-USER-SECRET'

        $backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Directory -ErrorAction SilentlyContinue)
        $backupDirs.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $backupDirs[0].FullName 'src\existing.psm1') | Should -BeTrue

        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'channelforge-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'channelforge-extract-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe '2. Missing expected package paths' {
    It 'reports nothing copied instead of falsely claiming success when the package has no recognized content' {
        $root = New-DestructiveInstallRoot
        $zipBytes = New-FixtureZipBytes -Entries @{ 'random-unrelated-file.txt' = 'not a real package' }

        $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
            param($Uri, $Headers, $OutFile, $UseBasicParsing)
            [System.IO.File]::WriteAllBytes($OutFile, $zipBytes)
        }.GetNewClosure()

        $result.Error | Should -BeNullOrEmpty
        ($result.StdOut -join "`n") | Should -Match 'Skipped'
        ($result.StdOut -join "`n") | Should -Not -Match 'Updated\s*:'

        # Nothing recognized was in the package, so the install root must be
        # byte-for-byte unchanged even though the run "succeeded".
        (Get-Content -LiteralPath (Join-Path $root 'src\existing.psm1') -Raw) | Should -Be 'old code'
        (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw) | Should -Be '0.1.0'
    }
}

Describe '3. Attempted overwrite of protected config/data/output paths' {
    It 'skips a package-supplied data/ directory and leaves existing protected data untouched' {
        $root = New-DestructiveInstallRoot
        $zipBytes = New-FixtureZipBytes -Entries @{
            'src\new.psm1'                = 'new code'
            'data\providers\mybunny.json' = '{"token":"ATTACKER-CONTROLLED-VALUE"}'
            'config\settings.json'        = '{"malicious":true}'
        }

        $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
            param($Uri, $Headers, $OutFile, $UseBasicParsing)
            [System.IO.File]::WriteAllBytes($OutFile, $zipBytes)
        }.GetNewClosure()

        $result.Error | Should -BeNullOrEmpty
        ($result.StdOut -join "`n") | Should -Match 'Skipped.*data'

        # Protected data must survive exactly as it was.
        (Get-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Raw) | Should -Match 'REAL-USER-SECRET'
        (Get-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Raw) | Should -Not -Match 'ATTACKER-CONTROLLED-VALUE'
        Test-Path -LiteralPath (Join-Path $root 'config') | Should -BeFalse

        # Allowed content from the same package must still install.
        Test-Path -LiteralPath (Join-Path $root 'src\new.psm1') | Should -BeTrue
    }
}

Describe '4. Read-only destination' {
    It 'refuses the update with a clear error instead of letting Copy-Item -Force clear ReadOnly' {
        # Assert-ChannelForgeWritableTarget checks every allowed target before
        # any copying begins, rather than relying on Copy-Item -Force --
        # which was previously found (empirically) to silently clear the
        # ReadOnly attribute and overwrite the file anyway.
        $root = New-DestructiveInstallRoot
        $targetPath = Join-Path $root 'src\existing.psm1'
        Set-ItemProperty -LiteralPath $targetPath -Name IsReadOnly -Value $true

        $zipBytes = New-FixtureZipBytes -Entries @{ 'src\existing.psm1' = 'new code' }

        try {
            $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $zipBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'read-only'
            $result.Error.Exception.Message | Should -Match ([regex]::Escape($targetPath))

            (Get-Content -LiteralPath $targetPath -Raw) | Should -Be 'old code'
        } finally {
            Set-ItemProperty -LiteralPath $targetPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }

        (Get-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Raw) | Should -Match 'REAL-USER-SECRET'

        # The check runs before any copying, so nothing should have been
        # installed even though the package also had other allowed content.
        $backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Directory -ErrorAction SilentlyContinue)
        $backupDirs.Count | Should -Be 1
        (Get-Content -LiteralPath (Join-Path $backupDirs[0].FullName 'src\existing.psm1') -Raw) | Should -Be 'old code'
    }
}

Describe '5. Backup failure' {
    It 'aborts before any download when the backup cannot be created, leaving the install root untouched' {
        $root = New-DestructiveInstallRoot

        Mock -ModuleName ChannelForgeAutoUpdate.Core New-Item {
            throw 'Access to the path is denied (simulated backup failure).'
        } -ParameterFilter { $ItemType -eq 'Directory' }

        $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
            param($Uri, $Headers, $OutFile, $UseBasicParsing)
            throw 'Invoke-WebRequest should never be called when backup fails first.'
        }

        $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $result.Error.Exception.Message | Should -Match 'denied'

        (Get-Content -LiteralPath (Join-Path $root 'src\existing.psm1') -Raw) | Should -Be 'old code'
        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'channelforge-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe '6. Extraction failure (corrupted entry payload, valid central directory)' {
    It 'reports the extraction failure, leaves the install root untouched, and preserves the backup' {
        $root = New-DestructiveInstallRoot
        $largeContent = ('X' * 200 + "`n") * 300
        $corruptedBytes = Get-CorruptedFixtureZipBytes -Entries @{ 'src\new.psm1' = $largeContent }

        $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
            param($Uri, $Headers, $OutFile, $UseBasicParsing)
            [System.IO.File]::WriteAllBytes($OutFile, $corruptedBytes)
        }.GetNewClosure()

        $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])

        (Get-Content -LiteralPath (Join-Path $root 'src\existing.psm1') -Raw) | Should -Be 'old code'
        (Get-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Raw) | Should -Match 'REAL-USER-SECRET'

        $backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Directory -ErrorAction SilentlyContinue)
        $backupDirs.Count | Should -Be 1

        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'channelforge-extract-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe '7. Copy failure (locked allowed-target file)' {
    It 'reports the copy failure and leaves protected data and the backup intact' {
        $root = New-DestructiveInstallRoot
        $lockedPath = Join-Path $root 'src\existing.psm1'
        $zipBytes = New-FixtureZipBytes -Entries @{ 'src\existing.psm1' = 'new code' }

        $lockHandle = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $result = Invoke-ChannelForgeApplyWithMockedRelease -InstallRoot $root -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $zipBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        } finally {
            $lockHandle.Dispose()
        }

        (Get-Content -LiteralPath (Join-Path $root 'data\providers\mybunny.json') -Raw) | Should -Match 'REAL-USER-SECRET'

        $backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Directory -ErrorAction SilentlyContinue)
        $backupDirs.Count | Should -Be 1
        (Get-Content -LiteralPath (Join-Path $backupDirs[0].FullName 'src\existing.psm1') -Raw) | Should -Be 'old code'

        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'channelforge-extract-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe '8. No GitHub release still exits cleanly' {
    It 'reports no release available and makes no filesystem changes' {
        $root = New-DestructiveInstallRoot
        $versionFile = Join-Path $root 'VERSION'

        Mock -ModuleName ChannelForgeAutoUpdate.Core Invoke-GitHubJsonRequest {
            $response = [pscustomobject]@{ StatusCode = 404 }
            $exception = [System.Net.Http.HttpRequestException]::new('Not Found')
            $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response -Force
            throw $exception
        }

        $output = & $script:OrchestratorPath -CheckOnly -VersionFile $versionFile -InstallRoot $root -Owner 'Jumpstile' -Repository 'ChannelForge' *>&1

        ($output -join "`n") | Should -Match 'No GitHub release is available yet'
        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $root 'src\existing.psm1') -Raw) | Should -Be 'old code'
    }
}

Describe '9. Module-scope error-action regression guard' {
    It 'sets its own $ErrorActionPreference to Stop regardless of import history' {
        # Regression guard for a real bug found while writing this suite: a
        # module's $ErrorActionPreference is snapshotted from the caller at
        # *import* time. Since the orchestrator intentionally imports without
        # -Force (to stay mockable -- see its own comment), an already-loaded
        # module instance (e.g. from this test file's own BeforeAll import,
        # done before the orchestrator ever sets $ErrorActionPreference =
        # 'Stop') would silently keep whatever preference was active back
        # then. Under 'Continue', a locked destination file during
        # Copy-ChannelForgeUpdatePackageContent's Copy-Item call printed a
        # warning and carried on, reporting "Update installed successfully"
        # while actually leaving the old file in place -- confirmed directly
        # against a real lock in "7. Copy failure" above, once this was
        # fixed. Checking the module-scope variable directly here (rather
        # than via Mock, whose substitute scriptblocks run with their own
        # default 'Continue' regardless of the module's setting -- verified
        # empirically, and it made an earlier version of this exact test a
        # false pass) is what actually confirms the fix is in place.
        InModuleScope ChannelForgeAutoUpdate.Core {
            $ErrorActionPreference | Should -Be 'Stop'
        }
    }
}
