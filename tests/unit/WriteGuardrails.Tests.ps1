BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Test-ChannelForgeWritePath' {
    It 'accepts a path inside the allowed root' {
        InModuleScope ChannelForge {
            $root = Join-Path $TestDrive 'output'
            $target = Join-Path $root 'reports\build-summary.json'
            Test-ChannelForgeWritePath -Path $target -AllowedRoot $root | Should -BeTrue
        }
    }

    It 'accepts the allowed root itself' {
        InModuleScope ChannelForge {
            $root = Join-Path $TestDrive 'output'
            Test-ChannelForgeWritePath -Path $root -AllowedRoot $root | Should -BeTrue
        }
    }

    It 'rejects a path outside the allowed root' {
        InModuleScope ChannelForge {
            $root = Join-Path $TestDrive 'output'
            $target = Join-Path $TestDrive 'elsewhere\file.json'
            Test-ChannelForgeWritePath -Path $target -AllowedRoot $root | Should -BeFalse
        }
    }

    It 'rejects an attempt to escape the allowed root with ..' {
        InModuleScope ChannelForge {
            $root = Join-Path $TestDrive 'output'
            $target = Join-Path $root '..\elsewhere\file.json'
            Test-ChannelForgeWritePath -Path $target -AllowedRoot $root | Should -BeFalse
        }
    }

    It 'rejects a sibling directory with a matching name prefix' {
        InModuleScope ChannelForge {
            $root = Join-Path $TestDrive 'output'
            $target = Join-Path $TestDrive 'output-other\file.json'
            Test-ChannelForgeWritePath -Path $target -AllowedRoot $root | Should -BeFalse
        }
    }

    It 'rejects empty values' {
        InModuleScope ChannelForge {
            Test-ChannelForgeWritePath -Path '' -AllowedRoot (Join-Path $TestDrive 'output') | Should -BeFalse
            Test-ChannelForgeWritePath -Path (Join-Path $TestDrive 'output\x') -AllowedRoot '' | Should -BeFalse
        }
    }
}

Describe 'Assert-ChannelForgeWritePath' {
    It 'does not throw for a path inside the allowed root' {
        $root = Join-Path $TestDrive 'output'
        $target = Join-Path $root 'reports\build-summary.json'

        { Assert-ChannelForgeWritePath -Path $target -AllowedRoot $root } | Should -Not -Throw
    }

    It 'throws for a path outside the allowed root' {
        $root = Join-Path $TestDrive 'output'
        $target = Join-Path $TestDrive 'elsewhere\file.json'

        { Assert-ChannelForgeWritePath -Path $target -AllowedRoot $root } | Should -Throw
    }
}

Describe 'Assert-ChannelForgeReadPath' {
    It 'does not throw for a path inside the allowed root' {
        $root = Join-Path $TestDrive 'data\playlists'
        $target = Join-Path $root 'sports.local.m3u'

        { Assert-ChannelForgeReadPath -Path $target -AllowedRoot $root } | Should -Not -Throw
    }

    It 'throws for a path outside the allowed root' {
        $root = Join-Path $TestDrive 'data\playlists'
        $target = Join-Path $TestDrive 'elsewhere\file.m3u'

        { Assert-ChannelForgeReadPath -Path $target -AllowedRoot $root } | Should -Throw
    }

    It 'throws for a .. traversal attempt that escapes the allowed root' {
        $root = Join-Path $TestDrive 'data\playlists'
        $target = Join-Path $root '..\..\elsewhere\file.m3u'

        { Assert-ChannelForgeReadPath -Path $target -AllowedRoot $root } | Should -Throw
    }

    It 'throws for a UNC path' {
        $root = Join-Path $TestDrive 'data\playlists'

        { Assert-ChannelForgeReadPath -Path '\\server\share\file.m3u' -AllowedRoot $root } | Should -Throw
    }

    It 'throws for a drive root or system path unrelated to the allowed root' {
        $root = Join-Path $TestDrive 'data\playlists'

        { Assert-ChannelForgeReadPath -Path 'C:\Windows\System32\drivers\etc\hosts' -AllowedRoot $root } | Should -Throw
    }
}

Describe 'Assert-ChannelForgePathExists' {
    It 'does not throw when the required file exists' {
        $path = Join-Path $TestDrive 'present.json'
        Set-Content -LiteralPath $path -Value '{}'

        { Assert-ChannelForgePathExists -Path $path -PathType Leaf } | Should -Not -Throw
    }

    It 'throws when the required file is missing' {
        $path = Join-Path $TestDrive 'missing.json'

        { Assert-ChannelForgePathExists -Path $path -PathType Leaf -Description 'Required source file' } | Should -Throw '*Required source file*'
    }

    It 'throws when a required directory is missing' {
        $path = Join-Path $TestDrive 'missing-dir'

        { Assert-ChannelForgePathExists -Path $path -PathType Container -Description 'IPTVBoss data path' } | Should -Throw '*IPTVBoss data path*'
    }
}

Describe 'Test-ChannelForgeBackupSourcePath' {
    It 'accepts a normal nested data directory' {
        InModuleScope ChannelForge {
            $path = Join-Path $TestDrive 'project\iptvboss-data'
            Test-ChannelForgeBackupSourcePath -Path $path | Should -BeTrue
        }
    }

    It 'rejects a drive root' {
        InModuleScope ChannelForge {
            Test-ChannelForgeBackupSourcePath -Path 'C:\' | Should -BeFalse
        }
    }

    It 'rejects a well-known system directory directly under a drive root' {
        InModuleScope ChannelForge {
            Test-ChannelForgeBackupSourcePath -Path 'C:\Windows' | Should -BeFalse
            Test-ChannelForgeBackupSourcePath -Path 'C:\Program Files' | Should -BeFalse
        }
    }

    It 'does not reject a deeply nested path that happens to share a blocked name' {
        InModuleScope ChannelForge {
            $path = Join-Path $TestDrive 'appdata\boot\iptvboss-data'
            Test-ChannelForgeBackupSourcePath -Path $path | Should -BeTrue
        }
    }

    It 'rejects empty values' {
        InModuleScope ChannelForge {
            Test-ChannelForgeBackupSourcePath -Path '' | Should -BeFalse
        }
    }
}

Describe 'Assert-ChannelForgeBackupSourcePath' {
    It 'does not throw for a normal nested data directory' {
        $path = Join-Path $TestDrive 'project\iptvboss-data'

        { Assert-ChannelForgeBackupSourcePath -Path $path } | Should -Not -Throw
    }

    It 'throws for a drive root' {
        { Assert-ChannelForgeBackupSourcePath -Path 'C:\' } | Should -Throw '*system directory*'
    }

    It 'throws for a well-known system directory' {
        { Assert-ChannelForgeBackupSourcePath -Path 'C:\Windows' } | Should -Throw '*system directory*'
    }
}
