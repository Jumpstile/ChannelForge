BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-ugwire-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    $script:Tv = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests\fixtures\event-sources\tvmaze-schedule.json') -Raw
    $script:Show = [pscustomobject]@{ showId = 5001; name = 'Fixture Show'; kind = 'episode'; trustTimes = $true }
    # Fixture data: an invented guide, not a real listing.
    function New-Guide {
        param([string]$Name, [string]$Start)
        $path = Join-Path $script:Dir $Name
        $xml = '<?xml version="1.0" encoding="UTF-8"?><tv><channel id="chan.one"/><programme start="' + $Start + '" stop="20301231000000 +0000" channel="chan.one"><title>Zeta Rovers vs Omega Hawks</title><desc>Secret text</desc></programme></tv>'
        [IO.File]::WriteAllText($path, $xml, [Text.UTF8Encoding]::new($false))
        $path
    }
    function Invoke-WithGuide {
        param([string]$GuidePath, [string]$EvidencePath)
        $reply = $script:Tv; $fetch = { param($Url) $reply }.GetNewClosure()
        InModuleScope ChannelForge -Parameters @{ S = $script:Show; G = $GuidePath; E = $EvidencePath; F = $fetch } {
            $arguments = @{ Show = $S; UserGuidePath = $G; Fetch = $F; FetchedAt = '2026-11-21T10:00:00Z' }
            if ($E) { $arguments.EvidencePath = $E }
            Get-ChannelForgeEventSourceEvidence @arguments
        }
    }
    function Get-Agreement {
        param([object[]]$GuideRecords)
        InModuleScope ChannelForge -Parameters @{ R = $GuideRecords } {
            $provider = [pscustomobject]@{ Key = 'provider1'; DisplayName = 'Provider 1'; Programmes = @([pscustomobject]@{ Title = 'Zeta Rovers vs Omega Hawks'; Start = [datetimeoffset]'2026-11-15T18:00:00Z'; Stop = $null }) }
            $all = @($provider) + @(ConvertTo-ChannelForgeUserGuideChannel -Evidence @($R))
            Get-ChannelForgeEventTimeAgreement -Candidate @($all | ForEach-Object { [pscustomobject]@{ Key = $_.Key } }) -Channel $all
        }
    }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'User guide wired into event source evidence' {
    It 'adds user-guide records to the source run, agreeing with the provider time, without the description' {
        $r = Invoke-WithGuide (New-Guide 'a.xml' '20261115130000 -0500')
        $r.Status | Should -Be 'Ok'
        $guide = @($r.Records | Where-Object Source -eq 'user-guide')
        $guide.Count | Should -Be 1
        $r.Records.Count | Should -BeGreaterThan 1
        ($guide | ConvertTo-Json -Depth 3) | Should -Not -BeLike '*Secret*'
        (Get-Agreement $guide).Events[0].Status | Should -Be 'agreed'
    }
    It 'shows a disagreeing guide time as a disagreement' {
        $r = Invoke-WithGuide (New-Guide 'b.xml' '20261115181000 +0000')
        (Get-Agreement @($r.Records | Where-Object Source -eq 'user-guide')).Events[0].Status | Should -Not -Be 'agreed'
    }
    It 'saves the guide facts next to the other source in the evidence file' {
        $evidence = Join-Path $script:Dir 'ev\schedule-evidence.json'
        $r = Invoke-WithGuide (New-Guide 'c.xml' '20261115130000 -0500') $evidence
        $r.Status | Should -Be 'Ok'
        $saved = @((Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json -DateKind String).records)
        ($saved | Where-Object source -eq 'user-guide').name | Should -Be 'Zeta Rovers vs Omega Hawks'
        ($saved | Where-Object source -eq 'user-guide').startUtc | Should -Be '2026-11-15T18:00:00Z'
        @($saved | Where-Object source -eq 'tvmaze.com').Count | Should -BeGreaterThan 0
    }
    It 'skips a missing guide with a plain reason; the source still works' {
        $r = Invoke-WithGuide (Join-Path $script:Dir 'gone.xml')
        $r.Status | Should -Be 'Ok'
        $r.SkippedSources | Should -Be @('user-guide: the file was not found.')
        @($r.Records | Where-Object Source -eq 'user-guide').Count | Should -Be 0
        $r.Records.Count | Should -BeGreaterThan 0
    }
    It 'skips a damaged guide and does not throw' {
        $bad = Join-Path $script:Dir 'bad.xml'
        [IO.File]::WriteAllText($bad, '<tv><programme', [Text.UTF8Encoding]::new($false))
        $r = Invoke-WithGuide $bad
        $r.Status | Should -Be 'Ok'
        $r.SkippedSources.Count | Should -Be 1
    }
}
