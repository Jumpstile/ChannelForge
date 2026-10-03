BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1') -Force

    function New-KnowledgeSide {
        param(
            [string]$ChannelId,
            [string]$Title,
            [string]$ObservationId,
            [string]$SourceId,
            [string]$ChannelReference,
            [string]$Relationship = 'Independent'
        )
        [ordered]@{
            ChannelId = $ChannelId
            Title = $Title
            Subtitle = 'Quarterfinal 1'
            EventStatus = 'Live'
            ObservationId = $ObservationId
            SourceId = $SourceId
            SourceFamily = 'fixture-guide-family'
            SourceRelationship = $Relationship
            EvidenceClass = 'ConfiguredTrustedXMLTV'
            ChannelReference = $ChannelReference
            CategoryKeys = @('wrestling')
            Participants = @('Alpha', 'Beta')
            EpisodeNumber = $null
            Competition = 'Regional Final'
            StartUtc = '2026-01-01T13:00:00.0000000Z'
            StopUtc = '2026-01-01T14:00:00.0000000Z'
            SourceRecordReference = 'event-one'
            SourceDataTimeUtc = '2026-01-01T11:30:00Z'
            ObservationTimeUtc = '2026-01-01T11:45:00Z'
            FetchTimeUtc = '2026-01-01T11:45:00Z'
        }
    }

    function New-KnowledgeEvidencePair {
        param(
            [string]$LeftObservationId,
            [string]$RightObservationId,
            [string]$Relationship = 'Independent',
            [int]$Confidence = 90
        )
        $left = New-KnowledgeSide -ChannelId 'channel-one' -Title 'Alpha Beta Championship Final' -ObservationId $LeftObservationId -SourceId 'source-guide-one' -ChannelReference 'guide.one' -Relationship $Relationship
        $right = New-KnowledgeSide -ChannelId 'channel-two' -Title 'Alpha Beta Championship' -ObservationId $RightObservationId -SourceId 'source-guide-two' -ChannelReference 'guide.two' -Relationship $Relationship
        [ordered]@{
            ObservationIds = @($LeftObservationId, $RightObservationId)
            Sides = @($left, $right)
            ConfidenceScore = $Confidence
            CorrelationBasis = @('MatchingParticipants', 'MatchingCompetition', 'NearStartTime')
        }
    }

    function Initialize-KnowledgeIdentities {
        param([string]$Root)
        $plan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions @(
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-one' }; Reason = 'Test identity one.' },
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-two' }; Reason = 'Test identity two.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -Plan $plan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:00:00Z' | Out-Null
    }

    function New-TestKnowledgeRoot {
        param([string]$Name)
        $path = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }
}

Describe 'ChannelForge durable knowledge state' {
    It 'requires a current base revision before applying a plan' {
        $root = New-TestKnowledgeRoot -Name 'stale-plan'
        $first = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions @(
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-one' }; Reason = 'Register channel one.' }
        )
        $stale = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:00:01Z' -Actions @(
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-two' }; Reason = 'Register channel two.' }
        )

        $applied = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $first -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:00:02Z'
        $applied.Revision | Should -Be 1
        { Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $stale -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:00:03Z' } | Should -Throw 'FAIL_CLOSED:*'
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $root).Revision | Should -Be 1
    }

    It 'keeps source-scoped bindings proposed until their explicit approval transition' {
        $root = New-TestKnowledgeRoot -Name 'binding-approval'
        Initialize-KnowledgeIdentities -Root $root
        $binding = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'AddBinding'; Entry = @{ ChannelId = 'channel-one'; PlaylistId = 'playlist-one'; SourceId = 'source-0123456789abcdef'; SourceChannelReference = 'station.one'; ObservationIds = @() }; Reason = 'Propose exact source-scoped mapping.' }
        )
        $entryId = [string]$binding.Actions[0].Entry.EntryId
        $proposed = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $binding -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z'
        (@($proposed.Entries | Where-Object EntryId -eq $entryId)[0]).ApprovalStatus | Should -Be 'Proposed'

        $approve = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:02:00Z' -Actions @(
            @{ Action = 'Approve'; EntryId = $entryId; Reason = 'Approve exact reviewed channel mapping.' }
        )
        $approved = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $approve -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:02:00Z'
        (@($approved.Entries | Where-Object EntryId -eq $entryId)[0]).ApprovalStatus | Should -Be 'Approved'
        (@($approved.AuditTrail | Where-Object EntryId -eq $entryId | Select-Object -Last 1)[0]).Action | Should -Be 'Approve'
    }

    It 'rejects knowledge snapshot paths outside the repository root' {
        $root = New-TestKnowledgeRoot -Name 'path-boundary'
        $outside = Join-Path $TestDrive 'outside-knowledge-snapshot.json'

        { Export-ChannelForgeKnowledgeState -RepositoryRoot $root -OutputPath $outside } | Should -Throw 'FAIL_CLOSED:*'
        Test-Path -LiteralPath $outside | Should -BeFalse
    }
    It 'rejects a reparse-point knowledge parent before creating outside directories' {
        $root = New-TestKnowledgeRoot -Name 'reparse-parent'
        $outside = Join-Path $TestDrive 'outside-knowledge-root'
        $null = New-Item -ItemType Directory -Path $outside -Force
        $null = New-Item -ItemType Junction -Path (Join-Path $root 'state') -Target $outside

        { Get-ChannelForgeKnowledgeState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED:*'
        {
            $plan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions @(
                @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-one' }; Reason = 'Register channel one.' }
            )
            Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $plan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:00:01Z'
        } | Should -Throw 'FAIL_CLOSED:*'
        Test-Path -LiteralPath (Join-Path $outside 'knowledge') | Should -BeFalse
    }
    It 'pins repository directories against reparse-point replacement during knowledge writes' {
        $root = New-TestKnowledgeRoot -Name 'pinned-knowledge-writer'
        Initialize-KnowledgeIdentities -Root $root
        $outside = Join-Path $TestDrive 'pinned-outside-root'
        $null = New-Item -ItemType Directory -Path $outside -Force
        $handles = [ChannelForge.KnowledgeNativeIO]::OpenDirectoryChain((Join-Path $root 'state'))
        try {
            { Move-Item -LiteralPath (Join-Path $root 'state') -Destination (Join-Path $root 'state-moved') -ErrorAction Stop } | Should -Throw
            $plan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
                @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-three' }; Reason = 'Register while the parent directory is pinned.' }
            )
            $state = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $plan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z'
            @($state.Entries | Where-Object ChannelId -eq 'channel-three').Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $outside 'knowledge') | Should -BeFalse
        }
        finally { foreach ($handle in $handles) { $handle.Dispose() } }
    }

    It 'retains every grouped evidence pair in an initial contextual alias proposal' {
        $root = New-TestKnowledgeRoot -Name 'grouped-alias-evidence'
        Initialize-KnowledgeIdentities -Root $root
        $firstPair = New-KnowledgeEvidencePair -LeftObservationId ('a' * 64) -RightObservationId ('b' * 64)
        $secondPair = New-KnowledgeEvidencePair -LeftObservationId ('c' * 64) -RightObservationId ('d' * 64)
        $firstPair.Sides[0] | Add-Member -NotePropertyName Description -NotePropertyValue 'Safe source description.' -Force
        $plan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'ProposeAlias'; Entry = @{ Sides = $firstPair.Sides; ConfidenceScore = $firstPair.ConfidenceScore; CorrelationBasis = $firstPair.CorrelationBasis; EvidenceRecords = @($firstPair, $secondPair) }; Reason = 'Retain grouped contextual evidence.' }
        )
        $plan.Actions[0].Entry.EvidenceRecords.Count | Should -Be 2

        $state = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $plan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z'
        $alias = @($state.Entries | Where-Object Kind -eq 'ProgrammeAlias')[0]
        $alias.EvidenceRecords.Count | Should -Be 2
        $alias.ObservationIds.Count | Should -Be 4
        @($alias.EvidenceRecords[0].Sides.Description | Where-Object { $_ -eq 'Safe source description.' }).Count | Should -Be 1
        $alias.EvidenceCount | Should -Be 4
    }

    It 'rejects credential-shaped values and POSIX private paths before durable plan creation' {
        $root = New-TestKnowledgeRoot -Name 'unsafe-knowledge-text'
        $unsafeValues = @('token=fixture-secret', 'Authorization: Bearer fixture-secret', 'Authorization: Basic dXNlcjpwYXNz', 'Authorization=Basic dXNlcjpwYXNz', 'Authorization="Bearer quoted-secret"', 'Authorization: ''Basic quoted-secret''', 'API_TOKEN=fixture-secret', 'AWS_SECRET_ACCESS_KEY=fixture-secret', 'Bearer standalone-token', 'private file /home/operator/.config/token', 'Source note references \\server\share\private.xml')
        foreach ($value in $unsafeValues) {
            $pair = New-KnowledgeEvidencePair -LeftObservationId ('a' * 64) -RightObservationId ('b' * 64)
            $pair.Sides[0].Title = $value
            { New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions @(
                    @{ Action = 'ProposeAlias'; Entry = @{ Sides = $pair.Sides; ConfidenceScore = $pair.ConfidenceScore; CorrelationBasis = $pair.CorrelationBasis }; Reason = 'Reject unsafe evidence.' }
                ) } | Should -Throw 'KNOWLEDGE_INVALID:*'
        }
        { New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions @(
                @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-one' }; Reason = 'token=fixture-secret' }
            ) } | Should -Throw 'KNOWLEDGE_INVALID:*'
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $root).Revision | Should -Be 0
    }
    It 'rejects unsafe text in imported snapshots and restored backup history' {
        $sourceRoot = New-TestKnowledgeRoot -Name 'unsafe-import-source'
        $targetRoot = New-TestKnowledgeRoot -Name 'unsafe-import-target'
        Initialize-KnowledgeIdentities -Root $sourceRoot
        $exportPath = Join-Path $sourceRoot 'snapshot.json'
        Export-ChannelForgeKnowledgeState -RepositoryRoot $sourceRoot -OutputPath $exportPath | Out-Null
        $snapshot = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json -DateKind String
        $snapshot.AuditTrail[0].Reason = 'Bearer imported-secret'
        $module = Get-Module ChannelForge | Select-Object -First 1
        $unsafeImport = & $module {
            param($state)
            $state.StateHash = Get-ChannelForgeKnowledgeHash -State $state
            ConvertTo-ChannelForgeCanonicalJson -InputObject $state
        } $snapshot
        $importPath = Join-Path $targetRoot 'unsafe-import.json'
        [IO.File]::WriteAllText($importPath,$unsafeImport,[Text.UTF8Encoding]::new($false))
        { Import-ChannelForgeKnowledgeState -RepositoryRoot $targetRoot -InputPath $importPath -ConfirmImport IMPORT -ImportedAtUtc '2026-01-01T00:02:00Z' } | Should -Throw 'FAIL_CLOSED:*'
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $targetRoot).Revision | Should -Be 0

        $restoreRoot = New-TestKnowledgeRoot -Name 'unsafe-restore-history'
        Initialize-KnowledgeIdentities -Root $restoreRoot
        $nextPlan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $restoreRoot -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-three' }; Reason = 'Register a second identity.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $restoreRoot -Plan $nextPlan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z' | Out-Null
        $backupPath = Join-Path $restoreRoot 'state/knowledge/learned.json.r1.bak'
        $backup = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json -DateKind String
        $backup.Entries[0].History[0].Reason = 'Authorization: Basic dXNlcjpwYXNz'
        $unsafeBackup = & $module {
            param($state)
            $state.StateHash = Get-ChannelForgeKnowledgeHash -State $state
            ConvertTo-ChannelForgeCanonicalJson -InputObject $state
        } $backup
        [IO.File]::WriteAllText($backupPath,$unsafeBackup,[Text.UTF8Encoding]::new($false))
        { Restore-ChannelForgeKnowledgeState -RepositoryRoot $restoreRoot -BackupRevision 1 -ConfirmRestore RESTORE -RestoredAtUtc '2026-01-01T00:02:00Z' } | Should -Throw 'FAIL_CLOSED:*'
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $restoreRoot).Revision | Should -Be 2
    }
    It 'rejects imported aliases whose side text is unsafe or unsupported by their evidence' {
        $sourceRoot = New-TestKnowledgeRoot -Name 'alias-context-source'
        Initialize-KnowledgeIdentities -Root $sourceRoot
        $pair = New-KnowledgeEvidencePair -LeftObservationId ('e' * 64) -RightObservationId ('f' * 64)
        $plan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $sourceRoot -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'ProposeAlias'; Entry = @{ Sides = $pair.Sides; ConfidenceScore = $pair.ConfidenceScore; CorrelationBasis = $pair.CorrelationBasis }; Reason = 'Create import-validation fixture.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $sourceRoot -Plan $plan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z' | Out-Null
        $exportPath = Join-Path $sourceRoot 'alias-state.json'
        Export-ChannelForgeKnowledgeState -RepositoryRoot $sourceRoot -OutputPath $exportPath | Out-Null
        $snapshotText = Get-Content -LiteralPath $exportPath -Raw
        $module = Get-Module ChannelForge | Select-Object -First 1

        $unsafeSnapshot = $snapshotText | ConvertFrom-Json -DateKind String
        $unsafeAlias = @($unsafeSnapshot.Entries | Where-Object Kind -eq 'ProgrammeAlias')[0]
        $unsafeAlias.Sides[0].Description = 'Imported source note references \\server\share\private.xml'
        $unsafeText = & $module {
            param($state)
            $state.StateHash = Get-ChannelForgeKnowledgeHash -State $state
            ConvertTo-ChannelForgeCanonicalJson -InputObject $state
        } $unsafeSnapshot
        $unsafeTarget = New-TestKnowledgeRoot -Name 'alias-unsafe-text-target'
        $unsafePath = Join-Path $unsafeTarget 'unsafe-side.json'
        [IO.File]::WriteAllText($unsafePath,$unsafeText,[Text.UTF8Encoding]::new($false))
        { Import-ChannelForgeKnowledgeState -RepositoryRoot $unsafeTarget -InputPath $unsafePath -ConfirmImport IMPORT -ImportedAtUtc '2026-01-01T00:02:00Z' } | Should -Throw 'FAIL_CLOSED:*'

        $mismatchedSnapshot = $snapshotText | ConvertFrom-Json -DateKind String
        $mismatchedAlias = @($mismatchedSnapshot.Entries | Where-Object Kind -eq 'ProgrammeAlias')[0]
        $mismatchedAlias.Sides[0].Title = 'Unrelated forged programme'
        $newContextKey = & $module {
            param($sides)
            $normalized = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides $sides)
            Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $normalized)
        } @($mismatchedAlias.Sides)
        $mismatchedAlias.ContextKey = $newContextKey
        $mismatchedAlias.EntryId = $newContextKey
        $mismatchedText = & $module {
            param($state)
            $state.StateHash = Get-ChannelForgeKnowledgeHash -State $state
            ConvertTo-ChannelForgeCanonicalJson -InputObject $state
        } $mismatchedSnapshot
        $mismatchedTarget = New-TestKnowledgeRoot -Name 'alias-context-mismatch-target'
        $mismatchedPath = Join-Path $mismatchedTarget 'mismatched-side.json'
        [IO.File]::WriteAllText($mismatchedPath,$mismatchedText,[Text.UTF8Encoding]::new($false))
        { Import-ChannelForgeKnowledgeState -RepositoryRoot $mismatchedTarget -InputPath $mismatchedPath -ConfirmImport IMPORT -ImportedAtUtc '2026-01-01T00:02:00Z' } | Should -Throw 'FAIL_CLOSED:*'
        $emptyEvidenceSnapshot = $snapshotText | ConvertFrom-Json -DateKind String
        $emptyEvidenceAlias = @($emptyEvidenceSnapshot.Entries | Where-Object Kind -eq 'ProgrammeAlias')[0]
        $emptyEvidenceAlias.EvidenceRecords = @()
        $emptyEvidenceAlias.ObservationIds = @()
        $emptyEvidenceAlias.EvidenceCount = 0
        $emptyEvidenceAlias.ApprovalStatus = 'Approved'
        $emptyEvidenceText = & $module {
            param($state)
            $state.StateHash = Get-ChannelForgeKnowledgeHash -State $state
            ConvertTo-ChannelForgeCanonicalJson -InputObject $state
        } $emptyEvidenceSnapshot
        $emptyEvidenceTarget = New-TestKnowledgeRoot -Name 'alias-empty-evidence-target'
        $emptyEvidencePath = Join-Path $emptyEvidenceTarget 'empty-evidence.json'
        [IO.File]::WriteAllText($emptyEvidencePath,$emptyEvidenceText,[Text.UTF8Encoding]::new($false))
        { Import-ChannelForgeKnowledgeState -RepositoryRoot $emptyEvidenceTarget -InputPath $emptyEvidencePath -ConfirmImport IMPORT -ImportedAtUtc '2026-01-01T00:02:00Z' } | Should -Throw 'FAIL_CLOSED:*'

        (Get-ChannelForgeKnowledgeState -RepositoryRoot $emptyEvidenceTarget).Revision | Should -Be 0
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $unsafeTarget).Revision | Should -Be 0
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $mismatchedTarget).Revision | Should -Be 0
    }





    It 'promotes contextual aliases only after repeated high-confidence independent evidence pairs' {
        $root = New-TestKnowledgeRoot -Name 'probationary'
        Initialize-KnowledgeIdentities -Root $root
        $firstPair = New-KnowledgeEvidencePair -LeftObservationId ('a' * 64) -RightObservationId ('b' * 64)
        $proposal = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'ProposeAlias'; Entry = @{ Sides = $firstPair.Sides; ConfidenceScore = $firstPair.ConfidenceScore; CorrelationBasis = $firstPair.CorrelationBasis }; Reason = 'Record contextual candidate.' }
        )
        $entryId = [string]$proposal.Actions[0].Entry.EntryId
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $proposal -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z' | Out-Null

        $secondPair = New-KnowledgeEvidencePair -LeftObservationId ('c' * 64) -RightObservationId ('d' * 64)
        $append = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:02:00Z' -Actions @(
            @{ Action = 'AppendAliasEvidence'; EntryId = $entryId; ObservationIds = $secondPair.ObservationIds; EvidenceRecords = @($secondPair); Reason = 'Record a second independent observation pair.' }
        )
        $appended = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $append -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:02:00Z'
        $appendedAlias = @($appended.Entries | Where-Object EntryId -eq $entryId)[0]
        $appendedAlias.EvidenceRecords.Count | Should -Be 2
        $appendedAlias.EvidenceRecords[0].Sides[0].SourceId | Should -Be 'source-guide-one'
        $appendedAlias.EvidenceRecords[0].Sides[0].FetchTimeUtc | Should -Be '2026-01-01T11:45:00.0000000Z'

        $promote = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:03:00Z' -Actions @(
            @{ Action = 'MarkProbationary'; EntryId = $entryId; Reason = 'Repeated independent evidence reached the probation threshold.' }
        )
        $probationary = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $promote -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:03:00Z'
        (@($probationary.Entries | Where-Object EntryId -eq $entryId)[0]).ApprovalStatus | Should -Be 'Probationary'

        $reject = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:04:00Z' -Actions @(
            @{ Action = 'Reject'; EntryId = $entryId; Reason = 'Review rejected this exact contextual alias.' }
        )
        $rejected = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $reject -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:04:00Z'
        (@($rejected.Entries | Where-Object EntryId -eq $entryId)[0]).ApprovalStatus | Should -Be 'Rejected'
    }

    It 'does not count mirror evidence toward probationary alias promotion' {
        $root = New-TestKnowledgeRoot -Name 'mirror-evidence'
        Initialize-KnowledgeIdentities -Root $root
        $firstPair = New-KnowledgeEvidencePair -LeftObservationId ('1' * 64) -RightObservationId ('2' * 64) -Relationship 'Mirror'
        $proposal = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'ProposeAlias'; Entry = @{ Sides = $firstPair.Sides; ConfidenceScore = 95; CorrelationBasis = $firstPair.CorrelationBasis }; Reason = 'Record mirrored contextual candidate.' }
        )
        $entryId = [string]$proposal.Actions[0].Entry.EntryId
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $proposal -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z' | Out-Null

        $secondPair = New-KnowledgeEvidencePair -LeftObservationId ('3' * 64) -RightObservationId ('4' * 64) -Relationship 'Mirror'
        $append = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:02:00Z' -Actions @(
            @{ Action = 'AppendAliasEvidence'; EntryId = $entryId; ObservationIds = $secondPair.ObservationIds; EvidenceRecords = @($secondPair); Reason = 'Record a second mirror pair.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $append -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:02:00Z' | Out-Null
        $promote = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:03:00Z' -Actions @(
            @{ Action = 'MarkProbationary'; EntryId = $entryId; Reason = 'Attempt promotion from mirrored evidence.' }
        )

        { Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $promote -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:03:00Z' } | Should -Throw 'FAIL_CLOSED:*'
        (@((Get-ChannelForgeKnowledgeState -RepositoryRoot $root).Entries | Where-Object EntryId -eq $entryId)[0]).ApprovalStatus | Should -Be 'Proposed'
    }

    It 'exports, imports idempotently, and restores without decreasing the revision' {
        $sourceRoot = New-TestKnowledgeRoot -Name 'export-source'
        $targetRoot = New-TestKnowledgeRoot -Name 'import-target'
        $registration = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $sourceRoot -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions @(
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-one' }; Reason = 'Register portable identity.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $sourceRoot -Plan $registration -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:00:00Z' | Out-Null
        $snapshot = Join-Path $sourceRoot 'knowledge-export.json'
        Export-ChannelForgeKnowledgeState -RepositoryRoot $sourceRoot -OutputPath $snapshot | Out-Null
        $targetSnapshot = Join-Path $targetRoot 'knowledge-export.json'
        Copy-Item -LiteralPath $snapshot -Destination $targetSnapshot

        $imported = Import-ChannelForgeKnowledgeState -RepositoryRoot $targetRoot -InputPath $targetSnapshot -ConfirmImport IMPORT -ImportedAtUtc '2026-01-01T00:01:00Z'
        $imported.Revision | Should -Be 1
        $again = Import-ChannelForgeKnowledgeState -RepositoryRoot $targetRoot -InputPath $targetSnapshot -ConfirmImport IMPORT -ImportedAtUtc '2026-01-01T00:02:00Z'
        $again.Revision | Should -Be 1

        $targetPlan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $targetRoot -CreatedAtUtc '2026-01-01T00:03:00Z' -Actions @(
            @{ Action = 'RegisterIdentity'; Entry = @{ ChannelId = 'channel-two' }; Reason = 'Register second identity.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $targetRoot -Plan $targetPlan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:03:00Z' | Out-Null
        $restored = Restore-ChannelForgeKnowledgeState -RepositoryRoot $targetRoot -BackupRevision 1 -ConfirmRestore RESTORE -RestoredAtUtc '2026-01-01T00:04:00Z'
        $restored.Revision | Should -Be 3
        (@($restored.Entries | Where-Object ChannelId -eq 'channel-one')[0]).ApprovalStatus | Should -Be 'Approved'
        (@($restored.Entries | Where-Object ChannelId -eq 'channel-two')[0]).ApprovalStatus | Should -Be 'Revoked'
    }
    It 'restores an older alias backup while preserving later complete evidence pairs' {
        $root = New-TestKnowledgeRoot -Name 'restore-alias-evidence'
        Initialize-KnowledgeIdentities -Root $root
        $firstPair = New-KnowledgeEvidencePair -LeftObservationId ('a' * 64) -RightObservationId ('b' * 64)
        $proposal = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @(
            @{ Action = 'ProposeAlias'; Entry = @{ Sides = $firstPair.Sides; ConfidenceScore = $firstPair.ConfidenceScore; CorrelationBasis = $firstPair.CorrelationBasis }; Reason = 'Record contextual candidate.' }
        )
        $entryId = [string]$proposal.Actions[0].Entry.EntryId
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $proposal -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z' | Out-Null
        $secondPair = New-KnowledgeEvidencePair -LeftObservationId ('c' * 64) -RightObservationId ('d' * 64)
        $append = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -CreatedAtUtc '2026-01-01T00:02:00Z' -Actions @(
            @{ Action = 'AppendAliasEvidence'; EntryId = $entryId; ObservationIds = $secondPair.ObservationIds; EvidenceRecords = @($secondPair); Reason = 'Record a second evidence pair.' }
        )
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $root -Plan $append -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:02:00Z' | Out-Null

        $restored = Restore-ChannelForgeKnowledgeState -RepositoryRoot $root -BackupRevision 2 -ConfirmRestore RESTORE -RestoredAtUtc '2026-01-01T00:03:00Z'
        $alias = @($restored.Entries | Where-Object EntryId -eq $entryId)[0]
        $restored.Revision | Should -Be 4
        $alias.EvidenceRecords.Count | Should -Be 2
        $alias.ObservationIds.Count | Should -Be 4
        $alias.EvidenceCount | Should -Be 4
        $alias.LastSeenAtUtc | Should -Be '2026-01-01T00:02:00Z'
        @($restored.Entries | Where-Object Revision -ne $restored.Revision).Count | Should -Be 0
        @($restored.Entries | Where-Object Kind -eq 'ChannelIdentity').Count | Should -Be 2
    }

}
