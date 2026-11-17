BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1') -Force
    $script:Executor = Join-Path $script:Repo 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
    $script:PlanScript = Join-Path $script:Repo 'scripts/Get-ChannelForgeSourceRefreshPlan.ps1'

    function New-Project {
        $root = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'), (Join-Path $root 'data/epg'), (Join-Path $root 'cache') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.json') -Value '{"provider":"fixture","sources":[]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg.json') -Value '{"epg_sources":[]}'
        Set-Content -LiteralPath (Join-Path $root 'cache/keep.txt') -Value 'last-known-good'
        $root
    }
    function Invoke-Script([string]$Script, [string]$Root, [string]$Cache, [string]$Out) {
        & $Script -Root $Root -ProviderConfigPath (Join-Path $Root 'data/providers/provider.json') `
            -EpgConfigPath (Join-Path $Root 'data/epg/epg.json') -CacheRoot $Cache -OutputRoot $Out `
            -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T00:00:00Z')
    }
}

Describe 'source refresh wrappers confine OutputRoot and CacheRoot to the project root' {
    It 'still writes reports under an allowed root' {
        $root = New-Project
        $r = Invoke-Script $script:Executor $root (Join-Path $root 'cache') (Join-Path $root 'reports')
        Test-Path -LiteralPath $r.JsonPath | Should -BeTrue
        $p = Invoke-Script $script:PlanScript $root (Join-Path $root 'cache') (Join-Path $root 'reports')
        Test-Path -LiteralPath $p.JsonPath | Should -BeTrue
    }

    It 'rejects an OutputRoot outside the root before writing anything' {
        $root = New-Project
        $outside = Join-Path $TestDrive ('outside-' + [guid]::NewGuid().ToString('N'))
        foreach ($script in @($script:Executor, $script:PlanScript)) {
            { Invoke-Script $script $root (Join-Path $root 'cache') $outside } | Should -Throw '*approved location*'
        }
        Test-Path -LiteralPath $outside | Should -BeFalse
    }

    It 'rejects .. traversal in OutputRoot and CacheRoot, and leaves the cache unchanged' {
        $root = New-Project
        $escape = Join-Path $root '../escaped'
        { Invoke-Script $script:Executor $root (Join-Path $root 'cache') $escape } | Should -Throw '*approved location*'
        { Invoke-Script $script:Executor $root $escape (Join-Path $root 'reports') } | Should -Throw '*approved location*'
        Test-Path -LiteralPath (Join-Path $root '../escaped') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'reports') | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $root 'cache/keep.txt') | Should -Be 'last-known-good'
    }
}

Describe 'Export-ChannelForgeM3UPlaylist -AllowedRoot' {
    BeforeAll {
        $script:Channel = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'One' -DisplayName 'One' -TvgId 'one.us' -Url 'https://example.invalid/one.ts' -Group 'Sports' -Logo ''
    }

    It 'writes the same bytes with or without an allowed root' {
        $dir = Join-Path $TestDrive 'm3u-ok'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @($script:Channel) | Export-ChannelForgeM3UPlaylist -Path (Join-Path $dir 'a.m3u')
        @($script:Channel) | Export-ChannelForgeM3UPlaylist -Path (Join-Path $dir 'b.m3u') -AllowedRoot $dir
        @($script:Channel) | Export-ChannelForgeM3UPlaylist -Path (Join-Path $dir 'c.m3u') -AllowedRoot $dir
        $a = [IO.File]::ReadAllBytes((Join-Path $dir 'a.m3u'))
        [IO.File]::ReadAllBytes((Join-Path $dir 'b.m3u')) | Should -Be $a
        [IO.File]::ReadAllBytes((Join-Path $dir 'c.m3u')) | Should -Be $a
    }

    It 'rejects a path outside the root or using .. and writes nothing' {
        $dir = Join-Path $TestDrive 'm3u-root'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $outside = Join-Path $TestDrive 'm3u-outside.m3u'
        $dotdot = Join-Path $dir '../m3u-dotdot.m3u'
        { @($script:Channel) | Export-ChannelForgeM3UPlaylist -Path $outside -AllowedRoot $dir } | Should -Throw '*approved location*'
        { @($script:Channel) | Export-ChannelForgeM3UPlaylist -Path $dotdot -AllowedRoot $dir } | Should -Throw '*approved location*'
        Test-Path -LiteralPath $outside | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $TestDrive 'm3u-dotdot.m3u') | Should -BeFalse
    }

    It 'keeps the stream URL out of the error message' {
        $dir = Join-Path $TestDrive 'm3u-root2'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $err = try { @($script:Channel) | Export-ChannelForgeM3UPlaylist -Path (Join-Path $TestDrive 'x.m3u') -AllowedRoot $dir } catch { $_.Exception.Message }
        $err | Should -Not -BeLike '*example.invalid*'
    }
}
