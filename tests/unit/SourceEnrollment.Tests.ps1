BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
}

Describe 'durable source enrollment' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path $script:Project | Out-Null
        $script:M3U = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n")
        $script:XMLTV = [Text.Encoding]::UTF8.GetBytes('<tv><channel id="one" /></tv>')
        function Save-Enrollment {
            param([byte[]]$M3UBytes = $script:M3U, [byte[]]$XMLTVBytes = $null)
            & (Get-Module ChannelForge) {
                param($Root, $Playlist, $Guide)
                Write-ChannelForgeSourceEnrollment -RepositoryRoot $Root -M3UBytes $Playlist -XMLTVBytes $Guide | Out-Null
            } $script:Project $M3UBytes $XMLTVBytes
        }
    }

    It 'persists an M3U-only enrollment across a fresh module import' {
        Save-Enrollment
        Remove-Module ChannelForge -Force
        Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $input = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project
        Test-Json -Path (Join-Path $script:Project 'state/source-enrollment.json') -SchemaFile (Join-Path $script:Root 'schemas/source-enrollment.schema.json') | Should -BeTrue

        $status.EnrollmentStatus | Should -Be 'saved'
        $status.M3UStatus | Should -Be 'ready'
        $status.XMLTVStatus | Should -Be 'no-guide'
        Test-Path -LiteralPath $input.M3UPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Project 'state/source-enrollment.json') -PathType Leaf | Should -BeTrue
    }

    It 'persists an optional XMLTV guide without exposing source bytes in status' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $raw = $status | ConvertTo-Json -Depth 8

        $status.XMLTVStatus | Should -Be 'ready'
        $raw | Should -Not -Match '#EXTM3U|<tv>|example.invalid'
        $raw | Should -Not -Match 'state[\\/]managed-sources|ContentHash|EnrollmentId'
    }

    It 'fails closed for enrollment record tampering' {
        Save-Enrollment
        $path = Join-Path $script:Project 'state/source-enrollment.json'
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $record.Status = 'Tampered'
        [IO.File]::WriteAllText($path, ($record | ConvertTo-Json -Depth 8 -Compress), [Text.UTF8Encoding]::new($false))

        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'needs-attention'
        $status.CanRefresh | Should -BeFalse
    }

    It 'detects changed managed bytes before any candidate refresh' {
        Save-Enrollment
        $input = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project
        [IO.File]::WriteAllBytes($input.M3UPath, [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=two,Two`nhttps://example.invalid/two`n"))

        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'changes-found'
        $status.M3UStatus | Should -Be 'changes-found'
        $status.CanRefresh | Should -BeTrue
    }

    It 'reports missing managed bytes as source unavailable' {
        Save-Enrollment
        $input = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project
        Remove-Item -LiteralPath $input.M3UPath -Force

        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'source-unavailable'
        $status.CanRefresh | Should -BeFalse
    }

    It 'rejects traversal and reparse-point managed paths' {
        Save-Enrollment
        $module = Get-Module ChannelForge
        { & $module { param($path,$root) Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $root } (Join-Path $script:Project 'state/../outside') (Join-Path $script:Project 'state') } | Should -Throw '*FAIL_CLOSED*'

        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Force -Path $outside | Out-Null
        $link = Join-Path $script:Project 'state/link'
        $symlinkCreated = $false
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
            $symlinkCreated = $true
        }
        catch {
            $symlinkCreated = $false
        }
        if ($symlinkCreated) {
            { & $module { param($path,$root) Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $root } (Join-Path $link 'file.m3u') (Join-Path $script:Project 'state') } | Should -Throw '*FAIL_CLOSED*'
        }
    }

    It 'leaves no enrollment temporary files after atomic persistence' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        @(Get-ChildItem -LiteralPath (Join-Path $script:Project 'state') -Recurse -Force -File | Where-Object Name -like '*.tmp').Count | Should -Be 0
    }
    It 'persists multiple playlists, multiple guides, and explicit ALL bindings' {
        $playlists = @(
            [pscustomobject]@{ Kind = 'M3U'; SourceKind = 'managed-file'; SourceKey = 'playlist-a'; Label = 'A'; Bytes = $script:M3U; Priority = 10 },
            [pscustomobject]@{ Kind = 'M3U'; SourceKind = 'managed-file'; SourceKey = 'playlist-b'; Label = 'B'; Bytes = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=two,Two`nhttps://example.invalid/two`n"); Priority = 20 }
        )
        $guides = @(
            [pscustomobject]@{ Kind = 'XMLTV'; SourceKind = 'public-https'; SourceKey = 'guide-a'; Label = 'Guide A'; Url = 'https://example.invalid/a.xml' },
            [pscustomobject]@{ Kind = 'XMLTV'; SourceKind = 'managed-file'; SourceKey = 'guide-b'; Label = 'Guide B'; Bytes = $script:XMLTV }
        )
        $saved = & (Get-Module ChannelForge) {
            param($root,$p,$g)
            Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p -GuideSources $g
        } $script:Project $playlists $guides
        # Replace the intentionally invalid placeholder binding with a valid ALL binding through the private authority.
        $guideId = @($saved.Guides | Where-Object Label -eq 'Guide A').SourceId
        $saved = & (Get-Module ChannelForge) {
            param($root,$p,$g,$id)
            Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p -GuideSources $g -Bindings @([pscustomobject]@{ GuideId = $id; AppliesToAll = $true; Revision = 3 })
        } $script:Project $playlists $guides $guideId
        $saved.Playlists.Count | Should -Be 2
        $saved.Guides.Count | Should -Be 2
        @($saved.Bindings | Where-Object AppliesToAll).Count | Should -Be 1
        @($saved.Bindings | Where-Object AppliesToAll).PlaylistIds.Count | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $script:Project 'state/source-enrollment.json') -Raw | ConvertFrom-Json).Version | Should -Be 'source-enrollment/v2'
    }

    It 'auto-binds exactly one playlist to exactly one guide' {
        $playlist = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='single-playlist'; Url='https://example.invalid/single.m3u' }
        $guide = [pscustomobject]@{ Kind='XMLTV'; SourceKind='public-https'; SourceKey='single-guide'; Url='https://example.invalid/single.xml' }
        $saved = & (Get-Module ChannelForge) { param($root,$p,$g) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources @($g) } $script:Project $playlist $guide
        $saved.Bindings.Count | Should -Be 1
        $saved.Bindings[0].AppliesToAll | Should -BeFalse
        $saved.Bindings[0].PlaylistIds.Count | Should -Be 1
        $saved.Bindings[0].PlaylistIds[0] | Should -Be $saved.Playlists[0].SourceId
    }

    It 'auto-binds one playlist to one or many guides, but leaves multi-playlist guides unbound' {
        $playlist = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='playlist-one'; Url='https://example.invalid/one.m3u'; Label='One' }
        $guideA = [pscustomobject]@{ Kind='XMLTV'; SourceKind='public-https'; SourceKey='guide-a'; Url='https://example.invalid/a.xml'; Label='A' }
        $guideB = [pscustomobject]@{ Kind='XMLTV'; SourceKind='public-https'; SourceKey='guide-b'; Url='https://example.invalid/b.xml'; Label='B' }
        $single = & (Get-Module ChannelForge) { param($root,$p,$g) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources $g } $script:Project $playlist @($guideA,$guideB)
        $single.Bindings.Count | Should -Be 2
        @($single.Bindings | Where-Object { $_.PlaylistIds.Count -eq 1 }).Count | Should -Be 2
        $playlistTwo = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='playlist-two'; Url='https://example.invalid/two.m3u'; Label='Two' }
        $multi = & (Get-Module ChannelForge) { param($root,$p,$g) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p -GuideSources @($g) } $script:Project @($playlist,$playlistTwo) $guideA
        @($multi.Bindings).Count | Should -Be 0
        $multi.Guides.Count | Should -Be 1
    }

    It 'accepts explicit single-playlist and ALL bindings only' {
        $p1 = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='p1'; Url='https://example.invalid/p1.m3u' }
        $p2 = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='p2'; Url='https://example.invalid/p2.m3u' }
        $g = [pscustomobject]@{ Kind='XMLTV'; SourceKind='public-https'; SourceKey='g'; Url='https://example.invalid/g.xml' }
        $one = & (Get-Module ChannelForge) { param($root,$p,$g) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p -GuideSources @($g) } $script:Project @($p1,$p2) $g
        $guideId = [string]$one.Guides[0].SourceId; $playlistId = [string]$one.Playlists[0].SourceId
        $selected = & (Get-Module ChannelForge) { param($root,$p,$g,$gid,$selectedPlaylistId) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p -GuideSources @($g) -Bindings @([pscustomobject]@{ GuideId=$gid; PlaylistIds=@($selectedPlaylistId); AppliesToAll=$false }) } $script:Project @($p1,$p2) $g $guideId $playlistId
        $selected.Bindings[0].PlaylistIds | Should -Be $playlistId
        $all = & (Get-Module ChannelForge) { param($root,$p,$g,$gid) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p -GuideSources @($g) -Bindings @([pscustomobject]@{ GuideId=$gid; AppliesToAll=$true }) } $script:Project @($p1,$p2) $g $guideId
        $all.Bindings[0].AppliesToAll | Should -BeTrue
        $all.Bindings[0].PlaylistIds.Count | Should -Be 0
    }

    It 'rejects duplicate source and effective binding identities on write' {
        $duplicate = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='same'; Url='https://example.invalid/a.m3u' }
        { & (Get-Module ChannelForge) { param($root,$p) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p } $script:Project @($duplicate,$duplicate) } | Should -Throw '*duplicate source identity*'
        $p = [pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='p'; Url='https://example.invalid/p.m3u' }
        $g = [pscustomobject]@{ Kind='XMLTV'; SourceKind='public-https'; SourceKey='g'; Url='https://example.invalid/g.xml' }
        $base = & (Get-Module ChannelForge) { param($root,$p,$g) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources @($g) } $script:Project $p $g
        $gid = [string]$base.Guides[0].SourceId; $bindingPlaylistId = [string]$base.Playlists[0].SourceId
        { & (Get-Module ChannelForge) { param($root,$p,$g,$gid,$bindingPlaylistId) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources @($g) -Bindings @([pscustomobject]@{GuideId=$gid;PlaylistIds=@($bindingPlaylistId)},[pscustomobject]@{GuideId=$gid;PlaylistIds=@($bindingPlaylistId);Revision=2}) } $script:Project $p $g $gid $bindingPlaylistId } | Should -Throw '*duplicate effective*'
        $guideDuplicate = [pscustomobject]@{ Kind='XMLTV'; SourceKind='public-https'; SourceKey='same-guide'; Url='https://example.invalid/g.xml' }
        { & (Get-Module ChannelForge) { param($root,$p,$g) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources @($g,$g) } $script:Project $p $guideDuplicate } | Should -Throw '*duplicate source identity*'
        $singleBinding = [pscustomobject]@{ GuideId=$gid; PlaylistIds=@($bindingPlaylistId); AppliesToAll=$false }
        { & (Get-Module ChannelForge) { param($root,$p,$g,$b) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources @($g) -Bindings @($b,$b) } $script:Project $p $g $singleBinding } | Should -Throw '*duplicate*'
    }

    It 'fails closed when persisted v2 identity or binding references are tampered' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        $path = Join-Path $script:Project 'state/source-enrollment.json'
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $record.Playlists = @($record.Playlists) + @($record.Playlists[0])
        & (Get-Module ChannelForge) {
            param($path,$record)
            $record.EnrollmentHash = $null
            $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
            [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
        } $path $record
        (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'

        Save-Enrollment -XMLTVBytes $script:XMLTV
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $record.Bindings[0].GuideId = ('f' * 64)
        & (Get-Module ChannelForge) {
            param($path,$record)
            $record.EnrollmentHash = $null
            $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
            [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
        } $path $record
        (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'
        Save-Enrollment -XMLTVBytes $script:XMLTV
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $record.Guides = @($record.Guides) + @($record.Guides[0])
        & (Get-Module ChannelForge) {
            param($path,$record)
            $record.EnrollmentHash = $null
            $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
            [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
        } $path $record
        (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'

        Save-Enrollment -XMLTVBytes $script:XMLTV
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $record.Guides[0].SourceId = $record.Playlists[0].SourceId
        & (Get-Module ChannelForge) {
            param($path,$record)
            $record.EnrollmentHash = $null
            $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
            [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
        } $path $record
        (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'

        Save-Enrollment -XMLTVBytes $script:XMLTV
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $record.Bindings = @($record.Bindings) + @($record.Bindings[0])
        & (Get-Module ChannelForge) {
            param($path,$record)
            $record.EnrollmentHash = $null
            $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
            [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
        } $path $record
        (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'

        Save-Enrollment -XMLTVBytes $script:XMLTV
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $record.Bindings[0].PlaylistIds = @('f' * 64)
        & (Get-Module ChannelForge) {
            param($path,$record)
            $record.EnrollmentHash = $null
            $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
            [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
        } $path $record
        (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'
        foreach ($invalid in @(
            @{ All = $true; PlaylistIds = @([string]$record.Playlists[0].SourceId) },
            @{ All = $false; PlaylistIds = @() }
        )) {
            Save-Enrollment -XMLTVBytes $script:XMLTV
            $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
            $record.Bindings[0].AppliesToAll = $invalid.All
            $record.Bindings[0].PlaylistIds = $invalid.PlaylistIds
            & (Get-Module ChannelForge) {
                param($path,$record)
                $record.EnrollmentHash = $null
                $record.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $record
                [IO.File]::WriteAllText($path,(ConvertTo-ChannelForgeCanonicalJson -InputObject $record),[Text.UTF8Encoding]::new($false))
            } $path $record
            (Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project).EnrollmentStatus | Should -Be 'needs-attention'
        }
    }

    It 'reads legacy v1 enrollment deterministically without creating a second authority' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        $path = Join-Path $script:Project 'state/source-enrollment.json'
        $current = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
        $legacy = [ordered]@{
            Version = 'source-enrollment/v1'
            EnrollmentId = $current.EnrollmentId
            Status = 'Valid'
            GuideMode = 'XMLTV'
            M3U = [ordered]@{ SourceId = $current.Playlists[0].SourceId; Kind = 'M3U'; Format = 'm3u'; ManagedPath = $current.Playlists[0].ManagedPath; ContentHash = $current.Playlists[0].ContentHash; ByteLength = $current.Playlists[0].ByteLength }
            XMLTV = [ordered]@{ SourceId = $current.Guides[0].SourceId; Kind = 'XMLTV'; Format = 'xmltv'; ManagedPath = $current.Guides[0].ManagedPath; ContentHash = $current.Guides[0].ContentHash; ByteLength = $current.Guides[0].ByteLength }
            AcceptedWorkflow = $current.AcceptedWorkflow
            RefreshPolicy = $current.RefreshPolicy
            LastRefreshStatus = 'saved'
            CreatedAtUtc = $current.CreatedAtUtc
            UpdatedAtUtc = $current.UpdatedAtUtc
        }
        & (Get-Module ChannelForge) {
            param($path,$record)
            $projection = [ordered]@{}; foreach ($property in @($record.PSObject.Properties)) { if ($property.Name -cne 'EnrollmentHash') { $projection[$property.Name] = $property.Value } }
            Add-Member -InputObject $record -MemberType NoteProperty -Name EnrollmentHash -Value $null
            $record.EnrollmentHash = Get-ChannelForgeDomainHash -Domain 'source-enrollment/v1' -InputObject $projection
            [IO.File]::WriteAllText($path, (ConvertTo-ChannelForgeCanonicalJson -InputObject $record), [Text.UTF8Encoding]::new($false))
        } $path ([pscustomobject]$legacy)
        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'saved'
        (Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project).M3UPath | Should -Not -BeNullOrEmpty
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).Version | Should -Be 'source-enrollment/v1'
    }

    It 'keeps source identity independent of enumeration order and rejects tokenized URLs' {
        $a = [pscustomobject]@{ Kind = 'M3U'; SourceKind = 'public-https'; SourceKey = 'a'; Label = 'A'; Url = 'https://example.invalid/a.m3u' }
        $b = [pscustomobject]@{ Kind = 'M3U'; SourceKind = 'public-https'; SourceKey = 'b'; Label = 'B'; Url = 'https://example.invalid/b.m3u' }
        $first = & (Get-Module ChannelForge) { param($root,$p) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p } $script:Project @($a,$b)
        $second = & (Get-Module ChannelForge) { param($root,$p) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources $p } $script:Project @($b,$a)
        (($first.Playlists.SourceId | Sort-Object) -join ',') | Should -Be (($second.Playlists.SourceId | Sort-Object) -join ',')
        { & (Get-Module ChannelForge) { param($root) Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @([pscustomobject]@{ Kind='M3U'; SourceKind='public-https'; SourceKey='bad'; Url='https://example.invalid/feed.m3u?token=secret' }) } $script:Project } | Should -Throw '*non-tokenized*'
    }

    It 'keeps safe status free of paths and URLs while accepted workflow remains unchanged' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $raw = $status | ConvertTo-Json -Depth 8
        $raw | Should -Not -Match 'managed-sources|example.invalid|AcceptedStateHash'
        $record = Get-Content -LiteralPath (Join-Path $script:Project 'state/source-enrollment.json') -Raw | ConvertFrom-Json
        $record.AcceptedWorkflow.AcceptedStateHash | Should -BeNullOrEmpty
    }
}
