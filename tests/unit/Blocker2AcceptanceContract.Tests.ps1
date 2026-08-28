BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ProposalRoot = Join-Path $script:RepoRoot 'docs\adr\blocker-2-contract-v8-proposal'
    $script:Docs = [ordered]@{}

    function Read-ProposalDocument {
        param([Parameter(Mandatory)][string]$Name)

        $path = Join-Path $script:ProposalRoot $Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "FAIL_CLOSED: required proposal document is missing: $Name"
        }
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "FAIL_CLOSED: required proposal document is empty: $Name"
        }
        return $text
    }

    function Assert-DocumentContains {
        param(
            [Parameter(Mandatory)][string]$Document,
            [Parameter(Mandatory)][string]$Needle,
            [Parameter(Mandatory)][string]$Evidence
        )

        if (-not $Document.Contains($Needle)) {
            throw "FAIL_CLOSED: missing $Evidence ($Needle)"
        }
    }

    function Assert-NormalizedContains {
        param(
            [Parameter(Mandatory)][string]$Document,
            [Parameter(Mandatory)][string]$Needle,
            [Parameter(Mandatory)][string]$Evidence
        )

        $normalizedDocument = [regex]::Replace($Document, '\s+', ' ')
        $normalizedNeedle = [regex]::Replace($Needle, '\s+', ' ')
        if (-not $normalizedDocument.Contains($normalizedNeedle)) {
            throw "FAIL_CLOSED: missing $Evidence ($Needle)"
        }
    }


    function Assert-DocumentMatches {
        param(
            [Parameter(Mandatory)][string]$Document,
            [Parameter(Mandatory)][string]$Pattern,
            [Parameter(Mandatory)][string]$Evidence
        )

        if ($Document -notmatch $Pattern) {
            throw "FAIL_CLOSED: missing $Evidence (/$Pattern/)"
        }
    }

    function Get-HeadingSection {
        param(
            [Parameter(Mandatory)][string]$Document,
            [Parameter(Mandatory)][string]$Heading
        )

        $escaped = [regex]::Escape($Heading)
        $match = [regex]::Match($Document, "(?ms)^$escaped\r?\n.*?(?=^#{1,2} |\z)")
        if (-not $match.Success) {
            throw "FAIL_CLOSED: required heading is missing: $Heading"
        }
        return $match.Value
    }

    function Assert-OrderedMarkers {
        param(
            [Parameter(Mandatory)][string]$Document,
            [Parameter(Mandatory)][string[]]$Markers,
            [Parameter(Mandatory)][string]$Evidence
        )

        $normalized = [regex]::Replace($Document, '\s+', ' ')
        $previous = -1
        foreach ($marker in $Markers) {
            $position = $normalized.IndexOf($marker, [StringComparison]::Ordinal)
            if ($position -lt 0) {
                throw "FAIL_CLOSED: missing topological marker '$marker' in $Evidence"
            }
            if ($position -le $previous) {
                throw "FAIL_CLOSED: non-topological order at '$marker' in $Evidence"
            }
            $previous = $position
        }
    }

    foreach ($name in @(
            'README.md',
            'PART-A-canonical-foundation.md',
            'PART-B-semantic-schemas.md',
            'PART-C-promotion-recovery.md',
            'SYMBOL-CLOSURE.md',
            'ISSUE-106-TECHNICAL-REVIEW.md')) {
        $script:Docs[$name] = Read-ProposalDocument $name
    }

    $script:AcceptanceVersion = 'blocker-2-contract/v8-acceptance'
    $script:CandidateVersion = 'blocker-2-contract/v7'
    $script:Domains = @(
        'pointer/v2',
        'accepted-state/v2',
        'active-m3u/v2',
        'active-xmltv/v2',
        'previous-m3u/v2',
        'previous-xmltv/v2',
        'decision-m3u/v2',
        'decision-xmltv/v2',
        'generation-manifest/v2',
        'previous-output-manifest/v2'
    )
}

Describe 'SECTION: ten-domain inventory' {
    It 'closes exactly the ten surface domains and one aggregate binding domain' {
        $section = Get-HeadingSection $script:Docs['PART-A-canonical-foundation.md'] '## 3. Exhaustive successor domain inventory'
        $rows = @([regex]::Matches($section, '(?m)^\d+\.\s+`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
        $rows | Should -Be @(
            'pointer/v2',
            'accepted-state/v2',
            'active-m3u/v2',
            'active-xmltv/v2',
            'previous-m3u/v2',
            'previous-xmltv/v2',
            'decision-m3u/v2',
            'decision-xmltv/v2',
            'generation-manifest/v2',
            'previous-output-manifest/v2',
            'decision-manifest/v2'
        )
        @($rows | Select-Object -First 10) | Should -Be $script:Domains
        Assert-DocumentContains $section 'PART-B is the sole owner of all eleven ordered projections.' 'single PART-B projection owner'
        Assert-DocumentContains $section 'decision-manifest/v2` (aggregate binding)' 'aggregate decision domain'
        Write-Output 'SECTION PASS: ten-domain inventory'
    }
}

Describe 'SECTION: symbol ownership' {
    It 'assigns every acceptance, decision, output, journal, and identity symbol to one owner' {
        $closure = $script:Docs['SYMBOL-CLOSURE.md']
        $ownership = [ordered]@{
            'CandidateContractVersion' = 'PART-A'
            'AcceptanceContractVersion' = 'PART-A'
            'BuildIdentity' = 'frozen v7 candidate contract'
            'PointerV2' = 'PART-B'
            'AcceptedStateV2' = 'PART-B'
            'ActiveM3UV2' = 'PART-B'
            'ActiveXMLTVV2' = 'PART-B'
            'PreviousM3UV2' = 'PART-B'
            'PreviousXMLTVV2' = 'PART-B'
            'DecisionM3UV2' = 'PART-B §8'
            'DecisionXMLTVV2' = 'PART-B §9'
            'DecisionManifestV2' = 'PART-B §10'
            'GenerationManifestV2' = 'PART-B §11'
            'PreviousOutputManifestV2' = 'PART-B §12'
            'M3UDecisionHash' = 'PART-B §8'
            'XMLTVDecisionHash' = 'PART-B §9–10'
            'DecisionManifestHash' = 'PART-B §10'
            'TransactionPhase' = 'PART-C'
            'JournalV2' = 'PART-C'
            'AcceptedOutputManifestV2' = 'PART-B §12'
            'OutputManifestHash' = 'PART-B §12 (hash rule in PART-A §5)'
            'JournalHash' = 'PART-C'
            'OldJournalHash' = 'PART-C'
            'GenerationId' = 'PART-A'
            'PreviousStateHash' = 'PART-B §3'
            'DuplicateCount' = 'PART-B §13'
        }
        foreach ($symbol in $ownership.Keys) {
            $pattern = '(?m)^\|\s*`' + [regex]::Escape($symbol) + '`\s*\|\s*' + [regex]::Escape($ownership[$symbol]) + '\s*\|'
            Assert-DocumentMatches $closure $pattern "sole owner for $symbol"
        }
        Assert-DocumentContains $closure 'inventory records no' 'closed symbol inventory'
        Assert-DocumentContains $closure 'The eleven named proposal projections each have one owner in PART-B.' 'eleven projection ownership'
        Assert-NormalizedContains $closure 'aggregate `DecisionManifestV2` is the only authority for' 'aggregate decision authority'
        Assert-DocumentContains $closure 'AcceptedOutputManifestV2` is a role-specific use' 'output-manifest role ownership'
        Write-Output 'SECTION PASS: symbol ownership'
    }
}

Describe 'SECTION: decision aggregate ownership' {
    It 'makes DecisionManifestHash singular and rejects stale subordinate ownership' {
        $aggregate = Get-HeadingSection $script:Docs['PART-B-semantic-schemas.md'] '## 10. `decision-manifest/v2` — DecisionManifestV2 aggregate'
        Assert-DocumentContains $aggregate '**Exact field list:** `Version,CandidateManifestHash,BuildIdentity,M3UDecisionHash,XMLTVDecisionStatus,XMLTVDecisionHash,DecisionIds,DecisionManifestHash`.' 'aggregate exact fields'
        Assert-DocumentContains $aggregate 'DecisionManifestHash = H(decision-manifest/v2, canonical bytes with only' 'aggregate hash domain'
        Assert-DocumentContains $aggregate 'DecisionManifestHash omitted)' 'aggregate self-hash omission'
        Assert-DocumentContains $aggregate 'The aggregate binds the subordinate M3U projection' 'subordinate binding'
        Assert-DocumentContains $aggregate 'is exactly `null` iff status is `NotGenerated`' 'NotGenerated aggregate hash nullability'
        Assert-NormalizedContains $aggregate 'The aggregate does not include either subordinate projection inline' 'no inline subordinate authority'
        Assert-NormalizedContains $aggregate 'a generation ID, a parent hash, an accepted state hash, an output hash, a generation hash, a pointer hash, or a journal hash' 'no stale aggregate links'

        foreach ($heading in @('## 3. `accepted-state/v2` — AcceptedStateV2', '## 11. `generation-manifest/v2` — GenerationManifestV2')) {
            $projection = Get-HeadingSection $script:Docs['PART-B-semantic-schemas.md'] $heading
            Assert-DocumentMatches $projection '(?m)^\*\*Exact field list:.*DecisionManifestHash' "aggregate reference in $heading"
            if ($projection -match '(?m)^\*\*Exact field list:.*(?:M3UDecisionHash|XMLTVDecisionHash)') {
                throw "FAIL_CLOSED: stale subordinate decision hash is owned by $heading"
            }
            if ($heading -like '*accepted-state*') {
                Assert-NormalizedContains $projection 'never carries or accepts either subordinate hash independently' 'subordinate hash exclusion'
            }
            else {
                Assert-NormalizedContains $projection 'never carries either subordinate decision hash' 'subordinate hash exclusion'
            }
        }
        Assert-DocumentContains $script:Docs['PART-A-canonical-foundation.md'] 'DecisionManifestHash` is the sole authoritative decision hash' 'sole authoritative decision hash'
        Assert-NormalizedContains $script:Docs['SYMBOL-CLOSURE.md'] 'contribute only their subordinate `M3UDecisionHash`/`XMLTVDecisionHash` values' 'subordinate-only ownership'
        Write-Output 'SECTION PASS: decision aggregate ownership'
    }
}

Describe 'SECTION: XMLTV status vectors and transitions' {
    It 'closes Generated and NotGenerated fields for first and later generations' {
        $b = $script:Docs['PART-B-semantic-schemas.md']
        $active = Get-HeadingSection $b '## 5. `active-xmltv/v2` — ActiveXMLTVV2'
        $previous = Get-HeadingSection $b '## 7. `previous-xmltv/v2` — PreviousXMLTVV2'
        Assert-DocumentContains $active 'ContentHash` | required nullable `Hash`; non-null iff `Status=Generated`, null iff `Status=NotGenerated`' 'active XMLTV content status'
        Assert-DocumentContains $active 'ByteLength` | required `UInt`; positive and exact iff `Generated`, exactly `0` iff `NotGenerated`' 'active XMLTV length status'
        Assert-DocumentContains $active 'RelativePath` | required nullable string exactly `merged.xml` iff `Generated`, exactly `null` iff `NotGenerated`' 'active XMLTV path status'
        Assert-DocumentContains $active 'Generated` requires a present `merged.xml`' 'Generated artifact requirement'
        Assert-DocumentContains $active 'NotGenerated` requires no `merged.xml`' 'NotGenerated artifact absence'
        Assert-DocumentContains $previous 'The XMLTV Generated/NotGenerated triple is identical to active XMLTV' 'previous status triple'
        Assert-DocumentContains $previous 'including N→N' 'N-to-N transition'
        Assert-DocumentContains $previous 'first-generation G and' 'first-generation vectors'
        foreach ($transition in @('G→G', 'G→N', 'N→G', 'N→N')) {
            Assert-DocumentContains $previous $transition "XMLTV transition $transition"
        }
        Assert-DocumentContains $previous 'only the first generation omits' 'first-generation omission boundary'
        Assert-DocumentContains $previous 'previous-output object and previous descriptors.' 'first-generation previous-object omission'
        Assert-NormalizedContains $b 'XMLTVDecisionStatus`, accepted-state `AcceptedXMLTVStatus`, output `ActiveXMLTVStatus`, and active descriptor `Status` must all equal `S`' 'cross-projection status equality'
        Assert-NormalizedContains $b 'NotGenerated status never permits a fabricated hash or empty stand-in object' 'no fabricated XMLTV decision'
        Write-Output 'SECTION PASS: XMLTV status vectors and transitions'
    }
}

Describe 'SECTION: mixed-generation A-J matrix' {
    It 'requires all ten labeled mixed-generation rejection cases to fail closed' {
        $c = $script:Docs['PART-C-promotion-recovery.md']
        $matrix = Get-HeadingSection $c '## 12. Mixed-generation rejection cases'
        $rows = @([regex]::Matches($matrix, '(?m)^\|\s*([A-J])\s*\|') | ForEach-Object { $_.Groups[1].Value })
        $rows | Should -Be @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J')
        Assert-DocumentContains $matrix 'The required ten-case rejection matrix is labeled exactly `A` through `J`.' 'A-J matrix closure'
        Assert-DocumentContains $matrix 'Every row has the same result: `FAIL_CLOSED_RECOVERY_REQUIRED`; mutate no pointer, generation, accepted artifact, or journal.' 'uniform fail-closed result'
        foreach ($case in @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J')) {
            Assert-DocumentMatches $matrix "(?m)^\|\s*$case\s*\|.*FAIL_CLOSED_RECOVERY_REQUIRED" "mixed-generation case $case result"
        }
        foreach ($field in @('Pointer.GenerationId', 'AcceptedState.CandidateManifestHash', 'ActiveM3U.GenerationId', 'GenerationManifest.PreviousOutputManifestHash', 'Decision.AcceptedParentGenerationManifestHash', 'state/accepted-lineup.json.previous', 'Journal.ExpectedOldPointerHash', 'Journal.OldJournalHash', 'FileIdentity')) {
            Assert-DocumentContains $matrix $field "mixed-generation field $field"
        }
        Write-Output 'SECTION PASS: mixed-generation A-J matrix'
    }
}

Describe 'SECTION: recovery boundaries and predicates' {
    It 'closes named durability boundaries and first-match recovery predicates' {
        $c = $script:Docs['PART-C-promotion-recovery.md']
        $boundary = Get-HeadingSection $c '## 8. Durability boundary matrix'
        foreach ($row in @(
                'Child/generation stage write',
                'Prepared journal replace',
                'Generation directory move',
                'GenerationPublished journal replace',
                'Pointer compare-and-swap',
                'PointerSwapped journal replace',
                'Full graph reopen',
                'Committed journal replace',
                'Cleanup')) {
            Assert-DocumentContains $boundary $row "durability boundary $row"
        }
        Assert-DocumentContains $boundary 'Before: OLD; after: NEW, even if the old journal is still GenerationPublished.' 'pointer authority boundary'
        Assert-DocumentContains $boundary 'Any before/after state remains NEW; retry cleanup, never rollback.' 'cleanup authority rule'

        $predicates = Get-HeadingSection $c '### 9.1 Recovery predicates'
        foreach ($predicate in @('R_lock', 'R_bad', 'R_journal', 'R_old', 'R_new', 'R_empty', 'R_other')) {
            $pattern = '(?m)^-\s+`' + [regex]::Escape($predicate) + '\s*:='
            Assert-DocumentMatches $predicates $pattern "recovery predicate $predicate"
        }
        Assert-DocumentContains $predicates 'R_lock := L -> FAIL_CLOSED_RECOVERY_REQUIRED' 'live-lock predicate'
        Assert-DocumentContains $predicates 'R_empty := not L and not U and not Jbad and not J and not S and E -> INITIAL_BASELINE_REQUIRED' 'empty-baseline predicate'
        Assert-DocumentContains $predicates 'R_other := none of R_lock, R_bad, R_journal, R_old, R_new, or R_empty' 'fallback predicate'
        Assert-NormalizedContains $c 'Recovery uses the following named first-match predicates in order' 'first-match ordering'

        $matrix = Get-HeadingSection $c '## 9. Recovery matrix'
        Assert-DocumentContains $matrix 'Recovery is first-match-wins.' 'recovery first-match rule'
        Assert-DocumentContains $matrix 'It never chooses a generation by directory order, timestamp, lexical order, or output contents.' 'no guessed generation'
        Assert-DocumentContains $matrix 'Journal backup left without a valid in-progress replacement' 'orphan backup rejection'
        Assert-DocumentContains $matrix 'Reparse/path substitution, UNC/SMB path, or changed FileIdentity' 'safe-path rejection'
        Assert-DocumentContains $matrix 'Cleanup failure after Committed' 'post-commit cleanup result'
        Write-Output 'SECTION PASS: recovery boundaries and predicates'
    }
}

Describe 'SECTION: acyclic hash graph and topological markers' {
    It 'records the semantic dependency graph and promotion happens-before order' {
        $a = $script:Docs['PART-A-canonical-foundation.md']
        $c = $script:Docs['PART-C-promotion-recovery.md']
        Assert-DocumentContains $a 'The hash dependency graph is:' 'hash graph declaration'
        Assert-DocumentContains $a 'Consequently, the decision portion of the graph is acyclic.' 'decision graph acyclicity'
        Assert-DocumentContains $c 'The semantic hash graph is independently acyclic' 'semantic graph acyclicity'
        Assert-DocumentContains $c 'each arrow is a required happens-before edge' 'topological edge declaration'
        $aGraph = Get-HeadingSection $a '## 6. Acyclic dependency and ownership'
        $cGraph = Get-HeadingSection $c '## 13. Acyclic transaction ordering'
        Assert-OrderedMarkers $aGraph @(
            'v7 candidate inputs',
            'CandidateManifestHash/BuildIdentity',
            'decision-m3u subordinate',
            'decision-manifest aggregate',
            'accepted-state/output',
            'generation-manifest',
            'pointer'
        ) 'PART-A semantic hash graph'
        Assert-OrderedMarkers $cGraph @(
            'lock and safe-input validation',
            'candidate artifact bytes and hashes',
            'decision bytes and hash',
            'accepted active artifacts',
            'output-manifest hash',
            'accepted-state hash',
            'complete generation manifest hash',
            'staged new pointer hash',
            'Prepared journal publication',
            'final generation directory move',
            'GenerationPublished JournalHash/publication',
            'old-pointer compare-and-swap to staged new pointer',
            'PointerSwapped JournalHash/publication',
            'Committed JournalHash/publication',
            'owner-only cleanup'
        ) 'PART-C promotion order'
        Assert-DocumentContains $c 'JournalHash` hashes only the ordered Journal projection without itself and points backward through `OldJournalHash`' 'backward-only journal edge'
        Assert-DocumentContains $c 'no node hashes itself, a later node, or a journal' 'no forward/self hash edge'
        Write-Output 'SECTION PASS: acyclic hash graph and topological markers'
    }
}

Describe 'SECTION: self-hash omission' {
    It 'requires every integrity self-hash to be excluded from its own canonical input' {
        $b = $script:Docs['PART-B-semantic-schemas.md']
        $rules = @(
            @('PointerHash', 'canonical pointer bytes with PointerHash omitted'),
            @('AcceptedStateHash', 'AcceptedStateHash, GenerationId, and AcceptedAtUtc omitted'),
            @('M3UDecisionHash', 'canonical bytes with M3UDecisionHash omitted'),
            @('XMLTVDecisionHash', 'canonical bytes with XMLTVDecisionHash omitted'),
            @('DecisionManifestHash', 'canonical bytes with only'),
            @('GenerationManifestHash', 'GenerationManifestHash and GenerationId omitted'),
            @('OutputManifestHash', 'OutputManifestHash, GenerationId, and AcceptedStateHash omitted')
        )
        foreach ($rule in $rules) {
            Assert-NormalizedContains $b $rule[1] "self-hash omission for $($rule[0])"
        }
        Assert-DocumentContains $script:Docs['PART-A-canonical-foundation.md'] 'Integrity hashes identify the declared canonical record' 'integrity hash distinction'
        Assert-DocumentContains $script:Docs['PART-A-canonical-foundation.md'] '`OutputManifestHash` excludes the required `AcceptedStateHash` reference' 'state/output cycle exclusion'
        Write-Output 'SECTION PASS: self-hash omission'
    }
}

Describe 'SECTION: candidate-v7 preservation' {
    It 'preserves frozen candidate authority and keeps the proposal unfrozen' {
        $a = $script:Docs['PART-A-canonical-foundation.md']
        $readme = $script:Docs['README.md']
        $review = $script:Docs['ISSUE-106-TECHNICAL-REVIEW.md']
        Assert-DocumentContains $a 'CandidateContractVersion` is the literal `blocker-2-contract/v7`' 'candidate v7 authority'
        Assert-DocumentContains $a 'Every retained candidate projection, candidate artifact, `BuildIdentity`, and candidate `Version` field remains owned by v7.' 'candidate field preservation'
        Assert-DocumentContains $a 'CandidateManifestHash` are v7 candidate values and are copied, never re-versioned or re-hashed by an acceptance domain.' 'candidate hash preservation'
        Assert-DocumentContains $readme 'Prior frozen authority: `blocker-2-contract/v7`' 'frozen v7 authority marker'
        Assert-NormalizedContains $readme 'Runtime acceptance, promotion, recovery, pointer publication, and generation publication may begin only after this corrected frozen authority is integrated' 'runtime authority boundary'
        Assert-NormalizedContains $readme 'Exact RevisionContentId is recorded in the governance FREEZE-RECORD' 'RCID governance ownership'
        foreach ($value in @(
                'IdentityRulesVersion` | `lineup-history-v1`',
                'M3UParserContractVersion` | `m3u-parser-v1`',
                'XMLTVParserContractVersion` | `xmltv-parser-v1`',
                'M3USerializerVersion` | `m3u-serializer-v1`',
                'XMLTVSerializerVersion` | `xmltv-serializer-v1`',
                'GuideBindingContractVersion` | `guide-binding-exact-ordinal-v1`')) {
            Assert-DocumentContains $review $value "preserved candidate $value"
        }
        Assert-DocumentContains $review 'Candidate namespace authority' 'candidate namespace boundary'
        Assert-DocumentContains $review 'Candidate review privacy boundary' 'candidate review boundary'
        Assert-DocumentContains $review 'Fixture values: evidence only.' 'fixture-value non-constant rule'
        Assert-DocumentContains $review 'Runtime authority | None until a new revision is approved and frozen' 'runtime authority gate'
        Write-Output 'SECTION PASS: candidate-v7 preservation'
    }
}

Describe 'SECTION: final Issue 106 remediation' {
    It 'closes PreviousStateHash ownership and DuplicateCount overflow' {
        $symbols = $script:Docs['SYMBOL-CLOSURE.md']
        $partB = $script:Docs['PART-B-semantic-schemas.md']
        Assert-DocumentMatches $symbols '(?m)^\|\s*`PreviousStateHash`\s*\|\s*PART-B §3\s*\|' 'PreviousStateHash sole owner'
        @([regex]::Matches($symbols, '(?m)^\|\s*`PreviousStateHash`\s*\|')).Count | Should -Be 1
        Assert-NormalizedContains $symbols 'null only first generation; later value is exact prior AcceptedStateHash; backward reference, not independently rehashed' 'PreviousStateHash backward rule'
        Assert-NormalizedContains $partB 'Valid range is `0..4294967295` inclusive' 'DuplicateCount uint32 range'
        Assert-NormalizedContains $partB 'exceeds `4294967295`' 'DuplicateCount overflow predicate'
        Assert-NormalizedContains $partB 'MUST fail closed before serializing or accepting' 'DuplicateCount overflow fail closed'
        Assert-NormalizedContains $partB 'saturation, modulo/wraparound, truncation, and implementation-defined behavior are forbidden' 'DuplicateCount overflow prohibitions'
        Assert-NormalizedContains $partB 'No serialized DuplicateCount is produced for an overflow' 'DuplicateCount no serialization'
        Write-Output 'SECTION PASS: final Issue 106 remediation'
    }
}
