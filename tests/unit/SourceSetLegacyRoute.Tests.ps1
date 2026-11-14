BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Executor = Join-Path $script:Repo 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
    Import-Module (Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1') -Force -WarningAction SilentlyContinue
    $script:Utf8 = [Text.UTF8Encoding]::new($false)
    $script:LegacyOrigin = 'legacy-source-enrollment/v1'
    function script:Get-Bytes([string]$Text) { $script:Utf8.GetBytes($Text) }
    function script:Get-M3U([string]$Name) { Get-Bytes "#EXTM3U`n#EXTINF:-1 tvg-id=`"$Name`",$Name`nhttps://example.invalid/$Name`n" }
    function script:Get-Guide([string]$Channel, [string]$Title) {
        Get-Bytes ('<?xml version="1.0"?><tv><channel id="' + $Channel + '"><display-name>' + $Channel + '</display-name></channel><programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="' + $Channel + '"><title>' + $Title + '</title></programme></tv>')
    }
    function script:New-Src([string]$Kind, [string]$Key, [string]$Id, [byte[]]$Bytes, [string]$Origin, [int]$Priority = 1) {
        [pscustomobject]@{
            Kind = $Kind; SourceKind = 'managed-file'; SourceKey = $Key; SourceId = $Id; Label = $Key
            Priority = $Priority; Url = $null; Bytes = $Bytes; Provenance = [ordered]@{ Origin = $Origin }
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
    function script:Get-Candidate($Root, [string]$Name) {
        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $Root
        New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $Root -OutputRoot (Join-Path $Root $Name) -WarningAction SilentlyContinue 3>$null 6>$null
    }
    function script:Get-SingleSource($Root, [string]$Name) {
        New-ChannelForgeCandidateProposal -Root $Root -M3UPath (Join-Path $Root "state/managed-sources/$('1' * 64).m3u") `
            -XMLTVPath (Join-Path $Root "state/managed-sources/$('3' * 64).xml") -OutputRoot (Join-Path $Root $Name) `
            -CandidateContractVersion 'blocker-2-contract/v8' -WarningAction SilentlyContinue 3>$null 6>$null
    }
    function script:Invoke-Refresh([string]$Root) {
        $result = & $script:Executor -Root $Root -EnrollmentPath (Join-Path $Root 'state/source-enrollment.json') -OutputRoot (Join-Path $Root 'reports')
        Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
    }
    function script:Get-CandidateNames([string]$Root) {
        $dir = Join-Path $Root 'reports/refresh-candidates/source-set/candidates'
        if (-not (Test-Path -LiteralPath $dir)) { return @() }
        @(Get-ChildItem -LiteralPath $dir -Directory | Where-Object Name -ne '.staging' | ForEach-Object Name)
    }
    function script:New-SimpleProject([string]$Origin, [int]$Revision = 1) {
        $p = New-Src 'M3U' 'alpha' ('1' * 64) (Get-M3U 'alpha') $Origin
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) (Get-Guide 'alpha' 'A') $Origin
        $b = [pscustomobject]@{ GuideId = ('3' * 64); PlaylistIds = @('1' * 64); Revision = $Revision }
        New-Project @($p) @($g) @($b)
    }
}

Describe 'migrated v1 set keeps its hash on the source set route' {
    It 'a legacy simple set gives the single-source candidate and manifest hashes' {
        $root = New-SimpleProject $script:LegacyOrigin
        $viaSet = Get-Candidate $root 'set'
        $single = Get-SingleSource $root 'single'
        $viaSet.BuildIdentity | Should -Be $single.BuildIdentity
        $viaSet.CandidateManifestHash | Should -Be $single.CandidateManifestHash
    }

    It 'a refresh of a changed legacy simple set builds the single-source candidate' {
        $root = New-SimpleProject $script:LegacyOrigin
        [IO.File]::WriteAllBytes((Join-Path $root "state/managed-sources/$('3' * 64).xml"), (Get-Guide 'alpha' 'B'))
        $null = Invoke-Refresh $root
        $names = @(Get-CandidateNames $root)
        $names.Count | Should -Be 1
        $names[0] | Should -Be (Get-SingleSource $root 'single').CandidateManifestHash
    }

    It 'an enrolled simple set keeps the source-set route' {
        $root = New-SimpleProject 'source-set-v2'
        $viaSet = Get-Candidate $root 'set'
        $viaSet.CandidateManifestHash | Should -Not -Be (Get-SingleSource $root 'single').CandidateManifestHash
    }

    It 'a legacy set with a second playlist moves to the source-set route' {
        $p1 = New-Src 'M3U' 'alpha' ('1' * 64) (Get-M3U 'alpha') $script:LegacyOrigin
        $p2 = New-Src 'M3U' 'beta' ('2' * 64) (Get-M3U 'beta') $script:LegacyOrigin 2
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) (Get-Guide 'alpha' 'A') $script:LegacyOrigin
        $b = [pscustomobject]@{ GuideId = ('3' * 64); PlaylistIds = @('1' * 64) }
        $legacy = Get-Candidate (New-Project @($p1, $p2) @($g) @($b)) 'legacy'
        $p1.Provenance.Origin = $p2.Provenance.Origin = $g.Provenance.Origin = 'source-set-v2'
        $enrolled = Get-Candidate (New-Project @($p1, $p2) @($g) @($b)) 'enrolled'
        $legacy.CandidateManifestHash | Should -Be $enrolled.CandidateManifestHash
    }

    It 'a legacy set with an edited binding moves to the source-set route' {
        $legacyRoot = New-SimpleProject $script:LegacyOrigin 2
        $enrolledRoot = New-SimpleProject 'source-set-v2' 2
        (Get-Candidate $legacyRoot 'legacy').CandidateManifestHash | Should -Be (Get-Candidate $enrolledRoot 'enrolled').CandidateManifestHash
        (Get-Candidate $legacyRoot 'legacy2').CandidateManifestHash | Should -Not -Be (Get-SingleSource $legacyRoot 'single').CandidateManifestHash
    }

    It 'an unchanged legacy set builds no candidate and keeps accepted state' {
        $root = New-SimpleProject $script:LegacyOrigin
        $stateFile = Join-Path $root 'state/source-enrollment.json'
        $before = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).AcceptedWorkflow | ConvertTo-Json
        $null = Invoke-Refresh $root
        @(Get-CandidateNames $root).Count | Should -Be 0
        (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).AcceptedWorkflow | ConvertTo-Json | Should -Be $before
    }
}
