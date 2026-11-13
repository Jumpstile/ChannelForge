BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ProposalSchemaPath = Join-Path $repo 'tests\fixtures\wrestling-event-card-v2-proposal.schema.json'
    $script:ProposalFixturePath = Join-Path $repo 'tests\fixtures\wrestling-event-card-v2-proposal.json'
    $script:V1SchemaPath = Join-Path $repo 'schemas\external_evidence_observation.schema.json'
    $script:V1FixturePath = Join-Path $repo 'tests\fixtures\aew-external-evidence-observation.v1.json'
    Import-Module (Join-Path $repo 'src\ChannelForge\ChannelForge.psd1') -Force

    $v1Input = Get-Content -LiteralPath $script:V1FixturePath -Raw | ConvertFrom-Json -AsHashtable
    $script:BaseV1Observation = ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $v1Input
    $script:Proposal = Get-Content -LiteralPath $script:ProposalFixturePath -Raw | ConvertFrom-Json -AsHashtable
}

Describe 'UNAPPROVED ChannelForgeExternalEvidenceObservation/v2 wrestling proposal' {
    It 'validates its event base through the existing v1 converter and schema' {
        $v1Json = ConvertTo-Json -InputObject $script:BaseV1Observation -Depth 20 -Compress
        Test-Json -Json $v1Json -SchemaFile $script:V1SchemaPath -ErrorAction Stop | Should -BeTrue
        $script:Proposal.BaseEventObservationReference.ContractVersion | Should -Be 'ChannelForgeExternalEvidenceObservation/v1'
        $script:Proposal.BaseEventObservationReference.ObservationId | Should -Be $script:BaseV1Observation.ObservationId
        $script:Proposal.BaseEventObservationReference.ProvisionalSubjectKey | Should -Be $script:BaseV1Observation.ProvisionalSubjectKey
        $script:Proposal.BaseEventObservationReference.SourceRecordReference | Should -Be $script:BaseV1Observation.SourceRecordReference
        @($script:BaseV1Observation.PSObject.Properties.Name) | Should -Not -Contain 'CardRevisionObservations'
    }

    It 'accepts the synthetic card proposal without widening the v1 schema' {
        Test-Json -Path $script:ProposalFixturePath -SchemaFile $script:ProposalSchemaPath -ErrorAction Stop | Should -BeTrue
        $script:Proposal.ProposalStatus | Should -Be 'UnapprovedArchitectureProposal'
        $script:Proposal.ProposalVersion | Should -Be 'ChannelForgeExternalEvidenceObservation/v2-proposal'
        $mutated = $script:Proposal.Clone()
        $mutated['Availability'] = [ordered]@{ State = 'Unknown'; EvidenceSourceRecordReferences = @() }
        $invalid = ConvertTo-Json -InputObject $mutated -Depth 30 -Compress
        (Test-Json -Json $invalid -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
        $validV1Json = ConvertTo-Json -InputObject $script:BaseV1Observation -Depth 20 -Compress
        $mutatedV1 = ConvertFrom-Json -InputObject $validV1Json -AsHashtable
        $mutatedV1['CardRevisionObservations'] = @()
        $invalidV1Json = ConvertTo-Json -InputObject $mutatedV1 -Depth 20 -Compress
        (Test-Json -Json $invalidV1Json -SchemaFile $script:V1SchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }
    It 'rejects canonical event and match IDs in source-scoped observations' {
        $eventMutation = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $eventMutation.BaseEventObservationReference['CanonicalEventId'] = 'canonical-event-not-source-evidence'
        $invalidEvent = ConvertTo-Json -InputObject $eventMutation -Depth 30 -Compress
        (Test-Json -Json $invalidEvent -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse

        $matchMutation = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $matchMutation.CardRevisionObservations[1].MatchObservations[0]['CanonicalMatchId'] = 'canonical-match-not-source-evidence'
        $invalidMatch = ConvertTo-Json -InputObject $matchMutation -Depth 30 -Compress
        (Test-Json -Json $invalidMatch -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }


    It 'requires direct evidence for stable source match references' {
        $unsupportedReference = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $unsupportedReference.CardRevisionObservations[1].MatchObservations[0].SourceMatchReferenceEvidence = $null
        $invalid = ConvertTo-Json -InputObject $unsupportedReference -Depth 30 -Compress
        (Test-Json -Json $invalid -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse

        $uncorrelated = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $uncorrelated.CardRevisionObservations[1].MatchObservations[0].SourceMatchReference = $null
        $uncorrelated.CardRevisionObservations[1].MatchObservations[0].SourceMatchReferenceEvidence = $null
        $valid = ConvertTo-Json -InputObject $uncorrelated -Depth 30 -Compress
        (Test-Json -Json $valid -SchemaFile $script:ProposalSchemaPath -ErrorAction Stop) | Should -BeTrue
    }

    It 'keeps event and bout status, revisions, and disclosure evidence distinct' {
        $eventStatus = @($script:BaseV1Observation.FieldObservations | Where-Object FieldName -eq 'EventStatus')[0]
        $eventStatus.NormalizedValue | Should -Be 'Cancelled'
        $script:Proposal.CardRevisionObservations[0].CardDisclosure.State | Should -Be 'ExplicitlyUnannounced'
        @($script:Proposal.CardRevisionObservations[0].MatchObservations).Count | Should -Be 0
        $first = $script:Proposal.CardRevisionObservations[1]
        $updated = $script:Proposal.CardRevisionObservations[2]
        $first.CardDisclosure.State | Should -Be 'ItemsObserved'
        $first.Completeness.Value | Should -Be 'Unknown'
        $first.MatchObservations.Count | Should -Be 2
        @($updated.MatchObservations | Where-Object SourceMatchReference -eq 'aew.fixture.match-2').Count | Should -Be 0
        $cancelled = @($script:Proposal.CardRevisionObservations[3].MatchObservations | Where-Object SourceMatchReference -eq 'aew.fixture.match-2')[0]
        $cancelled.Status.Value | Should -Be 'ExplicitlyCancelled'
        $cancelled.Status.Assertion | Should -Be 'ExplicitSourceStatement'
        $cancelled.Status.Evidence.SourceRecordReference | Should -Be 'aew.fixture.card-revision-3'
        $updated.MatchObservations[0].Participants[1].SourceParticipantReference | Should -Be 'aew.fixture.participant-c'
        $updated.MatchObservations[0].Stipulations[0].Text | Should -Be 'No Disqualification (synthetic)'
    }

    It 'requires observed card items to match explicit disclosure state' {
        $itemsWithoutEvidence = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $itemsWithoutEvidence.CardRevisionObservations[0].CardDisclosure.State = 'ItemsObserved'
        $itemsWithoutEvidence.CardRevisionObservations[0].CardDisclosure.Assertion = 'ObservedContent'
        $invalidItems = ConvertTo-Json -InputObject $itemsWithoutEvidence -Depth 30 -Compress
        (Test-Json -Json $invalidItems -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse

        $itemsWhenUnannounced = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $itemsWhenUnannounced.CardRevisionObservations[0].MatchObservations = @($script:Proposal.CardRevisionObservations[1].MatchObservations[0])
        $invalidUnannounced = ConvertTo-Json -InputObject $itemsWhenUnannounced -Depth 30 -Compress
        (Test-Json -Json $invalidUnannounced -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'requires evidence for complete cards, explicit cancellation, and normalized clocks' {
        $completeWithoutEvidence = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $completeWithoutEvidence.CardRevisionObservations[1].Completeness.Value = 'ExplicitlyComplete'
        $invalidCompleteness = ConvertTo-Json -InputObject $completeWithoutEvidence -Depth 30 -Compress
        (Test-Json -Json $invalidCompleteness -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse

        $implicitCancellation = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $implicitCancellation.CardRevisionObservations[3].MatchObservations[1].Status.Assertion = 'ObservedContent'
        $invalidCancellation = ConvertTo-Json -InputObject $implicitCancellation -Depth 30 -Compress
        (Test-Json -Json $invalidCancellation -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse

        $unknownZoneWithUtc = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $unknownZoneWithUtc.SourceClockObservations[0].NormalizedUtc = '2026-01-02T19:00:00Z'
        $invalidClock = ConvertTo-Json -InputObject $unknownZoneWithUtc -Depth 30 -Compress
        (Test-Json -Json $invalidClock -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'preserves separate unresolved event and broadcast clocks' {
        $clocks = @($script:Proposal.SourceClockObservations)
        @($clocks | ForEach-Object ClockRole) | Should -Be @('EventLocalStart', 'BroadcastStart')
        $clocks | ForEach-Object {
            $_.ZoneResolution | Should -Be 'Unknown'
            $_.TimeZoneId | Should -BeNullOrEmpty
            $_.NormalizedUtc | Should -BeNullOrEmpty
        }
    }

    It 'requires a displayed explicit offset before normalizing a source clock' {
        $missingOffset = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $missingOffset.SourceClockObservations[0].ZoneResolution = 'ExplicitOffset'
        $missingOffset.SourceClockObservations[0].RawDisplayValue = $null
        $missingOffset.SourceClockObservations[0].NormalizedUtc = '2026-01-03T00:00:00Z'
        $invalid = ConvertTo-Json -InputObject $missingOffset -Depth 30 -Compress
        (Test-Json -Json $invalid -SchemaFile $script:ProposalSchemaPath -ErrorAction SilentlyContinue) | Should -BeFalse

        $explicitOffset = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:Proposal -Depth 30 -Compress) -AsHashtable
        $explicitOffset.SourceClockObservations[0].ZoneResolution = 'ExplicitOffset'
        $explicitOffset.SourceClockObservations[0].RawDisplayValue = '2026-01-02T19:00:00-05:00'
        $explicitOffset.SourceClockObservations[0].NormalizedUtc = '2026-01-03T00:00:00Z'
        $valid = ConvertTo-Json -InputObject $explicitOffset -Depth 30 -Compress
        (Test-Json -Json $valid -SchemaFile $script:ProposalSchemaPath -ErrorAction Stop) | Should -BeTrue
    }

    It 'resolves every proposed evidence reference to a synthetic source record' {
        $sources = @($script:Proposal.SourceRecords | ForEach-Object SourceRecordReference)
        $sources | Should -Contain $script:Proposal.BaseEventObservationReference.SourceRecordReference
        foreach ($clock in $script:Proposal.SourceClockObservations) {
            $sources | Should -Contain $clock.Evidence.SourceRecordReference
        }
        foreach ($revision in $script:Proposal.CardRevisionObservations) {
            $sources | Should -Contain $revision.SourceRecordReference
            $sources | Should -Contain $revision.CardDisclosure.EvidenceSourceRecordReference
            if ($null -ne $revision.Completeness.EvidenceSourceRecordReference) {
                $sources | Should -Contain $revision.Completeness.EvidenceSourceRecordReference
            }
            foreach ($match in $revision.MatchObservations) {
                $sources | Should -Contain $match.Status.Evidence.SourceRecordReference
                if ($null -ne $match.SourceMatchReference) {
                    $sources | Should -Contain $match.SourceMatchReferenceEvidence.SourceRecordReference
                    $match.SourceMatchReferenceEvidence.SourceRecordReference | Should -Be $match.Status.Evidence.SourceRecordReference
                }
                else {
                    $match.SourceMatchReferenceEvidence | Should -BeNullOrEmpty
                }
                foreach ($participant in $match.Participants) {
                    $sources | Should -Contain $participant.Evidence.SourceRecordReference
                }
                foreach ($stipulation in $match.Stipulations) {
                    $sources | Should -Contain $stipulation.Evidence.SourceRecordReference
                }
                if ($null -ne $match.CardPosition) {
                    $sources | Should -Contain $match.CardPosition.Evidence.SourceRecordReference
                }
            }
        }
    }
}
