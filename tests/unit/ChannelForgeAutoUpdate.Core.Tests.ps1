BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $RepoRoot 'tools\ChannelForgeAutoUpdate.Core.psm1'
    $script:OrchestratorPath = Join-Path $RepoRoot 'tools\Invoke-ChannelForgeAutoUpdate.ps1'
    Import-Module $script:ModulePath -Force

    function New-ChannelForgeTestRelease {
        param(
            [string]$TagName = 'v0.2.0',
            [string[]]$AssetNames = @('ChannelForge-v0.2.0-windows-x64.zip'),
            [string]$Owner = 'Jumpstile',
            [string]$Repository = 'ChannelForge'
        )

        $assets = foreach ($name in $AssetNames) {
            [pscustomobject]@{
                name                  = $name
                browser_download_url = "https://github.com/$Owner/$Repository/releases/download/$TagName/$name"
            }
        }

        [pscustomobject]@{
            tag_name = $TagName
            assets   = @($assets)
        }
    }
}

Describe 'ConvertTo-ChannelForgeUpdateVersion' {
    It 'strips a leading v and parses a normal version' {
        InModuleScope ChannelForgeAutoUpdate.Core {
            ConvertTo-ChannelForgeUpdateVersion -VersionText 'v0.2.0' | Should -Be ([version]'0.2.0')
        }
    }

    It 'parses a version with no leading v' {
        InModuleScope ChannelForgeAutoUpdate.Core {
            ConvertTo-ChannelForgeUpdateVersion -VersionText '0.1.0' | Should -Be ([version]'0.1.0')
        }
    }

    It 'throws on a non-numeric version string' {
        InModuleScope ChannelForgeAutoUpdate.Core {
            { ConvertTo-ChannelForgeUpdateVersion -VersionText 'latest' } | Should -Throw
        }
    }
}

Describe 'Get-ChannelForgeLocalVersion' {
    It 'reads the version from a VERSION file' {
        $versionFile = Join-Path $TestDrive 'VERSION'
        Set-Content -LiteralPath $versionFile -Value '0.1.0' -NoNewline
        Get-ChannelForgeLocalVersion -Path $versionFile | Should -Be '0.1.0'
    }

    It 'throws when the VERSION file does not exist' {
        { Get-ChannelForgeLocalVersion -Path (Join-Path $TestDrive 'missing-VERSION') } | Should -Throw
    }

    It 'throws when the VERSION file is empty' {
        $versionFile = Join-Path $TestDrive 'empty-VERSION'
        New-Item -ItemType File -Path $versionFile -Force | Out-Null
        { Get-ChannelForgeLocalVersion -Path $versionFile } | Should -Throw
    }
}

Describe 'Test-ChannelForgeUpdateAssetUrl' {
    It 'accepts a well-formed GitHub release download URL' {
        Test-ChannelForgeUpdateAssetUrl -Url 'https://github.com/Jumpstile/ChannelForge/releases/download/v0.2.0/ChannelForge.zip' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeTrue
    }

    It 'rejects a non-GitHub host' {
        Test-ChannelForgeUpdateAssetUrl -Url 'https://evil.example.com/Jumpstile/ChannelForge/releases/download/v0.2.0/x.zip' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeFalse
    }

    It 'rejects a lookalike host with github.com as a subdomain prefix' {
        Test-ChannelForgeUpdateAssetUrl -Url 'https://github.com.evil.example.com/releases/download/v0.2.0/x.zip' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeFalse
    }

    It 'rejects embedded userinfo credentials' {
        Test-ChannelForgeUpdateAssetUrl -Url 'https://github.com@evil.example.com/releases/download/v0.2.0/x.zip' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeFalse
    }

    It 'rejects http (non-https)' {
        Test-ChannelForgeUpdateAssetUrl -Url 'http://github.com/Jumpstile/ChannelForge/releases/download/v0.2.0/x.zip' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeFalse
    }

    It 'rejects a GitHub URL outside the expected owner/repo/releases/download prefix' {
        Test-ChannelForgeUpdateAssetUrl -Url 'https://github.com/SomeoneElse/other-repo/releases/download/v1.0.0/x.zip' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeFalse
    }

    It 'rejects a malformed URL' {
        Test-ChannelForgeUpdateAssetUrl -Url 'not a url' -Owner 'Jumpstile' -Repository 'ChannelForge' | Should -BeFalse
    }
}

Describe 'Select-ChannelForgeUpdateAsset' {
    It 'selects the asset matching the pattern' {
        $release = New-ChannelForgeTestRelease -AssetNames @('ChannelForge.zip', 'unrelated-file.txt')
        $asset = Select-ChannelForgeUpdateAsset -Release $release -Pattern '^ChannelForge\.(zip|ps1|psm1)$' -Owner 'Jumpstile' -Repository 'ChannelForge'
        $asset.name | Should -Be 'ChannelForge.zip'
    }

    It 'throws when no asset matches the pattern' {
        $release = New-ChannelForgeTestRelease -AssetNames @('unrelated-file.txt')
        { Select-ChannelForgeUpdateAsset -Release $release -Pattern '^ChannelForge\.(zip|ps1|psm1)$' -Owner 'Jumpstile' -Repository 'ChannelForge' } | Should -Throw
    }

    It 'throws when the matching asset URL is not a real GitHub release URL' {
        $release = [pscustomobject]@{
            tag_name = 'v0.2.0'
            assets   = @([pscustomobject]@{
                name                  = 'ChannelForge.zip'
                browser_download_url = 'https://evil.example.com/ChannelForge.zip'
            })
        }
        { Select-ChannelForgeUpdateAsset -Release $release -Pattern '^ChannelForge\.(zip|ps1|psm1)$' -Owner 'Jumpstile' -Repository 'ChannelForge' } | Should -Throw
    }
}

Describe 'Get-ChannelForgeLatestReleaseInfo' {
    It 'reports Found = $false on a 404 (no releases published yet)' {
        InModuleScope ChannelForgeAutoUpdate.Core {
            Mock Invoke-GitHubJsonRequest {
                $response = [pscustomobject]@{ StatusCode = 404 }
                $exception = [System.Net.Http.HttpRequestException]::new('Not Found')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'NotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null
                )
                $errorRecord.ErrorDetails = $null
                $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response -Force
                throw $errorRecord
            }

            $result = Get-ChannelForgeLatestReleaseInfo -Owner 'Jumpstile' -Repository 'ChannelForge'
            $result.Found | Should -BeFalse
            $result.Release | Should -BeNullOrEmpty
        }
    }

    It 'returns the release when the request succeeds' {
        InModuleScope ChannelForgeAutoUpdate.Core {
            Mock Invoke-GitHubJsonRequest {
                [pscustomobject]@{ tag_name = 'v0.2.0'; assets = @() }
            }

            $result = Get-ChannelForgeLatestReleaseInfo -Owner 'Jumpstile' -Repository 'ChannelForge'
            $result.Found | Should -BeTrue
            $result.Release.tag_name | Should -Be 'v0.2.0'
        }
    }

    It 'rethrows on a non-404 failure' {
        InModuleScope ChannelForgeAutoUpdate.Core {
            Mock Invoke-GitHubJsonRequest {
                throw 'network unreachable'
            }

            { Get-ChannelForgeLatestReleaseInfo -Owner 'Jumpstile' -Repository 'ChannelForge' } | Should -Throw '*network unreachable*'
        }
    }
}

Describe 'Assert-ChannelForgeWritableTarget' {
    It 'throws a clear, actionable error when the target file is read-only' {
        $path = Join-Path $TestDrive 'readonly.psm1'
        Set-Content -LiteralPath $path -Value 'code' -NoNewline
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            { Assert-ChannelForgeWritableTarget -Path $path } | Should -Throw '*read-only*'
            { Assert-ChannelForgeWritableTarget -Path $path } | Should -Throw "*$path*"
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }

    It 'throws when a read-only file exists anywhere under a directory target' {
        $dir = Join-Path $TestDrive 'src-with-readonly'
        New-Item -ItemType Directory -Path (Join-Path $dir 'nested') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.psm1') -Value 'code' -NoNewline
        $nestedPath = Join-Path $dir 'nested\b.psm1'
        Set-Content -LiteralPath $nestedPath -Value 'code' -NoNewline
        Set-ItemProperty -LiteralPath $nestedPath -Name IsReadOnly -Value $true
        try {
            { Assert-ChannelForgeWritableTarget -Path $dir } | Should -Throw '*read-only*'
            { Assert-ChannelForgeWritableTarget -Path $dir } | Should -Throw "*$nestedPath*"
        } finally {
            Set-ItemProperty -LiteralPath $nestedPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }

    It 'does not throw when the target is writable' {
        $path = Join-Path $TestDrive 'writable.psm1'
        Set-Content -LiteralPath $path -Value 'code' -NoNewline
        { Assert-ChannelForgeWritableTarget -Path $path } | Should -Not -Throw
    }

    It 'does not throw when the target does not exist yet' {
        { Assert-ChannelForgeWritableTarget -Path (Join-Path $TestDrive 'does-not-exist.psm1') } | Should -Not -Throw
    }
}

Describe 'New-ChannelForgeUpdateBackup' {
    It 'backs up only allowed top-level names' {
        $root = Join-Path $TestDrive 'backup-root'
        New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'data') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'src\file.ps1') -Value 'code'
        Set-Content -LiteralPath (Join-Path $root 'data\secrets.json') -Value '{"token":"x"}'
        Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value '0.1.0'

        $backupDir = New-ChannelForgeUpdateBackup -Root $root

        Test-Path -LiteralPath (Join-Path $backupDir 'src\file.ps1') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $backupDir 'VERSION') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $backupDir 'data') | Should -BeFalse
    }

    It 'throws when the install root does not exist' {
        { New-ChannelForgeUpdateBackup -Root (Join-Path $TestDrive 'does-not-exist') } | Should -Throw
    }
}

Describe 'Test-ChannelForgeUpdateAllowedPath' {
    It 'allows known packaging paths' {
        Test-ChannelForgeUpdateAllowedPath -Name 'src' | Should -BeTrue
        Test-ChannelForgeUpdateAllowedPath -Name 'tools' | Should -BeTrue
        Test-ChannelForgeUpdateAllowedPath -Name 'VERSION' | Should -BeTrue
    }

    It 'denies protected data paths' {
        Test-ChannelForgeUpdateAllowedPath -Name 'data' | Should -BeFalse
        Test-ChannelForgeUpdateAllowedPath -Name 'config' | Should -BeFalse
        Test-ChannelForgeUpdateAllowedPath -Name 'output' | Should -BeFalse
        Test-ChannelForgeUpdateAllowedPath -Name 'backups' | Should -BeFalse
        Test-ChannelForgeUpdateAllowedPath -Name '.env' | Should -BeFalse
        Test-ChannelForgeUpdateAllowedPath -Name 'secrets.json' | Should -BeFalse
    }
}

Describe 'Copy-ChannelForgeUpdatePackageContent' {
    It 'copies allowed items and skips protected items' {
        $source = Join-Path $TestDrive 'extracted'
        $dest = Join-Path $TestDrive 'install-root'
        New-Item -ItemType Directory -Path (Join-Path $source 'src'), (Join-Path $source 'data\rules'), (Join-Path $source 'data\lineup') -Force | Out-Null
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'src\module.psm1') -Value 'new code'
        Set-Content -LiteralPath (Join-Path $source 'data\secrets.json') -Value '{"token":"stolen"}'
        Set-Content -LiteralPath (Join-Path $source 'data\rules\aliases.json') -Value '{"aliases":["package-default"]}' -NoNewline
        Set-Content -LiteralPath (Join-Path $source 'data\lineup\numbering_blocks.json') -Value '{"blocks":["package-default"]}' -NoNewline
        Set-Content -LiteralPath (Join-Path $source 'VERSION') -Value '0.2.0'

        # Pre-existing protected data in the install root must survive the update.
        New-Item -ItemType Directory -Path (Join-Path $dest 'data') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dest 'data\secrets.json') -Value '{"token":"real-user-secret"}'
        New-Item -ItemType Directory -Path (Join-Path $dest 'data\rules') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dest 'data\rules\aliases.json') -Value '{"aliases":["real-user-rule"]}' -NoNewline

        $result = Copy-ChannelForgeUpdatePackageContent -SourcePath $source -DestinationRoot $dest

        $result.Copied | Should -Contain 'src'
        $result.Copied | Should -Contain 'VERSION'
        $result.Skipped | Should -Contain 'data'
        $result.RequiredDataAdded | Should -Contain 'data/lineup/numbering_blocks.json'
        $result.RequiredDataAdded | Should -Not -Contain 'data/rules/aliases.json'

        Test-Path -LiteralPath (Join-Path $dest 'src\module.psm1') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $dest 'VERSION')) | Should -Be '0.2.0'
        (Get-Content -LiteralPath (Join-Path $dest 'data\secrets.json')) | Should -Match 'real-user-secret'
        (Get-Content -LiteralPath (Join-Path $dest 'data\rules\aliases.json')) | Should -Match 'real-user-rule'
        (Get-Content -LiteralPath (Join-Path $dest 'data\lineup\numbering_blocks.json')) | Should -Match 'package-default'
    }

    It 'throws when the source path does not exist' {
        { Copy-ChannelForgeUpdatePackageContent -SourcePath (Join-Path $TestDrive 'missing') -DestinationRoot $TestDrive } | Should -Throw
    }
}

Describe 'Invoke-ChannelForgeAutoUpdate -CheckOnly with no releases' {
    It 'reports no release available instead of throwing a 404' {
        $installRoot = Join-Path $TestDrive 'no-release-root'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $versionFile = Join-Path $installRoot 'VERSION'
        Set-Content -LiteralPath $versionFile -Value '0.1.0' -NoNewline

        Mock -ModuleName ChannelForgeAutoUpdate.Core Invoke-GitHubJsonRequest {
            $response = [pscustomobject]@{ StatusCode = 404 }
            $exception = [System.Net.Http.HttpRequestException]::new('Not Found')
            $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response -Force
            throw $exception
        }

        $output = & $script:OrchestratorPath -CheckOnly -VersionFile $versionFile -InstallRoot $installRoot -Owner 'Jumpstile' -Repository 'ChannelForge' *>&1

        ($output -join "`n") | Should -Match 'No GitHub release is available yet'
    }
}

Describe 'Invoke-ChannelForgeAutoUpdate -Apply -WhatIf' {
    It 'makes no backup, download, or replacement when -WhatIf is passed' {
        $installRoot = Join-Path $TestDrive 'whatif-root'
        New-Item -ItemType Directory -Path (Join-Path $installRoot 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $installRoot 'src\old.psm1') -Value 'old code'
        $versionFile = Join-Path $installRoot 'VERSION'
        Set-Content -LiteralPath $versionFile -Value '0.1.0' -NoNewline

        # The orchestrator calls the exported release lookup from script scope,
        # so a module-scoped mock of Get-ChannelForgeLatestReleaseInfo cannot
        # intercept that call. Mock its module-internal HTTP dependency instead
        # to keep this WhatIf behavior test entirely fixture-backed.
        Mock -ModuleName ChannelForgeAutoUpdate.Core Invoke-GitHubJsonRequest {
            [pscustomobject]@{
                tag_name = 'v0.2.0'
                assets   = @([pscustomobject]@{
                    name                  = 'ChannelForge-v0.2.0-windows-x64.zip'
                    browser_download_url = 'https://github.com/Jumpstile/ChannelForge/releases/download/v0.2.0/ChannelForge-v0.2.0-windows-x64.zip'
                })
            }
        }
        Mock -ModuleName ChannelForgeAutoUpdate.Core Invoke-WebRequest { throw 'Invoke-WebRequest should not be called during -WhatIf' }

        & $script:OrchestratorPath -Apply -WhatIf -VersionFile $versionFile -InstallRoot $installRoot -Owner 'Jumpstile' -Repository 'ChannelForge' *> $null

        Test-Path -LiteralPath (Join-Path $installRoot 'UpdateBackups') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $installRoot 'src\old.psm1')) | Should -Be 'old code'
    }
}
