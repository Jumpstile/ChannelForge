BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:V1SchemaPath = Join-Path $repo 'schemas\external_evidence_observation.schema.json'
    $script:V1FixturePath = Join-Path $repo 'tests\fixtures\aew-external-evidence-observation.v1.json'
    Import-Module (Join-Path $repo 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'AEW synthetic fixture through ChannelForgeExternalEvidenceObservation/v1' {
    It 'converts and validates using the accepted shared evidence contract' {
        $inputObject = Get-Content -LiteralPath $script:V1FixturePath -Raw | ConvertFrom-Json -AsHashtable
        $observation = ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $inputObject
        $json = ConvertTo-Json -InputObject $observation -Depth 20 -Compress
        Test-Json -Json $json -SchemaFile $script:V1SchemaPath -ErrorAction Stop | Should -BeTrue
        $observation.ContractVersion | Should -Be 'ChannelForgeExternalEvidenceObservation/v1'
        $observation.ProvisionalSubjectKey | Should -Be 'aew:fixture:event-001'
    }

    It 'preserves the unresolved source clock and explicit status without card-specific fields' {
        $inputObject = Get-Content -LiteralPath $script:V1FixturePath -Raw | ConvertFrom-Json -AsHashtable
        $observation = ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $inputObject
        $start = @($observation.FieldObservations | Where-Object FieldName -eq 'ScheduledStartUtc')[0]
        $status = @($observation.FieldObservations | Where-Object FieldName -eq 'EventStatus')[0]
        $start.NormalizedValue | Should -BeNullOrEmpty
        $start.OriginalValueOrFingerprint | Should -Be '7:00 PM (synthetic; timezone unknown)'
        $start.ReasonCodes | Should -Contain 'SourceTimezoneUnknown'
        $status.NormalizedValue | Should -Be 'Cancelled'
        $status.ReasonCodes | Should -Contain 'ExplicitStatusEvidence'
        @($observation.PSObject.Properties.Name) | Should -Not -Contain 'CardRevisions'
        $observation.SourceDataTimeUtc | Should -BeNullOrEmpty
        $observation.ObservationTimeUtc | Should -Be '2026-01-02T12:00:00Z'
        $observation.FetchTimeUtc | Should -Be '2026-01-02T12:00:00Z'
    }
}
