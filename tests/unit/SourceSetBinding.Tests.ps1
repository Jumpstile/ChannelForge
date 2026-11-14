BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
}

Describe 'Set-ChannelForgeSourceSetBinding' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $script:Files = Join-Path $TestDrive ('files-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Project, $script:Files | Out-Null
        function Add-Source {
            param([string]$Name, [string]$Kind)
            $path = Join-Path $script:Files "$Name.$(if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' })"
            $text = if ($Kind -eq 'M3U') { "#EXTM3U`n#EXTINF:-1 tvg-id=`"$Name`",$Name`nhttps://example.invalid/$Name`n" }
            else { "<?xml version=`"1.0`"?><tv><channel id=`"$Name`"><display-name>$Name</display-name></channel><programme start=`"20260101000000 +0000`" stop=`"20260101010000 +0000`" channel=`"$Name`"><title>$Name</title></programme></tv>" }
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
            Add-ChannelForgeSourceSetSource -Kind $Kind -Path $path -Label $Name -RepositoryRoot $script:Project
        }
        function Get-Set { & (Get-Module ChannelForge) { param($root) Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $root } $script:Project }
        function Get-SetBytes { [IO.File]::ReadAllBytes((Join-Path $script:Project 'state/source-enrollment.json')) }
        function Get-BindingOf { param($Guide) @((Get-Set).Bindings | Where-Object GuideId -eq $Guide.SourceId)[0] }
        $script:P1 = Add-Source 'alpha' 'M3U'
        $script:P2 = Add-Source 'beta' 'M3U'
        $script:G1 = Add-Source 'guide-one' 'XMLTV'
        $script:G2 = Add-Source 'guide-two' 'XMLTV'
    }

    It 'binds an unbound guide to one of two playlists' {
        $result = Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'beta' -RepositoryRoot $script:Project
        $result.Changed | Should -BeTrue
        $binding = Get-BindingOf $script:G1
        $binding.PlaylistIds | Should -Be @($script:P2.SourceId)
        $binding.AppliesToAll | Should -BeFalse
        $binding.Revision | Should -Be 1
        $binding.Enabled | Should -BeTrue
    }

    It 'binds two playlists, sorted and unique, by ID or label' {
        Set-ChannelForgeSourceSetBinding -SourceId $script:G1.SourceId -Playlist @($script:P2.SourceId, 'alpha', 'ALPHA', $script:P1.SourceId) -RepositoryRoot $script:Project | Out-Null
        (Get-BindingOf $script:G1).PlaylistIds | Should -Be @($script:P1.SourceId, $script:P2.SourceId | Sort-Object)
    }

    It 'stores ALL as the ALL mode, not a list' {
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -AllPlaylists -RepositoryRoot $script:Project | Out-Null
        $binding = Get-BindingOf $script:G1
        $binding.AppliesToAll | Should -BeTrue
        @($binding.PlaylistIds).Count | Should -Be 0
    }

    It 'unbinds on request and says so by guide label only' {
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -AllPlaylists -RepositoryRoot $script:Project | Out-Null
        $out = Set-ChannelForgeSourceSetBinding -Label 'guide-one' -NoPlaylist -RepositoryRoot $script:Project 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }
        @($out).Count | Should -Be 1
        "$($out.MessageData)" | Should -BeLike "*guide-one*"
        "$($out.MessageData)" | Should -Not -Match '[0-9a-f]{32}'
        $binding = Get-BindingOf $script:G1
        $binding.ExplicitlyUnbound | Should -BeTrue
        @($binding.PlaylistIds).Count | Should -Be 0
        $binding.Revision | Should -Be 2
    }

    It 'disables and enables the binding' {
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'alpha' -RepositoryRoot $script:Project | Out-Null
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'alpha' -Disable -RepositoryRoot $script:Project | Out-Null
        (Get-BindingOf $script:G1).Enabled | Should -BeFalse
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'alpha' -Enable -RepositoryRoot $script:Project | Out-Null
        (Get-BindingOf $script:G1).Enabled | Should -BeTrue
        (Get-BindingOf $script:G1).Revision | Should -Be 3
    }

    It 'a call that changes nothing leaves the file bytes and revision alone' {
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'alpha' -RepositoryRoot $script:Project | Out-Null
        $before = Get-SetBytes
        $result = Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist $script:P1.SourceId -Enable -RepositoryRoot $script:Project
        $result.Changed | Should -BeFalse
        Get-SetBytes | Should -Be $before
        (Get-BindingOf $script:G1).Revision | Should -Be 1
    }

    It 'changes Revision and BindingId on every real change' {
        $seen = @()
        foreach ($step in @(@{ Playlist = 'alpha' }, @{ Playlist = 'beta' }, @{ AllPlaylists = $true }, @{ NoPlaylist = $true }, @{ Playlist = 'alpha' })) {
            Set-ChannelForgeSourceSetBinding -Label 'guide-one' @step -RepositoryRoot $script:Project | Out-Null
            $binding = Get-BindingOf $script:G1
            $seen += "$($binding.Revision)/$($binding.BindingId)"
        }
        $seen.Count | Should -Be 5
        @($seen | Sort-Object -Unique).Count | Should -Be 5
    }

    It 'refuses an unknown playlist and a playlist given as the guide, changing nothing' {
        $before = Get-SetBytes
        { Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'nowhere' -RepositoryRoot $script:Project } | Should -Throw '*no saved playlist matches*'
        { Set-ChannelForgeSourceSetBinding -SourceId $script:P1.SourceId -Playlist 'beta' -RepositoryRoot $script:Project } | Should -Throw '*not a guide*'
        { Set-ChannelForgeSourceSetBinding -Label 'guide-one' -RepositoryRoot $script:Project } | Should -Throw '*exactly one*'
        Get-SetBytes | Should -Be $before
    }

    It 'leaves another guide''s binding untouched' {
        Set-ChannelForgeSourceSetBinding -Label 'guide-two' -Playlist 'alpha' -RepositoryRoot $script:Project | Out-Null
        $other = Get-BindingOf $script:G2
        Set-ChannelForgeSourceSetBinding -Label 'guide-one' -AllPlaylists -RepositoryRoot $script:Project | Out-Null
        $after = Get-BindingOf $script:G2
        $after.BindingId | Should -Be $other.BindingId
        $after.Revision | Should -Be $other.Revision
    }

    It 'refuses to edit an unhealthy set' {
        $snapshot = @(Get-ChildItem -LiteralPath (Join-Path $script:Project 'state/managed-sources') -File)[0]
        [IO.File]::AppendAllText($snapshot.FullName, "`n# changed")
        $before = Get-SetBytes
        { Set-ChannelForgeSourceSetBinding -Label 'guide-one' -Playlist 'alpha' -RepositoryRoot $script:Project } | Should -Throw '*SOURCE_ENROLLMENT_UNAVAILABLE*'
        Get-SetBytes | Should -Be $before
    }
}
