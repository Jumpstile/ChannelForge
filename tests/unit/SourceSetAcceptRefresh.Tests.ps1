BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Executor = Join-Path $script:Repo 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
    Import-Module (Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1') -Force -WarningAction SilentlyContinue
    $script:Utf8 = [Text.UTF8Encoding]::new($false)
    function script:Get-Bytes([string]$Text) { $script:Utf8.GetBytes($Text) }
    function script:Get-M3U([string]$Name) { Get-Bytes "#EXTM3U`n#EXTINF:-1 tvg-id=`"$Name`",$Name`nhttps://example.invalid/$Name`n" }
    function script:Get-Guide([string]$Channel, [string]$Title) {
        Get-Bytes ('<?xml version="1.0"?><tv><channel id="' + $Channel + '"><display-name>' + $Channel + '</display-name></channel><programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="' + $Channel + '"><title>' + $Title + '</title></programme></tv>')
    }
    function script:New-Src([string]$Kind, [string]$Key, [string]$Id, [bool]$Remote, [byte[]]$Bytes, [int]$Priority = 1) {
        [pscustomobject]@{
            Kind = $Kind; SourceKind = $(if ($Remote) { 'public-https' } else { 'managed-file' }); SourceKey = $Key; SourceId = $Id; Label = $Key
            Priority = $Priority; Url = $(if ($Remote) { "https://example.invalid/$Key" } else { $null }); Bytes = $Bytes
        }
    }
    function script:New-Project($Playlists, $Guides, $Bindings = @()) {
        $root = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/rules'), (Join-Path $root 'data/lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Repo 'data/rules/aliases.json') -Destination (Join-Path $root 'data/rules/aliases.json')
        Copy-Item -LiteralPath (Join-Path $script:Repo 'data/lineup/numbering_blocks.json') -Destination (Join-Path $root 'data/lineup/numbering_blocks.json')
        & (Get-Module ChannelForge) {
            param($root, $p, $g, $b)
            Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($p) -GuideSources @($g) -Bindings @($b) `
                -AcceptedGenerationManifestHash ('a' * 64) -AcceptedStateHash ('b' * 64) -AcceptedOutputManifestHash ('c' * 64) | Out-Null
        } $root $Playlists $Guides $Bindings
        $root
    }
    function script:Get-Set([string]$Root) { & (Get-Module ChannelForge) { param($r) Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $r } $Root }
    function script:Get-Record([string]$Root, [string]$Id) { @(@((Get-Set $Root).Playlists) + @((Get-Set $Root).Guides) | Where-Object SourceId -eq $Id)[0] }
    function script:Get-Snapshots([string]$Root) { @(Get-ChildItem -LiteralPath (Join-Path $Root 'state/managed-sources') -File | Sort-Object Name | ForEach-Object Name) }
    function script:Save-File([string]$Root, [string]$Name, [byte[]]$Bytes) { $p = Join-Path $Root $Name; [IO.File]::WriteAllBytes($p, $Bytes); $p }
    # Builds the review candidate for the saved set with the given replacements. Returns the arguments the accept step needs.
    function script:New-Candidate([string]$Root, [object[]]$Replacement = @(), [string]$Name = 'cand') {
        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $Root
        $out = Join-Path $Root $Name
        $built = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $Root -OutputRoot $out -Replacement $Replacement
        @{ CandidateDirectory = (Join-Path $out ('candidates/' + $built.CandidateManifestHash)); CandidateManifestHash = $built.CandidateManifestHash; Replacement = $Replacement; RepositoryRoot = $Root }
    }
    function script:Invoke-Refresh([string]$Root) {
        $result = & $script:Executor -Root $Root -EnrollmentPath (Join-Path $Root 'state/source-enrollment.json') -OutputRoot (Join-Path $Root 'reports')
        Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
    }
}

Describe 'accepting a refreshed candidate into the saved source set' {
    It 'keeps a changed remote playlist: new hash and file, old file gone, identity and bindings kept' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $true (Get-M3U 'old')
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $false (Get-Guide 'old' 'A')
        $binding = [pscustomobject]@{ GuideId = ('3' * 64); PlaylistIds = @('1' * 64); Revision = 4 }
        $root = New-Project @($p) @($g) @($binding)
        $before = Get-Record $root ('1' * 64)
        $guideBefore = Get-Record $root ('3' * 64)
        $newPath = Save-File $root 'new.m3u' (Get-M3U 'new')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $newPath })

        $result = Update-ChannelForgeSourceSetSource @args1
        @($result).Count | Should -Be 1

        $after = Get-Record $root ('1' * 64)
        $expectedHash = & (Get-Module ChannelForge) { param($b) Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $b } (Get-M3U 'new')
        $after.ContentHash | Should -Be $expectedHash
        $after.ContentHash | Should -Not -Be $before.ContentHash
        $after.ManagedPath | Should -Be "state/managed-sources/$expectedHash.m3u"
        [IO.File]::ReadAllBytes((Join-Path $root $after.ManagedPath)) | Should -Be (Get-M3U 'new')
        Test-Path -LiteralPath (Join-Path $root $before.ManagedPath) | Should -BeFalse
        $after.SourceId | Should -Be $before.SourceId
        $after.Label | Should -Be $before.Label
        $after.Priority | Should -Be $before.Priority
        $after.Url | Should -Be $before.Url
        @((Get-Set $root).Bindings)[0].Revision | Should -Be 4
        (Get-Record $root ('3' * 64)).ContentHash | Should -Be $guideBefore.ContentHash
        (Get-Snapshots $root).Count | Should -Be 2
    }

    It 'keeps a changed local guide that was replaced in its saved copy' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $false (Get-M3U 'one')
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $false (Get-Guide 'one' 'A')
        $root = New-Project @($p) @($g)
        $before = Get-Record $root ('3' * 64)
        [IO.File]::WriteAllBytes((Join-Path $root $before.ManagedPath), (Get-Guide 'one' 'B'))
        $args1 = New-Candidate $root

        Update-ChannelForgeSourceSetSource @args1 | Out-Null

        $after = Get-Record $root ('3' * 64)
        $after.ContentHash | Should -Not -Be $before.ContentHash
        $after.ManagedPath | Should -Not -Be $before.ManagedPath
        [IO.File]::ReadAllBytes((Join-Path $root $after.ManagedPath)) | Should -Be (Get-Guide 'one' 'B')
        Test-Path -LiteralPath (Join-Path $root $before.ManagedPath) | Should -BeFalse
        $after.SourceId | Should -Be $before.SourceId
    }

    It 'keeps two changed sources at once from one candidate' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $true (Get-M3U 'old')
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $false (Get-Guide 'old' 'A')
        $root = New-Project @($p) @($g)
        $guideBefore = Get-Record $root ('3' * 64)
        [IO.File]::WriteAllBytes((Join-Path $root $guideBefore.ManagedPath), (Get-Guide 'old' 'B'))
        $newPath = Save-File $root 'new.m3u' (Get-M3U 'new')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $newPath })

        @(Update-ChannelForgeSourceSetSource @args1).Count | Should -Be 2

        (Get-Snapshots $root).Count | Should -Be 2
        [IO.File]::ReadAllBytes((Join-Path $root (Get-Record $root ('1' * 64)).ManagedPath)) | Should -Be (Get-M3U 'new')
        [IO.File]::ReadAllBytes((Join-Path $root (Get-Record $root ('3' * 64)).ManagedPath)) | Should -Be (Get-Guide 'old' 'B')
    }

    It 'leaves the old record and old file when saving the set fails' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $true (Get-M3U 'old')
        $root = New-Project @($p) @()
        $setBefore = [IO.File]::ReadAllBytes((Join-Path $root 'state/source-enrollment.json'))
        $snapshotsBefore = Get-Snapshots $root
        $newPath = Save-File $root 'new.m3u' (Get-M3U 'new')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $newPath })
        Mock -ModuleName ChannelForge -CommandName Write-ChannelForgeSourceEnrollmentAtomicJson -MockWith { throw 'disk full' }

        { Update-ChannelForgeSourceSetSource @args1 } | Should -Throw '*disk full*'

        [IO.File]::ReadAllBytes((Join-Path $root 'state/source-enrollment.json')) | Should -Be $setBefore
        Get-Snapshots $root | Should -Be $snapshotsBefore
        [IO.File]::ReadAllBytes((Join-Path $root (Get-Record $root ('1' * 64)).ManagedPath)) | Should -Be (Get-M3U 'old')
    }

    It 'still succeeds with a warning when the old file cannot be deleted after the save' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $true (Get-M3U 'old')
        $root = New-Project @($p) @()
        $newPath = Save-File $root 'new.m3u' (Get-M3U 'new')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $newPath })
        Mock -ModuleName ChannelForge -CommandName Remove-ChannelForgeManagedSourceSnapshot -MockWith { throw 'file in use' }

        $result = Update-ChannelForgeSourceSetSource @args1 -WarningVariable warned -WarningAction SilentlyContinue

        @($result).Count | Should -Be 1
        "$warned" | Should -BeLike '*old saved copy could not be deleted*'
        [IO.File]::ReadAllBytes((Join-Path $root (Get-Record $root ('1' * 64)).ManagedPath)) | Should -Be (Get-M3U 'new')
    }

    It 'refuses bytes that are not the bytes the candidate was built from and changes nothing' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $true (Get-M3U 'old')
        $root = New-Project @($p) @()
        $setBefore = [IO.File]::ReadAllBytes((Join-Path $root 'state/source-enrollment.json'))
        $snapshotsBefore = Get-Snapshots $root
        $good = Save-File $root 'good.m3u' (Get-M3U 'new')
        $other = Save-File $root 'other.m3u' (Get-M3U 'other')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $good })
        $args1.Replacement = @([pscustomobject]@{ SourceId = ('1' * 64); Path = $other })

        { Update-ChannelForgeSourceSetSource @args1 } | Should -Throw '*do not match the candidate*'

        [IO.File]::ReadAllBytes((Join-Path $root 'state/source-enrollment.json')) | Should -Be $setBefore
        Get-Snapshots $root | Should -Be $snapshotsBefore
    }

    It 'refuses when an unrelated source is unhealthy and changes nothing' {
        $a = New-Src 'M3U' 'alpha' ('1' * 64) $true (Get-M3U 'alpha-old')
        $b = New-Src 'M3U' 'beta' ('2' * 64) $false (Get-M3U 'beta') 2
        $root = New-Project @($a, $b) @()
        $newPath = Save-File $root 'new.m3u' (Get-M3U 'alpha-new')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $newPath })
        Remove-Item -LiteralPath (Join-Path $root (Get-Record $root ('2' * 64)).ManagedPath) -Force
        $setBefore = [IO.File]::ReadAllBytes((Join-Path $root 'state/source-enrollment.json'))

        { Update-ChannelForgeSourceSetSource @args1 } | Should -Throw '*SOURCE_ENROLLMENT_UNAVAILABLE*'

        [IO.File]::ReadAllBytes((Join-Path $root 'state/source-enrollment.json')) | Should -Be $setBefore
    }

    It 'shows the sources as unchanged to the next refresh' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $true (Get-M3U 'old')
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $false (Get-Guide 'old' 'A')
        $root = New-Project @($p) @($g)
        [IO.File]::WriteAllBytes((Join-Path $root (Get-Record $root ('3' * 64)).ManagedPath), (Get-Guide 'old' 'B'))
        $newPath = Save-File $root 'new.m3u' (Get-M3U 'new')
        $args1 = New-Candidate $root @([pscustomobject]@{ SourceId = ('1' * 64); Path = $newPath })
        Update-ChannelForgeSourceSetSource @args1 | Out-Null
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -MockWith { Get-M3U 'new' }

        $report = Invoke-Refresh $root

        $report.ReviewNeeded | Should -BeFalse
        @($report.Sources | Where-Object ReasonCode -in @('CandidateGenerated', 'CandidateReviewRequired')).Count | Should -Be 0
    }

    It 'loads and refreshes a set saved with ID-named files, and keeps a hash-named copy through a later edit' {
        $p = New-Src 'M3U' 'first' ('1' * 64) $false (Get-M3U 'one')
        $root = New-Project @($p) @()
        (Get-Snapshots $root) | Should -Be @(('1' * 64) + '.m3u')
        (Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $root).State | Should -Be 'Valid'
        (Invoke-Refresh $root).ReviewNeeded | Should -BeFalse

        [IO.File]::WriteAllBytes((Join-Path $root (Get-Record $root ('1' * 64)).ManagedPath), (Get-M3U 'two'))
        $args1 = New-Candidate $root
        Update-ChannelForgeSourceSetSource @args1 | Out-Null
        $keptPath = (Get-Record $root ('1' * 64)).ManagedPath
        $other = Save-File $root 'extra.m3u' (Get-M3U 'extra')
        Add-ChannelForgeSourceSetSource -Kind M3U -Path $other -Label extra -RepositoryRoot $root | Out-Null

        (Get-Record $root ('1' * 64)).ManagedPath | Should -Be $keptPath
        (Get-Snapshots $root).Count | Should -Be 2
    }
}
