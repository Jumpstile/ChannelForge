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
}
