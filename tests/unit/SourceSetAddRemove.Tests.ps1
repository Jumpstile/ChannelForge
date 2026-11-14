BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
}

Describe 'headless add and remove of managed-file sources' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $script:Files = Join-Path $TestDrive ('files-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Project, $script:Files | Out-Null
        function New-SourceFile {
            param([string]$Name, [string]$Kind)
            $path = Join-Path $script:Files "$Name.$(if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' })"
            $text = if ($Kind -eq 'M3U') { "#EXTM3U`n#EXTINF:-1 tvg-id=`"$Name`",$Name`nhttps://example.invalid/$Name`n" }
            else { "<?xml version=`"1.0`"?><tv><channel id=`"$Name`"><display-name>$Name</display-name></channel><programme start=`"20260101000000 +0000`" stop=`"20260101010000 +0000`" channel=`"$Name`"><title>$Name</title></programme></tv>" }
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
            return $path
        }
        function Add-Source {
            param([string]$Name, [string]$Kind, [string]$Label = $Name)
            Add-ChannelForgeSourceSetSource -Kind $Kind -Path (New-SourceFile $Name $Kind) -Label $Label -RepositoryRoot $script:Project
        }
        function Get-Set { & (Get-Module ChannelForge) { param($root) Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $root } $script:Project }
        function Get-SetBytes { [IO.File]::ReadAllBytes((Join-Path $script:Project 'state/source-enrollment.json')) }
        function Get-Snapshots { @(Get-ChildItem -LiteralPath (Join-Path $script:Project 'state/managed-sources') -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name) }
        function Set-TestBindings {
            param([object[]]$Bindings)
            & (Get-Module ChannelForge) {
                param($root, $bindings)
                $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $root
                Save-ChannelForgeSourceSetEdit -RepositoryRoot $root -Base $base -PlaylistSources $base.Playlists -GuideSources $base.Guides -Bindings $bindings | Out-Null
            } $script:Project $Bindings
        }
    }

    It 'adds a second playlist after the first and keeps the first untouched' {
        $first = Add-Source 'alpha' 'M3U'
        $firstRecord = @((Get-Set).Playlists)[0]
        $second = Add-Source 'beta' 'M3U'
        $set = Get-Set

        $set.Playlists.Count | Should -Be 2
        $second.SourceId | Should -Not -Be $first.SourceId
        $set.Playlists[1].SourceId | Should -Be $second.SourceId
        @($set.Playlists | Where-Object SourceId -eq $first.SourceId)[0].ContentHash | Should -Be $firstRecord.ContentHash
        @($set.Playlists | Where-Object SourceId -eq $second.SourceId)[0].Priority | Should -BeGreaterThan $firstRecord.Priority
        (Get-Snapshots).Count | Should -Be 2
        Test-Json -Path (Join-Path $script:Project 'state/source-enrollment.json') -SchemaFile (Join-Path $script:Root 'schemas/source-enrollment.schema.json') | Should -BeTrue
    }

    It 'uses the default label when none is given' {
        $added = Add-ChannelForgeSourceSetSource -Kind M3U -Path (New-SourceFile 'plain' 'M3U') -RepositoryRoot $script:Project
        $added.Label | Should -Be 'M3U source'
    }

    It 'binds a new guide to the only playlist, and leaves it unbound once there are two playlists' {
        $playlist = Add-Source 'alpha' 'M3U'
        $guideOne = Add-Source 'guide-one' 'XMLTV'
        $set = Get-Set
        $set.Bindings.Count | Should -Be 1
        $set.Bindings[0].GuideId | Should -Be $guideOne.SourceId
        $set.Bindings[0].PlaylistIds | Should -Be @($playlist.SourceId)
        $set.Bindings[0].Revision | Should -Be 1

        Add-Source 'beta' 'M3U' | Out-Null
        $guideTwo = Add-Source 'guide-two' 'XMLTV'
        $set = Get-Set
        $set.Guides.Count | Should -Be 2
        @($set.Bindings | Where-Object GuideId -eq $guideTwo.SourceId).Count | Should -Be 0
        $set.Bindings.Count | Should -Be 1
    }

    It 'removes a playlist from every binding without retargeting any guide' {
        $p1 = Add-Source 'alpha' 'M3U'
        $p2 = Add-Source 'beta' 'M3U'
        $g1 = Add-Source 'guide-one' 'XMLTV'
        $g2 = Add-Source 'guide-two' 'XMLTV'
        $g3 = Add-Source 'guide-three' 'XMLTV'
        Set-TestBindings @(
            [pscustomobject]@{ GuideId = $g1.SourceId; PlaylistIds = @($p1.SourceId); AppliesToAll = $false; Revision = 1 }
            [pscustomobject]@{ GuideId = $g2.SourceId; PlaylistIds = @($p2.SourceId); AppliesToAll = $false; Revision = 1 }
            [pscustomobject]@{ GuideId = $g3.SourceId; PlaylistIds = @($p1.SourceId, $p2.SourceId); AppliesToAll = $false; Revision = 4 }
        )
        $before = Get-Set
        $removedSnapshot = @($before.Playlists | Where-Object SourceId -eq $p1.SourceId)[0].ManagedPath

        Remove-ChannelForgeSourceSetSource -SourceId $p1.SourceId -RepositoryRoot $script:Project | Out-Null
        $after = Get-Set
        $bindingOf = { param($set, $id) @($set.Bindings | Where-Object GuideId -eq $id)[0] }

        @($after.Playlists).Count | Should -Be 1
        $after.Playlists[0].SourceId | Should -Be $p2.SourceId
        $after.Guides.Count | Should -Be 3
        $orphan = & $bindingOf $after $g1.SourceId
        @($orphan.PlaylistIds).Count | Should -Be 0
        $orphan.ExplicitlyUnbound | Should -BeTrue
        $orphan.Revision | Should -Be 2
        $shared = & $bindingOf $after $g3.SourceId
        $shared.PlaylistIds | Should -Be @($p2.SourceId)
        $shared.Revision | Should -Be 5
        (& $bindingOf $after $g2.SourceId).BindingId | Should -Be (& $bindingOf $before $g2.SourceId).BindingId
        (& $bindingOf $after $g2.SourceId).Revision | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:Project $removedSnapshot) | Should -BeFalse
        (Get-Snapshots).Count | Should -Be 4
    }

    It 'refuses to remove the last playlist and changes nothing' {
        $playlist = Add-Source 'alpha' 'M3U'
        Add-Source 'guide-one' 'XMLTV' | Out-Null
        $before = Get-SetBytes
        $snapshots = Get-Snapshots

        { Remove-ChannelForgeSourceSetSource -SourceId $playlist.SourceId -RepositoryRoot $script:Project } | Should -Throw '*last playlist*'
        [Convert]::ToBase64String((Get-SetBytes)) | Should -Be ([Convert]::ToBase64String($before))
        (Get-Snapshots) | Should -Be $snapshots
    }

    It 'keeps the accepted-state hashes across an add and a remove' {
        Add-Source 'alpha' 'M3U' | Out-Null
        & (Get-Module ChannelForge) {
            param($root)
            $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $root
            Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $base.Playlists -PreserveUnboundGuides -AcceptedGenerationManifestHash ('a' * 64) -AcceptedStateHash ('b' * 64) -AcceptedOutputManifestHash ('c' * 64) | Out-Null
        } $script:Project
        $second = Add-Source 'beta' 'M3U'
        $kept = (Get-Set).AcceptedWorkflow
        $kept.GenerationManifestHash | Should -Be ('a' * 64)
        $kept.AcceptedStateHash | Should -Be ('b' * 64)
        $kept.AcceptedOutputManifestHash | Should -Be ('c' * 64)

        Remove-ChannelForgeSourceSetSource -SourceId $second.SourceId -RepositoryRoot $script:Project | Out-Null
        $kept = (Get-Set).AcceptedWorkflow
        $kept.GenerationManifestHash | Should -Be ('a' * 64)
        $kept.AcceptedStateHash | Should -Be ('b' * 64)
        $kept.AcceptedOutputManifestHash | Should -Be ('c' * 64)
    }

    It 'removes a guide by label and drops only its binding' {
        $p1 = Add-Source 'alpha' 'M3U'
        $p2 = Add-Source 'beta' 'M3U'
        $g1 = Add-Source 'guide-one' 'XMLTV' 'Guide One'
        $g2 = Add-Source 'guide-two' 'XMLTV'
        Set-TestBindings @(
            [pscustomobject]@{ GuideId = $g1.SourceId; PlaylistIds = @($p1.SourceId); AppliesToAll = $false; Revision = 1 }
            [pscustomobject]@{ GuideId = $g2.SourceId; PlaylistIds = @($p2.SourceId); AppliesToAll = $false; Revision = 3 }
        )
        $before = Get-Set

        Remove-ChannelForgeSourceSetSource -Label 'guide one' -Kind XMLTV -RepositoryRoot $script:Project | Out-Null
        $after = Get-Set

        $after.Guides.Count | Should -Be 1
        $after.Guides[0].SourceId | Should -Be $g2.SourceId
        $after.Playlists.Count | Should -Be 2
        $after.Bindings.Count | Should -Be 1
        $after.Bindings[0].BindingId | Should -Be (@($before.Bindings | Where-Object GuideId -eq $g2.SourceId)[0]).BindingId
        $after.Bindings[0].Revision | Should -Be 3
        (Get-Snapshots).Count | Should -Be 3
    }

    It 'refuses an invalid, empty, or oversize file and saves nothing' {
        Add-Source 'alpha' 'M3U' | Out-Null
        $before = Get-SetBytes
        $snapshots = Get-Snapshots
        $bad = Join-Path $script:Files 'bad.xml'
        [IO.File]::WriteAllText($bad, '<tv><channel', [Text.UTF8Encoding]::new($false))
        $notPlaylist = Join-Path $script:Files 'not-a-playlist.m3u'
        [IO.File]::WriteAllText($notPlaylist, "just some text`nwith no channels`n", [Text.UTF8Encoding]::new($false))
        $empty = Join-Path $script:Files 'empty.m3u'
        [IO.File]::WriteAllBytes($empty, [byte[]]@())
        $huge = Join-Path $script:Files 'huge.m3u'
        $stream = [IO.File]::Create($huge); $stream.SetLength(4MB + 1); $stream.Dispose()

        { Add-ChannelForgeSourceSetSource -Kind XMLTV -Path $bad -RepositoryRoot $script:Project } | Should -Throw '*not valid*'
        { Add-ChannelForgeSourceSetSource -Kind M3U -Path $notPlaylist -RepositoryRoot $script:Project } | Should -Throw '*not valid*'
        { Add-ChannelForgeSourceSetSource -Kind M3U -Path $empty -RepositoryRoot $script:Project } | Should -Throw '*empty*'
        { Add-ChannelForgeSourceSetSource -Kind M3U -Path $huge -RepositoryRoot $script:Project } | Should -Throw '*too large*'
        { Add-ChannelForgeSourceSetSource -Kind M3U -Path (Join-Path $script:Files 'missing.m3u') -RepositoryRoot $script:Project } | Should -Throw '*not found*'
        [Convert]::ToBase64String((Get-SetBytes)) | Should -Be ([Convert]::ToBase64String($before))
        (Get-Snapshots) | Should -Be $snapshots
    }

    It 'leaves the old set and snapshots when the set file cannot be saved' {
        $p1 = Add-Source 'alpha' 'M3U'
        Add-Source 'beta' 'M3U' | Out-Null
        $before = Get-SetBytes
        $snapshots = Get-Snapshots
        Mock -ModuleName ChannelForge Write-ChannelForgeSourceEnrollmentAtomicJson { throw 'disk full' }

        { Add-ChannelForgeSourceSetSource -Kind M3U -Path (New-SourceFile 'gamma' 'M3U') -RepositoryRoot $script:Project } | Should -Throw '*disk full*'
        { Remove-ChannelForgeSourceSetSource -SourceId $p1.SourceId -RepositoryRoot $script:Project } | Should -Throw '*disk full*'
        [Convert]::ToBase64String((Get-SetBytes)) | Should -Be ([Convert]::ToBase64String($before))
        (Get-Snapshots) | Should -Be $snapshots
    }

    It 'refuses the ninth playlist through the store limit and saves nothing' {
        1..8 | ForEach-Object { Add-Source "list-$_" 'M3U' | Out-Null }
        $before = Get-SetBytes
        $snapshots = Get-Snapshots

        { Add-Source 'list-9' 'M3U' } | Should -Throw '*too many playlists*'
        (Get-Set).Playlists.Count | Should -Be 8
        [Convert]::ToBase64String((Get-SetBytes)) | Should -Be ([Convert]::ToBase64String($before))
        (Get-Snapshots) | Should -Be $snapshots
    }
}
