BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force

    function New-Project { $p = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path (Join-Path $p 'output/reports'), (Join-Path $p 'output/cache') | Out-Null; $p }
    function Get-Snapshot([string]$Root) { @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object { '{0}|{1}' -f $_.FullName, $(if ($_.PSIsContainer) { 'dir' } else { (Get-FileHash -LiteralPath $_.FullName).Hash }) }) }
    function Get-Finding($Report, [string]$Check) { @($Report.Findings | Where-Object { $_.Check -eq $Check }) }
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
    function Publish-Fixture([string]$Root) {
        $f = New-Issue103Fixture -GenerationId '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' -Generated
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $Root -GenerationManifest $f.GenerationManifest -AcceptedState $f.AcceptedState -AcceptedOutputManifest $f.AcceptedOutputManifest -DecisionManifest $f.DecisionManifest -M3UBytes $f.M3UBytes -XMLTVBytes $f.XMLTVBytes | Out-Null
        Join-Path $Root 'state/generations/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    }
}

Describe 'Get-ChannelForgePreflightReport' {
    It 'passes a healthy project and leaves the roots exactly as they were' {
        $p = New-Project
        Set-Content -LiteralPath (Join-Path $p 'output/reports/keep.txt') -Value 'keep'
        $before = Get-Snapshot $p
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p
        $r.Version | Should -Be 'preflight-report/v1'
        @($r.Findings | Where-Object { $_.Status -eq 'Fail' }).Count | Should -Be 0
        (Get-Finding $r 'OutputRoot writable').Status | Should -Be 'Pass'
        Get-Snapshot $p | Should -Be $before
        Test-Path -LiteralPath (Join-Path $p 'output/reports/.preflight') | Should -BeFalse
    }

    It 'fails a missing root with a next step and does not create it' {
        $p = New-Project
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p -BackupRoot (Join-Path $p 'backups')
        $f = Get-Finding $r 'BackupRoot exists'
        $f.Status | Should -Be 'Fail'
        $f.NextStep | Should -Not -BeNullOrEmpty
        $r.Summary.Overall | Should -Be 'Fail'
        Test-Path -LiteralPath (Join-Path $p 'backups') | Should -BeFalse
    }

    It 'fails a root outside the project' {
        $p = New-Project
        $other = Join-Path $TestDrive 'elsewhere'; New-Item -ItemType Directory -Path $other | Out-Null
        (Get-Finding (Get-ChannelForgePreflightReport -RepositoryRoot $p -OutputRoot $other) 'OutputRoot inside project').Status | Should -Be 'Fail'
    }

    It 'fails an unwritable root and removes nothing of the user''s' {
        $p = New-Project
        New-Item -ItemType File -Path (Join-Path $p 'output/reports/.preflight') | Out-Null
        $f = Get-Finding (Get-ChannelForgePreflightReport -RepositoryRoot $p) 'OutputRoot writable'
        $f.Status | Should -Be 'Fail'
        $f.NextStep | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $p 'output/reports/.preflight') | Should -BeTrue
    }

    It 'fails when the free-space floor is larger than the drive' {
        $p = New-Project
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p -MinimumFreeSpaceMB 1000000000
        (Get-Finding $r 'OutputRoot free space').Status | Should -Be 'Fail'
    }

    It 'fails a root that is a junction' {
        $p = New-Project
        $target = Join-Path $TestDrive 'target'; New-Item -ItemType Directory -Path $target | Out-Null
        $link = Join-Path $p 'linked'
        try { New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null } catch { Set-ItResult -Skipped -Because 'this process cannot create a junction'; return }
        (Get-Finding (Get-ChannelForgePreflightReport -RepositoryRoot $p -OutputRoot $link) 'OutputRoot no link').Status | Should -Be 'Fail'
    }

    It 'reports Unknown, not Pass, when nothing is published yet' {
        $r = Get-ChannelForgePreflightReport -RepositoryRoot (New-Project)
        (Get-Finding $r 'published M3U matches manifest').Status | Should -Be 'Unknown'
        (Get-Finding $r 'published XMLTV matches manifest').Status | Should -Be 'Unknown'
        $r.Summary.Overall | Should -Be 'Unknown'
    }

    It 'passes matching published files and fails a changed byte' {
        $p = New-Project
        $generation = Publish-Fixture $p
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p
        (Get-Finding $r 'published M3U matches manifest').Status | Should -Be 'Pass'
        (Get-Finding $r 'published XMLTV matches manifest').Status | Should -Be 'Pass'
        $m3u = Join-Path $generation 'merged.m3u'
        Set-ItemProperty -LiteralPath $m3u -Name IsReadOnly -Value $false
        [IO.File]::AppendAllText($m3u, 'x')
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p
        (Get-Finding $r 'published M3U matches manifest').Status | Should -Be 'Fail'
        $r.Summary.Overall | Should -Be 'Fail'
    }
}
