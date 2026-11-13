BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SchemaPath = Join-Path $repo 'schemas\aew_event_evidence_offline.schema.json'
    $script:FixturePath = Join-Path $repo 'tests\fixtures\aew-event-evidence-offline.json'
}

Describe 'UNAPPROVED AEW card/revision design proposal (not production)' {
    It 'accepts its synthetic example only under the proposal schema' {
        Test-Json -Path $script:FixturePath -SchemaFile $script:SchemaPath -ErrorAction Stop | Should -BeTrue
    }

    It 'keeps unknown local clocks unnormalized and availability uncorroborated' {
        $fixture = Get-Content -LiteralPath $script:FixturePath -Raw | ConvertFrom-Json
        @($fixture.EventRevisions | Where-Object { $_.StartClock.ZoneResolution -eq 'Unknown' -and $null -eq $_.StartClock.NormalizedUtc }).Count | Should -Be 2
        $fixture.Availability.State | Should -Be 'Unknown'
        @($fixture.Availability.EvidenceSourceRecordIds).Count | Should -Be 0
    }
    It 'binds every proposed revision and status to an existing synthetic source record' {
        $fixture = Get-Content -LiteralPath $script:FixturePath -Raw | ConvertFrom-Json
        $sourceIds = @($fixture.SourceRecords | ForEach-Object SourceRecordId)
        foreach ($revision in $fixture.EventRevisions) {
            $sourceIds | Should -Contain $revision.SourceRecordId
            $sourceIds | Should -Contain $revision.EventStatus.EvidenceSourceRecordId
        }
        foreach ($revision in $fixture.CardRevisions) {
            $sourceIds | Should -Contain $revision.SourceRecordId
            foreach ($match in $revision.Matches) {
                $sourceIds | Should -Contain $match.EvidenceSourceRecordId
            }
        }
    }

    It 'rejects UTC normalization when the source timezone is unknown' {
        $fixture = Get-Content -LiteralPath $script:FixturePath -Raw | ConvertFrom-Json
        $fixture.EventRevisions[0].StartClock.NormalizedUtc = '2026-01-02T00:00:00Z'
        $invalid = $fixture | ConvertTo-Json -Depth 20 -Compress
        (Test-Json -Json $invalid -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'rejects offering availability marked unknown when evidence is attached' {
        $fixture = Get-Content -LiteralPath $script:FixturePath -Raw | ConvertFrom-Json
        $fixture.Availability.EvidenceSourceRecordIds = @('aew.fixture.card.2')
        $invalid = $fixture | ConvertTo-Json -Depth 20 -Compress
        (Test-Json -Json $invalid -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }


    It 'requires an explicit evidence assertion for cancellation' {
        $fixture = Get-Content -LiteralPath $script:FixturePath -Raw | ConvertFrom-Json
        $fixture.EventRevisions[1].EventStatus.Assertion = 'NotObserved'
        $invalid = $fixture | ConvertTo-Json -Depth 20 -Compress
        (Test-Json -Json $invalid -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }
}
