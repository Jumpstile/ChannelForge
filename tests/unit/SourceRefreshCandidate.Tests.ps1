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
    function script:New-Src([string]$Kind, [string]$Key, [string]$Id, [bool]$Remote, [byte[]]$Bytes, [int]$Priority = 1) {
        [pscustomobject]@{
            Kind = $Kind; SourceKind = $(if ($Remote) { 'public-https' } else { 'managed-file' }); SourceKey = $Key; SourceId = $Id; Label = $Key
            Priority = $Priority; Url = $(if ($Remote) { "https://example.invalid/$Key" } else { $null }); Bytes = $Bytes
        }
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
    function script:Save-File([string]$Path, [byte[]]$Bytes) { [IO.File]::WriteAllBytes($Path, $Bytes); $Path }
}

Describe 'refresh candidate for the whole saved set' {
    It 'builds one candidate holding a changed playlist and a changed guide' {
        $oldP = Get-M3U 'old'; $newP = Get-M3U 'new'; $otherP = Get-M3U 'other'
        $oldG = Get-Guide 'old' 'A'; $newG = Get-Guide 'old' 'B'
        $p1 = New-Src 'M3U' 'first' ('1' * 64) $true $oldP
        $p2 = New-Src 'M3U' 'second' ('2' * 64) $true $otherP 2
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $true $oldG
        $root = New-Project @($p1, $p2) @($g)
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -MockWith {
            if ($Url -like '*/first') { $newP } elseif ($Url -like '*/second') { $otherP } else { $newG }
        }

        $report = Invoke-Refresh $root
        @($report.Sources | Where-Object ReasonCode -eq 'CandidateGenerated').Count | Should -Be 2
        $names = @(Get-CandidateNames $root)
        $names.Count | Should -Be 1

        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $root
        $pathP = Save-File (Join-Path $root 'new.m3u') $newP
        $pathG = Save-File (Join-Path $root 'new.xml') $newG
        $both = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd1') `
            -Replacement @([pscustomobject]@{ SourceId = ('1' * 64); Path = $pathP }, [pscustomobject]@{ SourceId = ('3' * 64); Path = $pathG })
        $onlyP = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd2') `
            -ReplacementSourceId ('1' * 64) -ReplacementPath $pathP
        $onlyG = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd3') `
            -ReplacementSourceId ('3' * 64) -ReplacementPath $pathG
        $both.CandidateManifestHash | Should -Be $names[0]
        $onlyP.CandidateManifestHash | Should -Not -Be $names[0]
        $onlyG.CandidateManifestHash | Should -Not -Be $names[0]
    }

    It 'gives a single change the same candidate as the single-pair call' {
        $oldP = Get-M3U 'old'; $newP = Get-M3U 'new'
        $root = New-Project @((New-Src 'M3U' 'first' ('1' * 64) $true $oldP)) @()
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -MockWith { $newP }
        $null = Invoke-Refresh $root
        $names = @(Get-CandidateNames $root)
        $names.Count | Should -Be 1
        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $root
        $direct = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd') `
            -ReplacementSourceId ('1' * 64) -ReplacementPath (Save-File (Join-Path $root 'new.m3u') $newP)
        $direct.CandidateManifestHash | Should -Be $names[0]
    }

    It 'binds a changed local guide per its binding, not to the first playlist' {
        $a = New-Src 'M3U' 'alpha' ('1' * 64) $false (Get-M3U 'alpha')
        $b = New-Src 'M3U' 'beta' ('2' * 64) $false (Get-M3U 'beta') 2
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $false (Get-Guide 'beta' 'A')
        $binding = [pscustomobject]@{ GuideId = ('3' * 64); PlaylistIds = @('2' * 64) }
        $root = New-Project @($a, $b) @($g) @($binding)
        $newGuide = Get-Guide 'beta' 'B'
        [IO.File]::WriteAllBytes((Join-Path $root "state/managed-sources/$('3' * 64).xml"), $newGuide)

        $report = Invoke-Refresh $root
        @($report.Sources | Where-Object ReasonCode -eq 'CandidateGenerated').Count | Should -Be 1
        $names = @(Get-CandidateNames $root)
        $names.Count | Should -Be 1
        $firstPlaylistOnly = New-ChannelForgeCandidateProposal -Root $root -M3UPath (Join-Path $root "state/managed-sources/$('1' * 64).m3u") `
            -XMLTVPath (Join-Path $root "state/managed-sources/$('3' * 64).xml") -OutputRoot (Join-Path $root 'old-route') `
            -CandidateContractVersion 'blocker-2-contract/v8' -WarningAction SilentlyContinue 3>$null 6>$null
        $names[0] | Should -Not -Be $firstPlaylistOnly.CandidateManifestHash
        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $root
        (New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd')).CandidateManifestHash | Should -Be $names[0]
    }

    It 'reports every source, builds no candidate and keeps accepted state when one source is unavailable' {
        $a = New-Src 'M3U' 'alpha' ('1' * 64) $false (Get-M3U 'alpha')
        $b = New-Src 'M3U' 'beta' ('2' * 64) $false (Get-M3U 'beta') 2
        $g = New-Src 'XMLTV' 'guide' ('3' * 64) $true (Get-Guide 'alpha' 'A')
        $root = New-Project @($a, $b) @($g)
        $before = (Get-Content -LiteralPath (Join-Path $root 'state/source-enrollment.json') -Raw | ConvertFrom-Json).AcceptedWorkflow | ConvertTo-Json
        Remove-Item -LiteralPath (Join-Path $root "state/managed-sources/$('2' * 64).m3u")
        $newGuide = Get-Guide 'alpha' 'B'
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -MockWith { $newGuide }

        $report = Invoke-Refresh $root
        @($report.Sources).Count | Should -Be 3
        $byName = @{}
        foreach ($s in $report.Sources) { $byName[[string]$s.Name] = $s }
        $byName['beta'].Classification | Should -Be 'ReviewNeeded'
        $byName['alpha'].Result | Should -Be 'REUSED_VALID_CACHE'
        $byName['guide'].ReasonCode | Should -Be 'CandidateReviewRequired'
        @(Get-CandidateNames $root).Count | Should -Be 0
        $after = (Get-Content -LiteralPath (Join-Path $root 'state/source-enrollment.json') -Raw | ConvertFrom-Json).AcceptedWorkflow | ConvertTo-Json
        $after | Should -Be $before
    }

    It 'keeps the snapshot of a source whose fetch failed and still builds the candidate from the others' {
        $oldP = Get-M3U 'old'; $newP = Get-M3U 'new'; $otherP = Get-M3U 'other'
        $p1 = New-Src 'M3U' 'first' ('1' * 64) $true $oldP
        $p2 = New-Src 'M3U' 'second' ('2' * 64) $true $otherP 2
        $root = New-Project @($p1, $p2) @()
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -MockWith {
            if ($Url -like '*/first') { throw 'simulated outage' } else { $newP }
        }

        $report = Invoke-Refresh $root
        $first = @($report.Sources | Where-Object Name -eq 'first')[0]
        $second = @($report.Sources | Where-Object Name -eq 'second')[0]
        $first.Classification | Should -Be 'Degraded'
        $first.LastKnownGoodPreserved | Should -BeTrue
        $second.ReasonCode | Should -Be 'CandidateGenerated'
        @(Get-CandidateNames $root).Count | Should -Be 1
        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $root
        [IO.File]::ReadAllBytes($saved.M3UPath) | Should -Be $oldP
    }

    It 'builds the candidate for the saved set from an empty replacement list' {
        $a = New-Src 'M3U' 'alpha' ('1' * 64) $false (Get-M3U 'alpha')
        $root = New-Project @($a) @()
        $saved = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $root
        $none = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd1')
        $empty = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd2') -Replacement @()
        $same = New-ChannelForgeEnrolledCandidate -EnrollmentInputs $saved -RepositoryRoot $root -OutputRoot (Join-Path $root 'd3') `
            -ReplacementSourceId ('1' * 64) -ReplacementPath $saved.M3UPath
        $none.CandidateManifestHash | Should -Not -BeNullOrEmpty
        $empty.CandidateManifestHash | Should -Be $none.CandidateManifestHash
        $same.CandidateManifestHash | Should -Be $none.CandidateManifestHash
    }
}
