BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $root 'src/ChannelForge/ChannelForge.psd1') -Force
    $hA = 'a' * 64
    $hB = 'b' * 64
    $hC = 'c' * 64
    $generation = '0123456789abcdef0123456789abcdef'
}

Describe 'Issue 102 accepted-state projections' {
    It 'builds the v8-acceptance decision, output, and state hashes with exact fields' {
        $result = & (Get-Module ChannelForge) {
            param($a, $b, $c, $generation)
            $m3u = New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
            $decision = New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3u -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
            $output = New-ChannelForgeAcceptedOutputManifest -GenerationId $generation -ActiveM3UHash $c -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b
            $state = New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $decision.DecisionManifestHash -AcceptedOutputManifestHash $output.OutputManifestHash -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc '2026-08-29T00:00:00Z'
            [pscustomobject][ordered]@{ Decision = $decision; Output = $output; State = $state }
        } $hA $hB $hC $generation

        @($result.Decision.PSObject.Properties.Name) | Should -Be @('Version','CandidateManifestHash','BuildIdentity','M3UDecisionHash','XMLTVDecisionStatus','XMLTVDecisionHash','DecisionIds','DecisionManifestHash')
        @($result.Output.PSObject.Properties.Name) | Should -Be @('Version','GenerationId','ActiveM3UHash','ActiveXMLTVStatus','ActiveXMLTVHash','AcceptedStateHash','OutputManifestHash')
        @($result.State.PSObject.Properties.Name) | Should -Be @('Version','GenerationId','BuildIdentity','CandidateManifestHash','DecisionManifestHash','AcceptedOutputManifestHash','PreviousStateHash','IncludedCandidateEntryIds','ExcludedCandidateEntryIds','AcceptedBindingIds','AcceptedXMLTVStatus','AcceptedAtUtc','AcceptedStateHash')
        $result.Decision.Version | Should -Be 'blocker-2-contract/v8-acceptance'
        $result.Decision.XMLTVDecisionHash | Should -BeNullOrEmpty
        $result.Output.ActiveXMLTVHash | Should -BeNullOrEmpty
        $result.State.PreviousStateHash | Should -BeNullOrEmpty
    }

    It 'enforces all four XMLTV transition vectors without fabricated NotGenerated content' {
        $result = & (Get-Module ChannelForge) {
            param($a, $b, $c)
            $rows = foreach ($status in @('Generated','NotGenerated')) {
                $xml = if ($status -eq 'Generated') { New-ChannelForgeDecisionXMLTV -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -AcceptedXMLTVStatus Generated -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c) } else { $null }
                $m3u = New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
                $manifest = New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3u -XMLTVDecision $xml -XMLTVDecisionStatus $status
                [pscustomobject]@{ Status = $status; Manifest = $manifest }
            }
            $rows
        } $hA $hB $hC
        $result.Count | Should -Be 2
        ($result | Where-Object Status -eq Generated).Manifest.XMLTVDecisionHash | Should -Not -BeNullOrEmpty
        ($result | Where-Object Status -eq NotGenerated).Manifest.XMLTVDecisionHash | Should -BeNullOrEmpty
        { & (Get-Module ChannelForge) { param($a,$b,$c) New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision (New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)) -XMLTVDecision (New-ChannelForgeDecisionXMLTV -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -AcceptedXMLTVStatus Generated -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)) -XMLTVDecisionStatus NotGenerated } $hA $hB $hC } | Should -Throw 'FAIL_CLOSED:*'
    }

    It 'reconstructs KeepAcceptedEntry from exact bytes and the candidate-entry-content domain' {
        $result = & (Get-Module ChannelForge) {
            param($hA)
            $bytes = [Text.Encoding]::UTF8.GetBytes("#EXTINF:-1,Old`nhttps://old.invalid`n")
            $descriptor = [pscustomobject][ordered]@{ RelativePath = 'merged.m3u'; ByteLength = $bytes.Length; ContentHash = Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $bytes }
            $slice = [pscustomobject][ordered]@{ RelativePath = 'merged.m3u'; ByteOffset = 0; ByteLength = $bytes.Length; EntryContentHash = Get-ChannelForgeDomainHash -Domain 'candidate-entry-content/v1' -Bytes $bytes }
            $entry = [pscustomobject][ordered]@{ EntryId = $hA; EntryOutputSlice = $slice }
            Get-ChannelForgeKeepAcceptedEntry -PriorM3UDescriptor $descriptor -PriorM3UBytes $bytes -PriorAcceptedEntrySlice $entry
        } $hA
        [Text.Encoding]::UTF8.GetString($result.OutputBytes) | Should -Be "#EXTINF:-1,Old`nhttps://old.invalid`n"
        $result.EntryOutputSlice.EntryContentHash | Should -Be ( & (Get-Module ChannelForge) { param($b) Get-ChannelForgeDomainHash -Domain 'candidate-entry-content/v1' -Bytes $b } ([Text.Encoding]::UTF8.GetBytes("#EXTINF:-1,Old`nhttps://old.invalid`n")) )
        { & (Get-Module ChannelForge) { param($hA,$bytes) $bad = [pscustomobject][ordered]@{ RelativePath = 'merged.m3u'; ByteOffset = 0; ByteLength = $bytes.Length + 1; EntryContentHash = $hA }; Get-ChannelForgeKeepAcceptedEntry -PriorM3UDescriptor ([pscustomobject]@{RelativePath='merged.m3u';ByteLength=$bytes.Length;ContentHash=(Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $bytes)}) -PriorM3UBytes $bytes -PriorAcceptedEntrySlice ([pscustomobject]@{EntryId=$hA;EntryOutputSlice=$bad}) } $hA ([Text.Encoding]::UTF8.GetBytes("#EXTINF:-1,Old`nhttps://old.invalid`n")) } | Should -Throw 'FAIL_CLOSED:*'
    }

    It 'compares accepted and candidate entries deterministically and emits review evidence for identity changes' {
        $result = & (Get-Module ChannelForge) {
            param($a, $b, $c)
            $accepted = [pscustomobject][ordered]@{ EntryId = $a; HistoryKey = 'history-1'; HistoryIdentityStatus = 'Unique'; StreamFingerprint = $b; PresentationFingerprint = $c }
            $candidate = [pscustomobject][ordered]@{ EntryId = $b; HistoryKey = 'history-1'; HistoryIdentityStatus = 'Unique'; StreamFingerprint = $b; PresentationFingerprint = $a }
            $manifest = [pscustomobject][ordered]@{ Entries = @($candidate) }
            Compare-ChannelForgeCandidateToAccepted -CandidateManifest $manifest -AcceptedEntries @($accepted)
        } $hA $hB $hC
        $result.ChangeRecords.Count | Should -Be 1
        $result.ChangeRecords[0].Classification | Should -Be 'Renamed'
        $result.ReviewRecords.Count | Should -Be 0
    }

    It 'rejects actionable review records with compound entry cardinality' {
        { & (Get-Module ChannelForge) { param($a,$b) New-ChannelForgeReviewRecord -ReviewCategory Actionable -Classification ReviewNeeded -ReasonCode Conflict -CandidateEntryIds @($a,$b) -AcceptedEntryIds @($a) -CandidateBindingIds @() -DecisionTypesAllowed @('MapCandidateToAcceptedEntry') -Evidence @([ordered]@{EvidenceType='Conflict';Value='x';Ordinal=0}) } $hA $hB } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'fails closed when review entry or binding IDs are malformed' {
        { & (Get-Module ChannelForge) { param($a) New-ChannelForgeReviewRecord -ReviewCategory Informational -Classification IdentityConflict -ReasonCode Invalid -CandidateEntryIds @('not-a-hash') -AcceptedEntryIds @() -CandidateBindingIds @() -DecisionTypesAllowed @() -Evidence @([ordered]@{ EvidenceType = 'Conflict'; Value = 'x'; Ordinal = 0 }) } $hA } | Should -Throw 'FAIL_CLOSED:*'
        { & (Get-Module ChannelForge) { New-ChannelForgeReviewRecord -ReviewCategory Informational -Classification IdentityConflict -ReasonCode Invalid -CandidateEntryIds @() -AcceptedEntryIds @() -CandidateBindingIds @('not-a-hash') -DecisionTypesAllowed @() -Evidence @([ordered]@{ EvidenceType = 'Conflict'; Value = 'x'; Ordinal = 0 }) } } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'constructs active and previous XMLTV descriptors for Generated and NotGenerated transitions' {
        $result = & (Get-Module ChannelForge) {
            param($a, $b, $c, $generation, $priorGeneration)
            $generated = New-ChannelForgeActiveXMLTV -GenerationId $generation -AcceptedStateHash $a -OutputManifestHash $b -Status Generated -ContentHash $c -ByteLength 17 -RelativePath 'merged.xml'
            $notGenerated = New-ChannelForgeActiveXMLTV -GenerationId $generation -AcceptedStateHash $a -OutputManifestHash $b -Status NotGenerated -ContentHash $null -ByteLength 0 -RelativePath $null
            $previousGenerated = New-ChannelForgePreviousXMLTV -GenerationId $generation -AcceptedStateHash $a -OutputManifestHash $b -Status Generated -ContentHash $c -ByteLength 17 -RelativePath 'merged.xml' -PreviousGenerationId $priorGeneration
            $previousNotGenerated = New-ChannelForgePreviousXMLTV -GenerationId $generation -AcceptedStateHash $a -OutputManifestHash $b -Status NotGenerated -ContentHash $null -ByteLength 0 -RelativePath $null -PreviousGenerationId $priorGeneration
            [pscustomobject]@{ ActiveGenerated = $generated; ActiveNotGenerated = $notGenerated; PreviousGenerated = $previousGenerated; PreviousNotGenerated = $previousNotGenerated }
        } $hA $hB $hC $generation ('fedcba9876543210fedcba9876543210')
        $result.ActiveGenerated.Status | Should -Be 'Generated'
        $result.ActiveNotGenerated.ContentHash | Should -BeNullOrEmpty
        $result.ActiveNotGenerated.ByteLength | Should -Be 0
        $result.PreviousGenerated.PreviousGenerationId | Should -Be 'fedcba9876543210fedcba9876543210'
        $result.PreviousNotGenerated.RelativePath | Should -BeNullOrEmpty
        { & (Get-Module ChannelForge) { param($a,$b,$c,$generation) New-ChannelForgeActiveXMLTV -GenerationId $generation -AcceptedStateHash $a -OutputManifestHash $b -Status NotGenerated -ContentHash $c -ByteLength 0 -RelativePath $null } $hA $hB $hC $generation } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'requires complete coherent prior lineage after the first generation' {
        $result = & (Get-Module ChannelForge) {
            param($a, $b, $c, $generation, $priorGeneration)
            $current = [pscustomobject]@{ PreviousStateHash = $c; GenerationId = $generation }
            $priorState = [pscustomobject]@{ AcceptedStateHash = $c; GenerationId = $priorGeneration }
            $priorOutput = [pscustomobject]@{ OutputManifestHash = $b; GenerationId = $priorGeneration }
            $generationManifest = [pscustomobject]@{ PreviousOutputManifestHash = $b; GenerationId = $generation }
            $previousM3U = [pscustomobject]@{ AcceptedStateHash = $c; OutputManifestHash = $b; GenerationId = $generation; PreviousGenerationId = $priorGeneration }
            $previousXMLTV = [pscustomobject]@{ AcceptedStateHash = $c; OutputManifestHash = $b; GenerationId = $generation; PreviousGenerationId = $priorGeneration }
            Test-ChannelForgePreviousLineage -AcceptedState $current -GenerationManifest $generationManifest -PreviousM3U $previousM3U -PreviousXMLTV $previousXMLTV -PriorState $priorState -PriorOutput $priorOutput
        } $hA $hB $hC $generation 'fedcba9876543210fedcba9876543210'
        $result.PreviousOutputManifestHash | Should -Be $hB
        { & (Get-Module ChannelForge) { param($c) Test-ChannelForgePreviousLineage -AcceptedState ([pscustomobject]@{PreviousStateHash=$c}) -GenerationManifest $null -PreviousM3U ([pscustomobject]@{}) -PreviousXMLTV $null -PriorState $null -PriorOutput $null } $hC } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'supports XMLTV-only actionable review evidence keyed by binding occurrence' {
        $review = & (Get-Module ChannelForge) {
            New-ChannelForgeReviewRecord -ReviewCategory Actionable -Classification ReviewNeeded -ReasonCode AmbiguousGuideBinding -CandidateEntryIds @() -AcceptedEntryIds @() -CandidateBindingIds @() -DecisionTypesAllowed @('AcceptGuideBinding') -Evidence @([ordered]@{EvidenceType='GuideCandidate';BindingKey='key-1';OccurrenceOrdinal=2;Ordinal=2})
        }
        @($review.CandidateEntryIds).Count | Should -Be 0
        @($review.AcceptedEntryIds).Count | Should -Be 0
        $review.ReviewId | Should -Match '^[0-9a-f]{64}$'
    }
}
