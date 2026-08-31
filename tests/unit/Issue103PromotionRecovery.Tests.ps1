BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force

    function New-Issue103Fixture {
        param([Parameter(Mandatory)][string]$GenerationId,[switch]$Generated,[AllowNull()][object]$PreviousStateHash,[AllowNull()][object]$PreviousOutputManifestHash)
        & (Get-Module ChannelForge) {
            param($GenerationId,$Generated,$PreviousStateHash,$PreviousOutputManifestHash)
            $a='a'*64; $b='b'*64; $c='c'*64
            $m3uDecision=New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
            $xmlDecision=if ($Generated) { New-ChannelForgeDecisionXMLTV -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -AcceptedXMLTVStatus Generated -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c) } else { $null }
            $status=if ($Generated) {'Generated'} else {'NotGenerated'}
            $decision=New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $xmlDecision -XMLTVDecisionStatus $status
            $m3u=[Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Channel $GenerationId`nhttps://example.invalid/$GenerationId`n")
            $m3uHash=Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $m3u
            $xml=if ($Generated) { [Text.Encoding]::UTF8.GetBytes('<?xml version="1.0" encoding="UTF-8"?><tv></tv>') } else { $null }
            $xmlHash=if ($Generated) { Get-ChannelForgeDomainHash -Domain 'active-xmltv/v2' -Bytes $xml } else { $null }
            $output=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$GenerationId;ActiveM3UHash=$m3uHash;ActiveXMLTVStatus=$status;ActiveXMLTVHash=$xmlHash;AcceptedStateHash=$b;OutputManifestHash=$null}
            $output.OutputManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'previous-output-manifest/v2' -Projection $output -HashProperty OutputManifestHash -Omit @('GenerationId','AcceptedStateHash')
            $state=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$GenerationId;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedOutputManifestHash=$output.OutputManifestHash;PreviousStateHash=$PreviousStateHash;IncludedCandidateEntryIds=@($a);ExcludedCandidateEntryIds=@($b);AcceptedBindingIds=@($c);AcceptedXMLTVStatus=$status;AcceptedAtUtc='2026-08-29T00:00:00Z';AcceptedStateHash=$null}
            $state.AcceptedStateHash=Get-ChannelForgeAcceptanceHash -Domain 'accepted-state/v2' -Projection $state -HashProperty AcceptedStateHash -Omit @('GenerationId','AcceptedAtUtc')
            $output.AcceptedStateHash=$state.AcceptedStateHash
            $manifest=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$GenerationId;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedStateHash=$state.AcceptedStateHash;AcceptedOutputManifestHash=$output.OutputManifestHash;ActiveM3UHash=$output.ActiveM3UHash;ActiveXMLTVHash=$output.ActiveXMLTVHash;PreviousOutputManifestHash=$PreviousOutputManifestHash;GenerationManifestHash=$null}
            $manifest.GenerationManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
            [pscustomobject]@{GenerationManifest=[pscustomobject]$manifest;AcceptedState=[pscustomobject]$state;AcceptedOutputManifest=[pscustomobject]$output;DecisionManifest=$decision;M3UBytes=$m3u;XMLTVBytes=$xml}
        } $GenerationId ([bool]$Generated) $PreviousStateHash $PreviousOutputManifestHash
    }
}

Describe 'Issue 103 immutable generation promotion and recovery' {
    It 'publishes a first immutable NotGenerated generation and classifies it valid after restart' {
        $root=Join-Path $TestDrive 'first'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        $result=Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes
        $result.Outcome | Should -Be 'NEW'
        (Test-Path (Join-Path $root 'state/accepted-lineup.json')) | Should -BeTrue
        (Test-Path (Join-Path $root 'state/accepted-lineup.json.previous')) | Should -BeFalse
        (Test-Path (Join-Path $root 'state/generations/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/merged.xml')) | Should -BeFalse
        (Get-Item (Join-Path $root 'state/generations/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/generation.manifest.json')).IsReadOnly | Should -BeTrue
        $recovery=Recover-ChannelForgeAcceptedState -RepositoryRoot $root
        $recovery.Outcome | Should -Be 'NEW'
        $recovery.JournalStage | Should -Be 'Committed'
    }

    It 'replaces the pointer atomically and preserves exact previous pointer bytes' {
        $root=Join-Path $TestDrive 'second'
        $first=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $first.GenerationManifest -AcceptedState $first.AcceptedState -AcceptedOutputManifest $first.AcceptedOutputManifest -DecisionManifest $first.DecisionManifest -M3UBytes $first.M3UBytes -XMLTVBytes $first.XMLTVBytes | Out-Null
        $oldBytes=[IO.File]::ReadAllBytes((Join-Path $root 'state/accepted-lineup.json'))
        $second=New-Issue103Fixture -GenerationId 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210' -PreviousStateHash $first.AcceptedState.AcceptedStateHash -PreviousOutputManifestHash $first.AcceptedOutputManifest.OutputManifestHash
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $second.GenerationManifest -AcceptedState $second.AcceptedState -AcceptedOutputManifest $second.AcceptedOutputManifest -DecisionManifest $second.DecisionManifest -M3UBytes $second.M3UBytes -XMLTVBytes $second.XMLTVBytes | Out-Null
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'state/accepted-lineup.json.previous'))) | Should -Be ([Convert]::ToBase64String($oldBytes))
        (Get-Content (Join-Path $root 'state/accepted-lineup.json') -Raw) | Should -Match 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
        (Get-Content (Join-Path $root 'output/merged.m3u') -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'stages Generated XMLTV only when the output status is Generated' {
        $root=Join-Path $TestDrive 'xml'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' -Generated
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes | Out-Null
        (Test-Path (Join-Path $root 'state/generations/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/merged.xml')) | Should -BeTrue
    }
    It 'accepts #102 constructor output directly without semantic transformation' {
        $root = Join-Path $TestDrive 'issue102-direct'
        $generation = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        $fixture = & (Get-Module ChannelForge) {
            param($generation)
            $a='a'*64; $b='b'*64; $c='c'*64
            $m3uBytes=[Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Direct`nhttps://example.invalid/direct`n")
            $m3uHash=Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $m3uBytes
            $m3uDecision=New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
            $decision=New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
            $output=New-ChannelForgeAcceptedOutputManifest -GenerationId $generation -ActiveM3UHash $m3uHash -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b
            $state=New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $decision.DecisionManifestHash -AcceptedOutputManifestHash $output.OutputManifestHash -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc '2026-08-29T00:00:00Z'
            $output.AcceptedStateHash=$state.AcceptedStateHash
            $manifest=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedStateHash=$state.AcceptedStateHash;AcceptedOutputManifestHash=$output.OutputManifestHash;ActiveM3UHash=$output.ActiveM3UHash;ActiveXMLTVHash=$output.ActiveXMLTVHash;PreviousOutputManifestHash=$null;GenerationManifestHash=$null}
            $manifest.GenerationManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
            $descriptor=New-ChannelForgeActiveM3U -GenerationId $generation -AcceptedStateHash $state.AcceptedStateHash -OutputManifestHash $output.OutputManifestHash -ContentHash $m3uHash -ByteLength $m3uBytes.Length
            $xmlDescriptor=New-ChannelForgeActiveXMLTV -GenerationId $generation -AcceptedStateHash $state.AcceptedStateHash -OutputManifestHash $output.OutputManifestHash -Status NotGenerated -ContentHash $null -ByteLength 0 -RelativePath $null
            [pscustomobject]@{GenerationManifest=[pscustomobject]$manifest;AcceptedState=$state;AcceptedOutputManifest=$output;DecisionManifest=$decision;M3UBytes=$m3uBytes;XMLTVBytes=$null;Descriptor=$descriptor;XMLTVDescriptor=$xmlDescriptor}
        } $generation
        $fixture.Descriptor.GenerationId | Should -Be $generation
        $fixture.Descriptor.AcceptedStateHash | Should -Be $fixture.AcceptedState.AcceptedStateHash
        $fixture.Descriptor.OutputManifestHash | Should -Be $fixture.AcceptedOutputManifest.OutputManifestHash
        $fixture.Descriptor.ContentHash | Should -Be $fixture.AcceptedOutputManifest.ActiveM3UHash
        $fixture.XMLTVDescriptor.Status | Should -Be 'NotGenerated'
        $fixture.XMLTVDescriptor.ContentHash | Should -BeNullOrEmpty
        (Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes).Outcome | Should -Be 'NEW'
        (Recover-ChannelForgeAcceptedState -RepositoryRoot $root).Outcome | Should -Be 'NEW'
    }

    It 'fails closed on every named runtime fault boundary' {
        $hooks=@('A01 StageWrite.GenerationManifest','A02 StageFlush.GenerationManifest','A03 StageReopenHash.GenerationManifest','A04 StageWrite.AcceptedState','A05 StageFlush.AcceptedState','A06 StageReopenHash.AcceptedState','A07 StageWrite.AcceptedOutputManifest','A08 StageFlush.AcceptedOutputManifest','A09 StageReopenHash.AcceptedOutputManifest','A10 StageWrite.DecisionManifest','A11 StageFlush.DecisionManifest','A12 StageReopenHash.DecisionManifest','A13 StageWrite.M3U','A14 StageFlush.M3U','A15 StageReopenHash.M3U','A16 StageWrite.XMLTV','A17 StageFlush.XMLTV','A18 StageReopenHash.XMLTV','A19 JournalWrite.Prepared','A20 JournalFlush.Prepared','A21 JournalReopenHash.Prepared','A22 JournalBeforeReplace.Prepared','A23 JournalAfterReplace.Prepared','A24 GenerationDirectoryMove.Before','A25 GenerationDirectoryMove.After','A26 JournalBeforeReplace.GenerationPublished','A27 JournalAfterReplace.GenerationPublished','A28 PointerReplace.Before','A29 PointerReplace.After','A30 JournalBeforeReplace.PointerSwapped','A31 JournalAfterReplace.PointerSwapped','A32 VerifyCurrentPointer.Before','A33 VerifyCurrentPointer.After','A34 JournalBeforeReplace.Committed','A35 JournalAfterReplace.Committed','A36 CleanupDelete.GenerationStage.Before','A37 CleanupDelete.GenerationStage.After','A38 CleanupDelete.PointerJournalBackup.Before','A39 CleanupDelete.PointerJournalBackup.After','A40 CleanupDelete.TransactionDirectory.Before','A41 CleanupDelete.TransactionDirectory.After','A42 Verify.GenerationManifest.Before','A43 Verify.GenerationManifest.After','A44 Verify.AcceptedState.Before','A45 Verify.AcceptedState.After','A46 Verify.OutputManifest.Before','A47 Verify.OutputManifest.After','A48 Verify.M3U.Before','A49 Verify.M3U.After','A50 Verify.XMLTV.Before','A51 Verify.XMLTV.After','A52 JournalStageWrite.GenerationPublished','A53 JournalStageFlush.GenerationPublished','A54 JournalStageReopenHash.GenerationPublished','A55 JournalStageWrite.PointerSwapped','A56 JournalStageFlush.PointerSwapped','A57 JournalStageReopenHash.PointerSwapped','A58 JournalStageWrite.Committed','A59 JournalStageFlush.Committed','A60 JournalStageReopenHash.Committed')
        foreach ($item in $hooks) {
            $parts=$item -split ' ',2; $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' -Generated
            { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes -FaultHook $parts[1] } | Should -Throw -Because $item
        }
    }

    It 'returns INITIAL_BASELINE_REQUIRED for an empty store and FAIL_CLOSED for malformed authority' {
        $empty=Join-Path $TestDrive 'empty'; (Recover-ChannelForgeAcceptedState -RepositoryRoot $empty).Outcome | Should -Be 'INITIAL_BASELINE_REQUIRED'
        $bad=Join-Path $TestDrive 'bad'; New-Item (Join-Path $bad 'state') -ItemType Directory -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $bad 'state/accepted-lineup.json'),'{}')
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $bad } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
        $valid=Join-Path $TestDrive 'nojournal'; $vf=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $valid -GenerationManifest $vf.GenerationManifest -AcceptedState $vf.AcceptedState -AcceptedOutputManifest $vf.AcceptedOutputManifest -DecisionManifest $vf.DecisionManifest -M3UBytes $vf.M3UBytes | Out-Null
        Remove-Item (Join-Path $valid 'state/accepted-lineup.journal.json')
        (Recover-ChannelForgeAcceptedState -RepositoryRoot $valid).Outcome | Should -Be 'ACCEPTED_STATE_VALID'
    }
    It 'resolves pointer-swap and committed-journal interruption to coherent NEW state' {
        $root=Join-Path $TestDrive 'restart'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -FaultHook 'PointerReplace.After' } | Should -Throw
        $firstRecovery=Recover-ChannelForgeAcceptedState -RepositoryRoot $root
        $firstRecovery.Outcome | Should -Be 'NEW'
        $firstRecovery.JournalStage | Should -Be 'PointerSwapped'
        $secondRecovery=Recover-ChannelForgeAcceptedState -RepositoryRoot $root
        $secondRecovery.Outcome | Should -Be 'NEW'
        $secondRecovery.JournalStage | Should -Be 'Committed'
    }

    It 'blocks concurrent recovery while the exclusive operation lock is live' {
        $root=Join-Path $TestDrive 'lock'
        New-Item (Join-Path $root 'state') -ItemType Directory -Force | Out-Null
        $lease=& (Get-Module ChannelForge) { param($path) $null=Initialize-ChannelForgeGenerationStore; [ChannelForge.GenerationStore]::AcquireLock($path) } (Join-Path $root 'state/lineup-operation.lock')
        try { { Recover-ChannelForgeAcceptedState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*' }
        finally { $lease.Dispose() }
    }

    It 'rejects invalid generation identity and non-local authority roots before mutation' {
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        $bad=[pscustomobject]$fixture.GenerationManifest.PSObject.Copy(); $bad.GenerationId='A'*63
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot (Join-Path $TestDrive 'identity') -GenerationManifest $bad -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw 'FAIL_CLOSED:*'
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot '\\server\share\clone' -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw
    }
    It 'rejects self-valid graph identity substitution and XMLTV status inconsistency' {
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        $bad=[pscustomobject]$fixture.GenerationManifest.PSObject.Copy()
        $bad.GenerationId='f'*64
        $badOrdered=[ordered]@{}; foreach($property in $bad.PSObject.Properties){$badOrdered[$property.Name]=$property.Value}
        $bad.GenerationManifestHash=& (Get-Module ChannelForge) { param($projection) Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $projection -HashProperty GenerationManifestHash -Omit @('GenerationId') } $badOrdered
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot (Join-Path $TestDrive 'graph-id') -GenerationManifest $bad -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw 'FAIL_CLOSED*'
        $generated=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' -Generated
        $badOutput=[pscustomobject]$generated.AcceptedOutputManifest.PSObject.Copy()
        $badOutput.ActiveXMLTVStatus='NotGenerated'
        $badOutput.ActiveXMLTVHash=$null
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot (Join-Path $TestDrive 'graph-status') -GenerationManifest $generated.GenerationManifest -AcceptedState $generated.AcceptedState -AcceptedOutputManifest $badOutput -DecisionManifest $generated.DecisionManifest -M3UBytes $generated.M3UBytes -XMLTVBytes $generated.XMLTVBytes } | Should -Throw 'FAIL_CLOSED:*'
    }

    It 'rejects a hardlinked operation lock without changing the outside file' {
        $root=Join-Path $TestDrive 'hardlink-lock'
        $state=Join-Path $root 'state'
        New-Item $state -ItemType Directory -Force | Out-Null
        $outside=Join-Path $TestDrive 'outside-lock'
        [IO.File]::WriteAllText($outside,'outside')
        New-Item -ItemType HardLink -Path (Join-Path $state 'lineup-operation.lock') -Target $outside | Out-Null
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw 'FAIL_CLOSED:*'
        [IO.File]::ReadAllText($outside) | Should -Be 'outside'
    }

    It 'rejects a repository root reached through a reparse point' {
        $realRoot=Join-Path $TestDrive 'reparse-real'
        New-Item $realRoot -ItemType Directory -Force | Out-Null
        $linkRoot=Join-Path $TestDrive 'reparse-link'
        try { New-Item $linkRoot -ItemType SymbolicLink -Target $realRoot -ErrorAction Stop | Out-Null } catch { Set-ItResult -Skipped -Because 'symbolic-link creation is unavailable on this workstation'; return }
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $linkRoot -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'rejects cross-volume authority and staging paths' {
        $drives=@(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -and (Test-Path $_.Root) })
        if ($drives.Count -lt 2) { Set-ItResult -Skipped -Because 'only one filesystem volume is available on this workstation'; return }
        & (Get-Module ChannelForge) {
            param($root,$paths)
            { Assert-ChannelForgeGenerationSameVolume -RepositoryRoot $root -Paths $paths } | Should -Throw 'FAIL_CLOSED:*'
        } $drives[0].Root @($drives[0].Root,$drives[1].Root)
    }

    It 'persists and validates all operational FileIdentity fields without semantic hash coupling' {
        $root=Join-Path $TestDrive 'identity-fields'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes | Out-Null
        $journalPath=Join-Path $root 'state/accepted-lineup.journal.json'
        $journal=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($journalPath)) -AsHashtable -Depth 100
        $identity=$journal.MutationRecords[0].ExpectedNewFileIdentity
        @('VolumeSerial','FileId','ByteLength','LastWriteUtcTicks','NumberOfLinks','IsReparsePoint') | ForEach-Object { $identity.ContainsKey($_) | Should -BeTrue -Because $_ }
        $semanticBefore=& (Get-Module ChannelForge) { param($value) Get-ChannelForgeGenerationIdentityKey $value } $identity
        $operationalVariant=[ordered]@{}; foreach($property in $identity.Keys){$operationalVariant[$property]=$identity[$property]}
        $operationalVariant.NumberOfLinks=99; $operationalVariant.IsReparsePoint=$true
        $semanticAfter=& (Get-Module ChannelForge) { param($left,$right) (Get-ChannelForgeGenerationIdentityKey $left) -eq (Get-ChannelForgeGenerationIdentityKey $right) } $identity $operationalVariant
        $semanticAfter | Should -BeTrue
        $journal.MutationRecords[0].ExpectedNewFileIdentity.NumberOfLinks=2
        $projection=[ordered]@{Version=$journal.Version;TransactionId=$journal.TransactionId;JournalStage=$journal.JournalStage;ExpectedOldPointerHash=$journal.ExpectedOldPointerHash;ExpectedNewPointerHash=$journal.ExpectedNewPointerHash;ExpectedOldGenerationId=$journal.ExpectedOldGenerationId;ExpectedNewGenerationId=$journal.ExpectedNewGenerationId;MutationRecords=$journal.MutationRecords;OldJournalHash=$journal.OldJournalHash}
        $journal.JournalHash=& (Get-Module ChannelForge) { param($projection) Get-ChannelForgeDomainHash -Domain 'journal/v2' -InputObject (ConvertTo-ChannelForgeGenerationCanonicalObject $projection) } $projection
        [IO.File]::WriteAllBytes($journalPath,(& (Get-Module ChannelForge) { param($value) ConvertTo-ChannelForgeGenerationBytes $value } $journal))
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
        $journal.MutationRecords[0].ExpectedNewFileIdentity.NumberOfLinks=1
        $journal.MutationRecords[0].ExpectedNewFileIdentity.IsReparsePoint=$true
        $journal.JournalHash=& (Get-Module ChannelForge) { param($projection) Get-ChannelForgeDomainHash -Domain 'journal/v2' -InputObject (ConvertTo-ChannelForgeGenerationCanonicalObject $projection) } $projection
        [IO.File]::WriteAllBytes($journalPath,(& (Get-Module ChannelForge) { param($value) ConvertTo-ChannelForgeGenerationBytes $value } $journal))
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
    }
    It 'rejects self-valid journal tampering of predecessor and file identity' {
        $root=Join-Path $TestDrive 'journal-tamper'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes | Out-Null
        & (Get-Module ChannelForge) {
            param($path,$mode)
            $j=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -AsHashtable -Depth 100
            if ($mode -eq 'OldJournalHash') { $j.OldJournalHash='0'*64 } else { $j.MutationRecords[0].ExpectedNewFileIdentity.FileId='0'*32 }
            $projection=[ordered]@{Version=$j.Version;TransactionId=$j.TransactionId;JournalStage=$j.JournalStage;ExpectedOldPointerHash=$j.ExpectedOldPointerHash;ExpectedNewPointerHash=$j.ExpectedNewPointerHash;ExpectedOldGenerationId=$j.ExpectedOldGenerationId;ExpectedNewGenerationId=$j.ExpectedNewGenerationId;MutationRecords=$j.MutationRecords;OldJournalHash=$j.OldJournalHash}
            $j.JournalHash=Get-ChannelForgeDomainHash -Domain 'journal/v2' -InputObject (ConvertTo-ChannelForgeGenerationCanonicalObject $projection)
            [IO.File]::WriteAllBytes($path,(ConvertTo-ChannelForgeGenerationBytes $j))
        } (Join-Path $root 'state/accepted-lineup.journal.json') 'OldJournalHash'
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
        & (Get-Module ChannelForge) {
            param($path)
            $j=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -AsHashtable -Depth 100
            $j.MutationRecords[0].ExpectedNewFileIdentity.FileId='0'*32
            $projection=[ordered]@{Version=$j.Version;TransactionId=$j.TransactionId;JournalStage=$j.JournalStage;ExpectedOldPointerHash=$j.ExpectedOldPointerHash;ExpectedNewPointerHash=$j.ExpectedNewPointerHash;ExpectedOldGenerationId=$j.ExpectedOldGenerationId;ExpectedNewGenerationId=$j.ExpectedNewGenerationId;MutationRecords=$j.MutationRecords;OldJournalHash=$j.OldJournalHash}
            $j.JournalHash=Get-ChannelForgeDomainHash -Domain 'journal/v2' -InputObject (ConvertTo-ChannelForgeGenerationCanonicalObject $projection)
        } (Join-Path $root 'state/accepted-lineup.journal.json')
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
    }
    It 'fails closed for malformed predecessors, missing staged pointers, unrelated finals, and extra children' {
        $firstId='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        $secondId='fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
        $previousRoot=Join-Path $TestDrive 'variant-previous'
        $first=New-Issue103Fixture -GenerationId $firstId
        $second=New-Issue103Fixture -GenerationId $secondId -PreviousStateHash $first.AcceptedState.AcceptedStateHash -PreviousOutputManifestHash $first.AcceptedOutputManifest.OutputManifestHash
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $previousRoot -GenerationManifest $first.GenerationManifest -AcceptedState $first.AcceptedState -AcceptedOutputManifest $first.AcceptedOutputManifest -DecisionManifest $first.DecisionManifest -M3UBytes $first.M3UBytes | Out-Null
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $previousRoot -GenerationManifest $second.GenerationManifest -AcceptedState $second.AcceptedState -AcceptedOutputManifest $second.AcceptedOutputManifest -DecisionManifest $second.DecisionManifest -M3UBytes $second.M3UBytes | Out-Null
        $previousPath=Join-Path $previousRoot 'state/accepted-lineup.json.previous'
        $previous=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($previousPath))
        $previous.GenerationId='0'*64
        $previous.PointerHash=& (Get-Module ChannelForge) { param($value) Get-ChannelForgeDomainHash -Domain 'pointer/v2' -InputObject (ConvertTo-ChannelForgeGenerationCanonicalObject $value) } $previous
        [IO.File]::WriteAllText($previousPath,(ConvertTo-Json $previous -Compress -Depth 20))
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $previousRoot } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'

        $stagedRoot=Join-Path $TestDrive 'variant-staged'
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $stagedRoot -GenerationManifest $first.GenerationManifest -AcceptedState $first.AcceptedState -AcceptedOutputManifest $first.AcceptedOutputManifest -DecisionManifest $first.DecisionManifest -M3UBytes $first.M3UBytes -FaultHook 'PointerReplace.Before' } | Should -Throw
        $stagedJournal=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $stagedRoot 'state/accepted-lineup.journal.json')))
        Remove-Item (Join-Path $stagedRoot "state/.staging/$($stagedJournal.TransactionId)/accepted-lineup.json") -Force
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $stagedRoot } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'

        $unrelatedRoot=Join-Path $TestDrive 'variant-unrelated'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $unrelatedRoot -GenerationManifest $first.GenerationManifest -AcceptedState $first.AcceptedState -AcceptedOutputManifest $first.AcceptedOutputManifest -DecisionManifest $first.DecisionManifest -M3UBytes $first.M3UBytes | Out-Null
        $thirdId='00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff'
        $third=New-Issue103Fixture -GenerationId $thirdId -PreviousStateHash $first.AcceptedState.AcceptedStateHash -PreviousOutputManifestHash $first.AcceptedOutputManifest.OutputManifestHash
        $thirdPath=Join-Path $unrelatedRoot "state/generations/$thirdId"
        New-Item $thirdPath -ItemType Directory -Force | Out-Null
        & (Get-Module ChannelForge) {
            param($path,$fixture)
            foreach($entry in @(
                @('generation.manifest.json',(ConvertTo-ChannelForgeGenerationBytes $fixture.GenerationManifest)),
                @('accepted-state.json',(ConvertTo-ChannelForgeGenerationBytes $fixture.AcceptedState)),
                @('accepted-output.manifest.json',(ConvertTo-ChannelForgeGenerationBytes $fixture.AcceptedOutputManifest)),
                @('decision-manifest.json',(ConvertTo-ChannelForgeGenerationBytes $fixture.DecisionManifest)),
                @('merged.m3u',$fixture.M3UBytes)
            )) { [IO.File]::WriteAllBytes((Join-Path $path $entry[0]),[byte[]]$entry[1]) }
        } $thirdPath $third
        (Test-Path $thirdPath) | Should -BeTrue
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $unrelatedRoot -GenerationManifest $second.GenerationManifest -AcceptedState $second.AcceptedState -AcceptedOutputManifest $second.AcceptedOutputManifest -DecisionManifest $second.DecisionManifest -M3UBytes $second.M3UBytes -FaultHook 'GenerationDirectoryMove.Before' } | Should -Throw
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $unrelatedRoot } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'

        $extraRoot=Join-Path $TestDrive 'variant-extra'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $extraRoot -GenerationManifest $first.GenerationManifest -AcceptedState $first.AcceptedState -AcceptedOutputManifest $first.AcceptedOutputManifest -DecisionManifest $first.DecisionManifest -M3UBytes $first.M3UBytes | Out-Null
        $extraGeneration=Join-Path $extraRoot "state/generations/$firstId"
        [IO.File]::WriteAllText((Join-Path $extraGeneration 'unowned.tmp'),'unowned')
        Remove-Item (Join-Path $extraRoot 'state/accepted-lineup.journal.json') -Force
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $extraRoot } | Should -Throw 'FAIL_CLOSED*'
    }
}
