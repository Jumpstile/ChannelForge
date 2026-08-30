BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force
    $child = Join-Path $PSScriptRoot 'Issue103ProcessRestart.Child.ps1'
}

Describe 'Issue 103 external process restart recovery' {
    It 'classifies durable-boundary process death without in-process exception recovery' {
        $cases=@(
            [pscustomobject]@{ Hook='JournalAfterReplace.Prepared'; Outcome='OLD'; Stage='Prepared' },
            [pscustomobject]@{ Hook='PointerReplace.AfterBackupMove'; Outcome='NEW'; Stage='PointerSwapped' },
            [pscustomobject]@{ Hook='PointerReplace.After'; Outcome='NEW'; Stage='PointerSwapped' },
            [pscustomobject]@{ Hook='JournalAfterReplace.Committed'; Outcome='NEW'; Stage='Committed' }
        )
        foreach ($case in $cases) {
            $root=Join-Path $TestDrive ($case.Hook -replace '[^A-Za-z0-9]','-')
            $marker=Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ready')
            $psi=[Diagnostics.ProcessStartInfo]::new()
            $psi.FileName=(Get-Command pwsh).Source
            $psi.UseShellExecute=$false
            foreach ($argument in @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$child,'-RepositoryRoot',$root,'-FaultHook',$case.Hook,'-Marker',$marker)) { [void]$psi.ArgumentList.Add($argument) }
            $process=[Diagnostics.Process]::Start($psi)
            try {
                $deadline=[DateTime]::UtcNow.AddSeconds(20)
                while (-not (Test-Path $marker) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
                (Test-Path $marker) | Should -BeTrue -Because "child reached $($case.Hook) before external termination"
            } finally {
                if (-not $process.HasExited) { $process.Kill($true) }
                $process.WaitForExit()
                Remove-Item $marker -Force -ErrorAction SilentlyContinue
            }
            $recovery=Recover-ChannelForgeAcceptedState -RepositoryRoot $root
            $recovery.Outcome | Should -Be $case.Outcome
            $recovery.JournalStage | Should -Be $case.Stage
        }
    }
    It 'externally kills each Generated XMLTV write boundary and preserves fail-closed remnants' {
        foreach ($hook in @('StageWrite.XMLTV','StageFlush.XMLTV','StageReopenHash.XMLTV')) {
            $root=Join-Path $TestDrive ('generated-' + ($hook -replace '[^A-Za-z0-9]','-'))
            $marker=Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ready')
            $psi=[Diagnostics.ProcessStartInfo]::new()
            $psi.FileName=(Get-Command pwsh).Source
            $psi.UseShellExecute=$false
            foreach ($argument in @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$child,'-RepositoryRoot',$root,'-FaultHook',$hook,'-Marker',$marker)) { [void]$psi.ArgumentList.Add($argument) }
            $process=[Diagnostics.Process]::Start($psi)
            try {
                $deadline=[DateTime]::UtcNow.AddSeconds(20)
                while (-not (Test-Path $marker) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
                (Test-Path $marker) | Should -BeTrue -Because "child reached $hook before external termination"
            } finally {
                if (-not $process.HasExited) { $process.Kill($true) }
                $process.WaitForExit()
                Remove-Item $marker -Force -ErrorAction SilentlyContinue
            }
            (Test-Path (Join-Path $root 'state/accepted-lineup.json')) | Should -BeFalse
            (Test-Path (Join-Path $root 'state/accepted-lineup.journal.json')) | Should -BeFalse
            @([IO.Directory]::GetDirectories((Join-Path $root 'state/.staging'))).Count | Should -BeGreaterThan 0
            { Recover-ChannelForgeAcceptedState -RepositoryRoot $root } | Should -Throw 'FAIL_CLOSED_RECOVERY_REQUIRED:*'
        }
    }
    It 'runs the complete A01-A60 external restart classification table' {
        $hookNames=@('StageWrite.GenerationManifest','StageFlush.GenerationManifest','StageReopenHash.GenerationManifest','StageWrite.AcceptedState','StageFlush.AcceptedState','StageReopenHash.AcceptedState','StageWrite.AcceptedOutputManifest','StageFlush.AcceptedOutputManifest','StageReopenHash.AcceptedOutputManifest','StageWrite.DecisionManifest','StageFlush.DecisionManifest','StageReopenHash.DecisionManifest','StageWrite.M3U','StageFlush.M3U','StageReopenHash.M3U','StageWrite.XMLTV','StageFlush.XMLTV','StageReopenHash.XMLTV','JournalWrite.Prepared','JournalFlush.Prepared','JournalReopenHash.Prepared','JournalBeforeReplace.Prepared','JournalAfterReplace.Prepared','GenerationDirectoryMove.Before','GenerationDirectoryMove.After','JournalBeforeReplace.GenerationPublished','JournalAfterReplace.GenerationPublished','PointerReplace.Before','PointerReplace.After','JournalBeforeReplace.PointerSwapped','JournalAfterReplace.PointerSwapped','VerifyCurrentPointer.Before','VerifyCurrentPointer.After','JournalBeforeReplace.Committed','JournalAfterReplace.Committed','CleanupDelete.GenerationStage.Before','CleanupDelete.GenerationStage.After','CleanupDelete.PointerJournalBackup.Before','CleanupDelete.PointerJournalBackup.After','CleanupDelete.TransactionDirectory.Before','CleanupDelete.TransactionDirectory.After','Verify.GenerationManifest.Before','Verify.GenerationManifest.After','Verify.AcceptedState.Before','Verify.AcceptedState.After','Verify.OutputManifest.Before','Verify.OutputManifest.After','Verify.M3U.Before','Verify.M3U.After','Verify.XMLTV.Before','Verify.XMLTV.After','JournalStageWrite.GenerationPublished','JournalStageFlush.GenerationPublished','JournalStageReopenHash.GenerationPublished','JournalStageWrite.PointerSwapped','JournalStageFlush.PointerSwapped','JournalStageReopenHash.PointerSwapped','JournalStageWrite.Committed','JournalStageFlush.Committed','JournalStageReopenHash.Committed')
        $cases=@()
        foreach($index in 1..60) {
            $classification='FAIL_CLOSED_RECOVERY_REQUIRED'; $current=$false; $previous=$false; $journal=$false
            if($index -in @(23,24)){ $classification='OLD/Prepared'; $journal=$true }
            elseif($index -in @(27,28,29,55)){ $classification='NEW/PointerSwapped'; $current=$true; $journal=$true }
            elseif($index -in @(31,35,36,37,38,39,40,41,58)){ $classification='NEW/Committed'; $current=$true; $journal=$true }
            elseif($index -in @(32,33,42,43,44,45,46,47,48,49,50,51)){ $classification='INITIAL_BASELINE_REQUIRED/'; $journal=$false }
            elseif($index -in @(25,26,52,53,54)){ $journal=$true }
            elseif($index -in @(30,34,56,57,59,60)){ $current=$true; $journal=$true }
            $cases += [pscustomobject]@{Case=('A{0:D2}' -f $index);Hook=$hookNames[$index-1];Classification=$classification;Current=$current;Previous=$previous;Journal=$journal;Staging=$true}
        }
        foreach($case in $cases) {
            $root=Join-Path $TestDrive ('matrix-' + $case.Case)
            $marker=Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ready')
            $psi=[Diagnostics.ProcessStartInfo]::new(); $psi.FileName=(Get-Command pwsh).Source; $psi.UseShellExecute=$false
            foreach($argument in @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$child,'-RepositoryRoot',$root,'-FaultHook',$case.Hook,'-Marker',$marker)){[void]$psi.ArgumentList.Add($argument)}
            $process=[Diagnostics.Process]::Start($psi)
            try {
                $deadline=[DateTime]::UtcNow.AddSeconds(20)
                while(-not(Test-Path $marker) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
                (Test-Path $marker) | Should -BeTrue -Because "child reached $($case.Case) $($case.Hook)"
            } finally {
                if(-not $process.HasExited){$process.Kill($true)}
                $process.WaitForExit(); Remove-Item $marker -Force -ErrorAction SilentlyContinue
            }
            $actualClassification=''
            try { $recovery=Recover-ChannelForgeAcceptedState -RepositoryRoot $root; $actualClassification="$($recovery.Outcome)/$($recovery.JournalStage)" } catch { $actualClassification=$_.Exception.Message.Split("`n")[0].Trim() }
            if($actualClassification -like 'FAIL_CLOSED_RECOVERY_REQUIRED:*'){$actualClassification='FAIL_CLOSED_RECOVERY_REQUIRED'}
            $actualClassification | Should -Be $case.Classification -Because $case.Case
            $state=Join-Path $root 'state'
            (Test-Path (Join-Path $state 'accepted-lineup.json')) | Should -Be $case.Current -Because "$($case.Case) current"
            (Test-Path (Join-Path $state 'accepted-lineup.json.previous')) | Should -Be $case.Previous -Because "$($case.Case) previous"
            (Test-Path (Join-Path $state 'accepted-lineup.journal.json')) | Should -Be $case.Journal -Because "$($case.Case) journal"
            (Test-Path (Join-Path $state '.staging')) | Should -Be $case.Staging -Because "$($case.Case) staging"
        }
    }
}
