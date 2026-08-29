BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $root 'src/ChannelForge/ChannelForge.psd1') -Force
    $hA = 'a' * 64
    $hB = 'b' * 64
    $hC = 'c' * 64
    $generation = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
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
        } $hA $hB $hC $generation ('fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210')
        $result.ActiveGenerated.Status | Should -Be 'Generated'
        $result.ActiveNotGenerated.ContentHash | Should -BeNullOrEmpty
        $result.ActiveNotGenerated.ByteLength | Should -Be 0
        $result.PreviousGenerated.PreviousGenerationId | Should -Be 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
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
        } $hA $hB $hC $generation 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
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
    It 'requires 64 lowercase hexadecimal generation IDs' {
        $valid = & (Get-Module ChannelForge) { param($a,$b,$c,$generation) New-ChannelForgeAcceptedOutputManifest -GenerationId $generation -ActiveM3UHash $a -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b } $hA $hB $hC $generation
        $valid.GenerationId | Should -Be $generation
        foreach ($bad in @(
            ('0' * 63),
            ('0' * 65),
            ('A' * 64),
            ('g' * 64)
        )) {
            { & (Get-Module ChannelForge) { param($a,$b,$value) New-ChannelForgeAcceptedOutputManifest -GenerationId $value -ActiveM3UHash $a -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b } $hA $hB $bad } | Should -Throw 'FAIL_CLOSED:*'
        }
        foreach ($bad in @('', $null)) {
            { & (Get-Module ChannelForge) { param($a,$b,$value) New-ChannelForgeAcceptedOutputManifest -GenerationId $value -ActiveM3UHash $a -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b } $hA $hB $bad } | Should -Throw
        }
    }

    It 'recomputes both acceptance self-hashes and rejects forged bindings' {
        $objects = & (Get-Module ChannelForge) {
            param($a,$b,$c,$generation)
            $m3u = New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
            $decision = New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3u -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
            $output = New-ChannelForgeAcceptedOutputManifest -GenerationId $generation -ActiveM3UHash $c -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b
            $state = New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $decision.DecisionManifestHash -AcceptedOutputManifestHash $output.OutputManifestHash -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc '2026-08-29T00:00:00Z'
            $output.AcceptedStateHash = $state.AcceptedStateHash
            [pscustomobject]@{ Decision = $decision; State = $state; Output = $output }
        } $hA $hB $hC $generation
        { & (Get-Module ChannelForge) { param($o,$a,$b,$generation) Test-ChannelForgeAcceptanceBinding -DecisionManifest $o.Decision -AcceptedState $o.State -OutputManifest $o.Output -CandidateManifestHash $a -BuildIdentity $b -GenerationId $generation } $objects $hA $hB $generation } | Should -Not -Throw
        foreach ($mutation in @('StateHash','OutputHash','StateCopiedToOutput','WrongPreviousState')) {
            $copy = [pscustomobject]@{
                Decision = $objects.Decision
                State = [pscustomobject]$objects.State.PSObject.Copy()
                Output = [pscustomobject]$objects.Output.PSObject.Copy()
            }
            switch ($mutation) {
                'StateHash' { $copy.State.AcceptedStateHash = $hA }
                'OutputHash' { $copy.Output.OutputManifestHash = $hA }
                'StateCopiedToOutput' { $copy.State.AcceptedStateHash = $hA; $copy.Output.AcceptedStateHash = $hA }
                'WrongPreviousState' { $copy.State.PreviousStateHash = $hA }
            }
            { & (Get-Module ChannelForge) { param($o,$a,$b,$generation) Test-ChannelForgeAcceptanceBinding -DecisionManifest $o.Decision -AcceptedState $o.State -OutputManifest $o.Output -CandidateManifestHash $a -BuildIdentity $b -GenerationId $generation } $copy $hA $hB $generation } | Should -Throw 'FAIL_CLOSED:*'
        }
    }

    It 'rejects mixed acceptance and candidate contract versions' {
        $objects = & (Get-Module ChannelForge) {
            param($a,$b,$c,$generation)
            $m3u = New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
            $decision = New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3u -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
            $output = New-ChannelForgeAcceptedOutputManifest -GenerationId $generation -ActiveM3UHash $c -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b
            $state = New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $decision.DecisionManifestHash -AcceptedOutputManifestHash $output.OutputManifestHash -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc '2026-08-29T00:00:00Z'
            $output.AcceptedStateHash = $state.AcceptedStateHash
            [pscustomobject]@{ Decision = $decision; State = $state; Output = $output }
        } $hA $hB $hC $generation
        foreach ($name in @('Decision','State','Output')) {
            $copy = [pscustomobject]$objects.$name.PSObject.Copy()
            $copy.Version = 'blocker-2-contract/v8'
            $decision = if ($name -eq 'Decision') { $copy } else { $objects.Decision }
            $state = if ($name -eq 'State') { $copy } else { $objects.State }
            $output = if ($name -eq 'Output') { $copy } else { $objects.Output }
            { & (Get-Module ChannelForge) { param($d,$s,$o,$a,$b,$generation) Test-ChannelForgeAcceptanceBinding -DecisionManifest $d -AcceptedState $s -OutputManifest $o -CandidateManifestHash $a -BuildIdentity $b -GenerationId $generation } $decision $state $output $hA $hB $generation } | Should -Throw 'FAIL_CLOSED:*'
        }
        $candidateV7 = [pscustomobject][ordered]@{ Version = 'blocker-2-contract/v7'; ContractVersion = 'blocker-2-contract/v7'; Entries = @([pscustomobject]@{ EntryId = $hA }); BindingRecords = @() }
        { & (Get-Module ChannelForge) { param($candidate,$decision) New-ChannelForgeAcceptedEntries -CandidateManifest $candidate -DecisionManifest $decision -DecisionRecords @() } $candidateV7 $objects.Decision } | Should -Throw 'FAIL_CLOSED:*'
    }

    It 'requires explicit complete decision coverage and rejects stale or conflicting decisions' {
        $fixture = & (Get-Module ChannelForge) {
            param($a,$b,$c)
            $record = [ordered]@{ DecisionType = 'IncludeCandidateEntry'; CandidateEntryId = $a }
            $withoutId = [ordered]@{}; foreach ($p in $record.GetEnumerator()) { $withoutId[$p.Key] = $p.Value }
            $record.DecisionId = Get-ChannelForgeDomainHash -Domain 'decision-manifest/v2' -InputObject $withoutId
            $m3u = New-ChannelForgeDecisionM3U -CandidateManifestHash $b -BuildIdentity $c -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @() -DecisionIds @($record.DecisionId)
            $manifest = New-ChannelForgeDecisionManifest -CandidateManifestHash $b -BuildIdentity $c -M3UDecision $m3u -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
            $candidate = [pscustomobject][ordered]@{ Version = 'blocker-2-contract/v8'; ContractVersion = 'blocker-2-contract/v8'; Entries = @([pscustomobject]@{ EntryId = $a }); BindingRecords = @() }
            [pscustomobject]@{ Record = [pscustomobject]$record; Manifest = $manifest; Candidate = $candidate }
        } $hA $hB $hC
        { & (Get-Module ChannelForge) { param($f) New-ChannelForgeAcceptedEntries -CandidateManifest $f.Candidate -DecisionManifest $f.Manifest -DecisionRecords @() } $fixture } | Should -Throw 'FAIL_CLOSED:*'
        $accepted = & (Get-Module ChannelForge) { param($f) New-ChannelForgeAcceptedEntries -CandidateManifest $f.Candidate -DecisionManifest $f.Manifest -DecisionRecords @($f.Record) } $fixture
        $accepted.Count | Should -Be 1
        $stale = [pscustomobject][ordered]@{ DecisionId = $fixture.Record.DecisionId; DecisionType = 'IncludeCandidateEntry'; CandidateEntryId = $hB }
        { & (Get-Module ChannelForge) { param($f,$record) New-ChannelForgeAcceptedEntries -CandidateManifest $f.Candidate -DecisionManifest $f.Manifest -DecisionRecords @($record) } $fixture $stale } | Should -Throw 'FAIL_CLOSED:*'
        { & (Get-Module ChannelForge) { param($f) New-ChannelForgeAcceptedEntries -CandidateManifest $f.Candidate -DecisionManifest $f.Manifest -DecisionRecords @($f.Record,$f.Record) } $fixture } | Should -Throw 'FAIL_CLOSED:*'
        $conflict = & (Get-Module ChannelForge) {
            param($a)
            $record = [ordered]@{ DecisionType = 'ExcludeCandidateEntry'; CandidateEntryId = $a }
            $withoutId = [ordered]@{}; foreach ($p in $record.GetEnumerator()) { $withoutId[$p.Key] = $p.Value }
            $record.DecisionId = Get-ChannelForgeDomainHash -Domain 'decision-manifest/v2' -InputObject $withoutId
            [pscustomobject]$record
        } $hA
        $conflictManifest = [pscustomobject]$fixture.Manifest.PSObject.Copy()
        $conflictManifest.DecisionIds = @($fixture.Record.DecisionId,$conflict.DecisionId | Sort-Object)
        { & (Get-Module ChannelForge) { param($f,$manifest,$conflict) New-ChannelForgeAcceptedEntries -CandidateManifest $f.Candidate -DecisionManifest $manifest -DecisionRecords @($f.Record,$conflict) } $fixture $conflictManifest $conflict } | Should -Throw 'FAIL_CLOSED:*'
    }

    It 'accepts canonical UTC forms and rejects parseable non-canonical forms' {
        foreach ($timestamp in @('2026-08-29T00:00:00Z','2026-08-29T00:00:00.123Z','2026-08-29T00:00:00.1234567Z')) {
            { & (Get-Module ChannelForge) { param($a,$b,$c,$generation,$timestamp) New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $c -AcceptedOutputManifestHash $b -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc $timestamp } $hA $hB $hC $generation $timestamp } | Should -Not -Throw
        }
        foreach ($timestamp in @('2026-08-29 00:00:00Z','2026-08-29T00:00:00+00:00','2026-08-29T00:00:00z','2026-08-29T00:00:00.12345678Z')) {
            { & (Get-Module ChannelForge) { param($a,$b,$c,$generation,$timestamp) New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $c -AcceptedOutputManifestHash $b -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc $timestamp } $hA $hB $hC $generation $timestamp } | Should -Throw 'FAIL_CLOSED:*'
        }
    }

    It 'covers first-generation and all complete XMLTV transition graphs' {
        $results = & (Get-Module ChannelForge) {
            param($a,$b,$c,$generation)
            $make = {
                param($priorStatus,$currentStatus,$priorState,$priorOutput,$priorGeneration,$currentGeneration)
                $parentHash = if ($null -eq $priorOutput) { $null } else { $priorOutput.OutputManifestHash }
                $xmlDecision = if ($currentStatus -eq 'Generated') { New-ChannelForgeDecisionXMLTV -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $parentHash -AcceptedXMLTVStatus Generated -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c) } else { $null }
                $m3uDecision = New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $parentHash -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
                $decision = New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $xmlDecision -XMLTVDecisionStatus $currentStatus
                $activeXmlHash = if ($currentStatus -eq 'Generated') { $c } else { $null }
                $output = New-ChannelForgeAcceptedOutputManifest -GenerationId $currentGeneration -ActiveM3UHash $c -ActiveXMLTVStatus $currentStatus -ActiveXMLTVHash $activeXmlHash -AcceptedStateHash $b
                $state = New-ChannelForgeAcceptedState -GenerationId $currentGeneration -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $decision.DecisionManifestHash -AcceptedOutputManifestHash $output.OutputManifestHash -PreviousStateHash $(if($null -eq $priorState){$null}else{$priorState.AcceptedStateHash}) -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus $currentStatus -AcceptedAtUtc '2026-08-29T00:00:00Z'
                $output.AcceptedStateHash = $state.AcceptedStateHash
                $activeM3U = New-ChannelForgeActiveM3U -GenerationId $currentGeneration -AcceptedStateHash $state.AcceptedStateHash -OutputManifestHash $output.OutputManifestHash -ContentHash $c -ByteLength 1
                $activeXml = if ($currentStatus -eq 'Generated') { New-ChannelForgeActiveXMLTV -GenerationId $currentGeneration -AcceptedStateHash $state.AcceptedStateHash -OutputManifestHash $output.OutputManifestHash -Status Generated -ContentHash $c -ByteLength 1 -RelativePath 'merged.xml' } else { New-ChannelForgeActiveXMLTV -GenerationId $currentGeneration -AcceptedStateHash $state.AcceptedStateHash -OutputManifestHash $output.OutputManifestHash -Status NotGenerated -ContentHash $null -ByteLength 0 -RelativePath $null }
                $lineage = if ($null -eq $priorState) { Test-ChannelForgePreviousLineage -AcceptedState $state -GenerationManifest $null -PreviousM3U $null -PreviousXMLTV $null -PriorState $null -PriorOutput $null } else {
                    $previousM3U = New-ChannelForgePreviousM3U -GenerationId $currentGeneration -AcceptedStateHash $priorState.AcceptedStateHash -OutputManifestHash $priorOutput.OutputManifestHash -ContentHash $c -ByteLength 1 -PreviousGenerationId $priorGeneration
                    $previousXml = if ($priorStatus -eq 'Generated') { New-ChannelForgePreviousXMLTV -GenerationId $currentGeneration -AcceptedStateHash $priorState.AcceptedStateHash -OutputManifestHash $priorOutput.OutputManifestHash -Status Generated -ContentHash $c -ByteLength 1 -RelativePath 'merged.xml' -PreviousGenerationId $priorGeneration } else { New-ChannelForgePreviousXMLTV -GenerationId $currentGeneration -AcceptedStateHash $priorState.AcceptedStateHash -OutputManifestHash $priorOutput.OutputManifestHash -Status NotGenerated -ContentHash $null -ByteLength 0 -RelativePath $null -PreviousGenerationId $priorGeneration }
                    $generationManifest = [pscustomobject]@{ GenerationId = $currentGeneration; PreviousOutputManifestHash = $priorOutput.OutputManifestHash }
                    Test-ChannelForgePreviousLineage -AcceptedState $state -GenerationManifest $generationManifest -PreviousM3U $previousM3U -PreviousXMLTV $previousXml -PriorState $priorState -PriorOutput $priorOutput
                }
                [pscustomobject]@{ PriorStatus=$priorStatus; CurrentStatus=$currentStatus; Decision=$decision; State=$state; Output=$output; ActiveM3U=$activeM3U; ActiveXMLTV=$activeXml; Lineage=$lineage }
            }
            $first = @()
            foreach ($current in @('Generated','NotGenerated')) { $first += & $make $null $current $null $null $null $generation }
            foreach ($prior in @('Generated','NotGenerated')) {
                foreach ($current in @('Generated','NotGenerated')) {
                    $priorGeneration = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
                    $priorResult = & $make $null $prior $null $null $null $priorGeneration
                    $first += & $make $prior $current $priorResult.State $priorResult.Output $priorGeneration $generation
                }
            }
            $first
        } $hA $hB $hC $generation
        $results.Count | Should -Be 6
        foreach ($row in $results) {
            $row.Decision.XMLTVDecisionStatus | Should -Be $row.CurrentStatus
            $row.State.AcceptedXMLTVStatus | Should -Be $row.CurrentStatus
            $row.Output.ActiveXMLTVStatus | Should -Be $row.CurrentStatus
            $row.ActiveXMLTV.Status | Should -Be $row.CurrentStatus
            { & (Get-Module ChannelForge) { param($r,$a,$b,$generation) Test-ChannelForgeAcceptanceBinding -DecisionManifest $r.Decision -AcceptedState $r.State -OutputManifest $r.Output -CandidateManifestHash $a -BuildIdentity $b -GenerationId $generation } $row $hA $hB $generation } | Should -Not -Throw
            $row.Lineage.PreviousStateHash | Should -Be $row.State.PreviousStateHash
        }
    }
}
