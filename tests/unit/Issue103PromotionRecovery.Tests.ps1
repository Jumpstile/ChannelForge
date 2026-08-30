BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force

    function New-Issue103Fixture {
        param([Parameter(Mandatory)][string]$GenerationId,[switch]$Generated,[AllowNull()][string]$PreviousStateHash)
        & (Get-Module ChannelForge) {
            param($GenerationId,$Generated,$PreviousStateHash)
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
            $manifest=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$GenerationId;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedStateHash=$state.AcceptedStateHash;AcceptedOutputManifestHash=$output.OutputManifestHash;GenerationManifestHash=$null}
            $manifest.GenerationManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
            [pscustomobject]@{GenerationManifest=[pscustomobject]$manifest;AcceptedState=[pscustomobject]$state;AcceptedOutputManifest=[pscustomobject]$output;DecisionManifest=$decision;M3UBytes=$m3u;XMLTVBytes=$xml}
        } $GenerationId ([bool]$Generated) $PreviousStateHash
    }
}

Describe 'Issue 103 immutable generation promotion and recovery' {
    It 'publishes a first immutable NotGenerated generation and classifies it valid after restart' {
        $root=Join-Path $TestDrive 'first'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef'
        $result=Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes
        $result.Outcome | Should -Be 'NEW'
        (Test-Path (Join-Path $root 'state/accepted-lineup.json')) | Should -BeTrue
        (Test-Path (Join-Path $root 'state/accepted-lineup.json.previous')) | Should -BeFalse
        (Test-Path (Join-Path $root 'state/generations/0123456789abcdef0123456789abcdef/merged.xml')) | Should -BeFalse
        $recovery=Recover-ChannelForgeAcceptedState -RepositoryRoot $root
        $recovery.Outcome | Should -Be 'NEW'
        $recovery.JournalStage | Should -Be 'Committed'
    }

    It 'replaces the pointer atomically and preserves exact previous pointer bytes' {
        $root=Join-Path $TestDrive 'second'
        $first=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $first.GenerationManifest -AcceptedState $first.AcceptedState -AcceptedOutputManifest $first.AcceptedOutputManifest -DecisionManifest $first.DecisionManifest -M3UBytes $first.M3UBytes -XMLTVBytes $first.XMLTVBytes | Out-Null
        $oldBytes=[IO.File]::ReadAllBytes((Join-Path $root 'state/accepted-lineup.json'))
        $second=New-Issue103Fixture -GenerationId 'fedcba9876543210fedcba9876543210' -PreviousStateHash $first.AcceptedState.AcceptedStateHash
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $second.GenerationManifest -AcceptedState $second.AcceptedState -AcceptedOutputManifest $second.AcceptedOutputManifest -DecisionManifest $second.DecisionManifest -M3UBytes $second.M3UBytes -XMLTVBytes $second.XMLTVBytes | Out-Null
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'state/accepted-lineup.json.previous'))) | Should -Be ([Convert]::ToBase64String($oldBytes))
        (Get-Content (Join-Path $root 'state/accepted-lineup.json') -Raw) | Should -Match 'fedcba9876543210fedcba9876543210'
        (Get-Content (Join-Path $root 'output/merged.m3u') -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'stages Generated XMLTV only when the output status is Generated' {
        $root=Join-Path $TestDrive 'xml'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef' -Generated
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes | Out-Null
        (Test-Path (Join-Path $root 'state/generations/0123456789abcdef0123456789abcdef/merged.xml')) | Should -BeTrue
    }

    It 'fails closed on every named runtime fault boundary' {
        $hooks=@('A01 StageWrite.GenerationManifest','A02 StageFlush.GenerationManifest','A03 StageReopenHash.GenerationManifest','A04 StageWrite.AcceptedState','A05 StageFlush.AcceptedState','A06 StageReopenHash.AcceptedState','A07 StageWrite.AcceptedOutputManifest','A08 StageFlush.AcceptedOutputManifest','A09 StageReopenHash.AcceptedOutputManifest','A10 StageWrite.DecisionManifest','A11 StageFlush.DecisionManifest','A12 StageReopenHash.DecisionManifest','A13 StageWrite.M3U','A14 StageFlush.M3U','A15 StageReopenHash.M3U','A19 JournalWrite.Prepared','A20 JournalFlush.Prepared','A21 JournalReopenHash.Prepared','A22 JournalBeforeReplace.Prepared','A23 JournalAfterReplace.Prepared','A24 GenerationDirectoryMove.Before','A25 GenerationDirectoryMove.After','A26 JournalBeforeReplace.GenerationPublished','A27 JournalAfterReplace.GenerationPublished','A28 PointerReplace.Before','A29 PointerReplace.After','A30 JournalBeforeReplace.PointerSwapped','A31 JournalAfterReplace.PointerSwapped','A32 VerifyCurrentPointer.Before','A33 VerifyCurrentPointer.After','A34 JournalBeforeReplace.Committed','A35 JournalAfterReplace.Committed','A36 CleanupDelete.GenerationStage.Before','A37 CleanupDelete.GenerationStage.After','A38 CleanupDelete.PointerJournalBackup.Before','A39 CleanupDelete.PointerJournalBackup.After','A40 CleanupDelete.TransactionDirectory.Before','A41 CleanupDelete.TransactionDirectory.After','A42 Verify.GenerationManifest.Before','A43 Verify.GenerationManifest.After','A44 Verify.AcceptedState.Before','A45 Verify.AcceptedState.After','A46 Verify.OutputManifest.Before','A47 Verify.OutputManifest.After','A48 Verify.M3U.Before','A49 Verify.M3U.After','A50 Verify.XMLTV.Before','A51 Verify.XMLTV.After','A52 JournalStageWrite.GenerationPublished','A53 JournalStageFlush.GenerationPublished','A54 JournalStageReopenHash.GenerationPublished','A55 JournalStageWrite.PointerSwapped','A56 JournalStageFlush.PointerSwapped','A57 JournalStageReopenHash.PointerSwapped','A58 JournalStageWrite.Committed','A59 JournalStageFlush.Committed','A60 JournalStageReopenHash.Committed')
        foreach ($item in $hooks) {
            $parts=$item -split ' ',2; $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef' -Generated
            { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $root -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes -FaultHook $parts[1] } | Should -Throw
        }
    }

    It 'returns INITIAL_BASELINE_REQUIRED for an empty store and FAIL_CLOSED for malformed authority' {
        $empty=Join-Path $TestDrive 'empty'; (Recover-ChannelForgeAcceptedState -RepositoryRoot $empty).Outcome | Should -Be 'INITIAL_BASELINE_REQUIRED'
        $bad=Join-Path $TestDrive 'bad'; New-Item (Join-Path $bad 'state') -ItemType Directory -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $bad 'state/accepted-lineup.json'),'{}')
        { Recover-ChannelForgeAcceptedState -RepositoryRoot $bad } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
        $valid=Join-Path $TestDrive 'nojournal'; $vf=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef'
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $valid -GenerationManifest $vf.GenerationManifest -AcceptedState $vf.AcceptedState -AcceptedOutputManifest $vf.AcceptedOutputManifest -DecisionManifest $vf.DecisionManifest -M3UBytes $vf.M3UBytes | Out-Null
        Remove-Item (Join-Path $valid 'state/accepted-lineup.journal.json')
        (Recover-ChannelForgeAcceptedState -RepositoryRoot $valid).Outcome | Should -Be 'ACCEPTED_STATE_VALID'
    }
    It 'resolves pointer-swap and committed-journal interruption to coherent NEW state' {
        $root=Join-Path $TestDrive 'restart'
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef'
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
        $fixture=New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef'
        $bad=[pscustomobject]$fixture.GenerationManifest.PSObject.Copy(); $bad.GenerationId='A'*32
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot (Join-Path $TestDrive 'identity') -GenerationManifest $bad -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw 'FAIL_CLOSED:*'
        { Publish-ChannelForgeAcceptedGeneration -RepositoryRoot '\\server\share\clone' -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes } | Should -Throw
    }
}
