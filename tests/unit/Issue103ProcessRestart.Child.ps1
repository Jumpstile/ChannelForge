param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$FaultHook,
    [Parameter(Mandatory)][string]$Marker
)
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force
$env:CHANNELFORGE_TEST_MODE = '1'
$env:CHANNELFORGE_TEST_HOLD_AT = $FaultHook
$env:CHANNELFORGE_TEST_HOLD_MARKER = $Marker
    $fixture = & (Get-Module ChannelForge) {
        param($RepositoryRoot)
    $generation='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    $a='a'*64; $b='b'*64; $c='c'*64
    $m3u=[Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Channel $generation`nhttps://example.invalid/$generation`n")
    $m3uHash=Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $m3u
    $m3uDecision=New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
    $xmlDecision=New-ChannelForgeDecisionXMLTV -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -AcceptedXMLTVStatus Generated -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
    $decision=New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $xmlDecision -XMLTVDecisionStatus Generated
    $xml=[Text.Encoding]::UTF8.GetBytes('<?xml version="1.0" encoding="UTF-8"?><tv></tv>')
    $xmlHash=Get-ChannelForgeDomainHash -Domain 'active-xmltv/v2' -Bytes $xml
    $output=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;ActiveM3UHash=$m3uHash;ActiveXMLTVStatus='Generated';ActiveXMLTVHash=$xmlHash;AcceptedStateHash=$b;OutputManifestHash=$null}
    $output.OutputManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'previous-output-manifest/v2' -Projection $output -HashProperty OutputManifestHash -Omit @('GenerationId','AcceptedStateHash')
    $state=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedOutputManifestHash=$output.OutputManifestHash;PreviousStateHash=$null;IncludedCandidateEntryIds=@($a);ExcludedCandidateEntryIds=@($b);AcceptedBindingIds=@($c);AcceptedXMLTVStatus='Generated';AcceptedAtUtc='2026-08-29T00:00:00Z';AcceptedStateHash=$null}
    $state.AcceptedStateHash=Get-ChannelForgeAcceptanceHash -Domain 'accepted-state/v2' -Projection $state -HashProperty AcceptedStateHash -Omit @('GenerationId','AcceptedAtUtc')
    $output.AcceptedStateHash=$state.AcceptedStateHash
    $manifest=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedStateHash=$state.AcceptedStateHash;AcceptedOutputManifestHash=$output.OutputManifestHash;ActiveM3UHash=$output.ActiveM3UHash;ActiveXMLTVHash=$output.ActiveXMLTVHash;PreviousOutputManifestHash=$null;GenerationManifestHash=$null}
    $manifest.GenerationManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
    $baseline=[pscustomobject]@{GenerationManifest=[pscustomobject]$manifest;AcceptedState=$state;AcceptedOutputManifest=$output;DecisionManifest=$decision;M3UBytes=$m3u;XMLTVBytes=$xml}
    $fixture=$baseline
    if ($FaultHook -eq 'PointerReplace.AfterBackupMove') {
        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $RepositoryRoot -GenerationManifest $baseline.GenerationManifest -AcceptedState $baseline.AcceptedState -AcceptedOutputManifest $baseline.AcceptedOutputManifest -DecisionManifest $baseline.DecisionManifest -M3UBytes $baseline.M3UBytes -XMLTVBytes $baseline.XMLTVBytes | Out-Null
        $generation='fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'
        $m3u=[Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Channel $generation`nhttps://example.invalid/$generation`n")
        $m3uHash=Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $m3u
        $m3uDecision=New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $baseline.GenerationManifest.GenerationManifestHash -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
        $xmlDecision=New-ChannelForgeDecisionXMLTV -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $baseline.GenerationManifest.GenerationManifestHash -AcceptedXMLTVStatus Generated -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
        $decision=New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $xmlDecision -XMLTVDecisionStatus Generated
        $output=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;ActiveM3UHash=$m3uHash;ActiveXMLTVStatus='Generated';ActiveXMLTVHash=$xmlHash;AcceptedStateHash=$b;OutputManifestHash=$null}
        $output.OutputManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'previous-output-manifest/v2' -Projection $output -HashProperty OutputManifestHash -Omit @('GenerationId','AcceptedStateHash')
        $state=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedOutputManifestHash=$output.OutputManifestHash;PreviousStateHash=$baseline.AcceptedState.AcceptedStateHash;IncludedCandidateEntryIds=@($a);ExcludedCandidateEntryIds=@($b);AcceptedBindingIds=@($c);AcceptedXMLTVStatus='Generated';AcceptedAtUtc='2026-08-29T00:00:00Z';AcceptedStateHash=$null}
        $state.AcceptedStateHash=Get-ChannelForgeAcceptanceHash -Domain 'accepted-state/v2' -Projection $state -HashProperty AcceptedStateHash -Omit @('GenerationId','AcceptedAtUtc')
        $output.AcceptedStateHash=$state.AcceptedStateHash
        $manifest=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedStateHash=$state.AcceptedStateHash;AcceptedOutputManifestHash=$output.OutputManifestHash;ActiveM3UHash=$output.ActiveM3UHash;ActiveXMLTVHash=$output.ActiveXMLTVHash;PreviousOutputManifestHash=$baseline.AcceptedOutputManifest.OutputManifestHash;GenerationManifestHash=$null}
        $manifest.GenerationManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
        $fixture=[pscustomobject]@{GenerationManifest=[pscustomobject]$manifest;AcceptedState=[pscustomobject]$state;AcceptedOutputManifest=[pscustomobject]$output;DecisionManifest=$decision;M3UBytes=$m3u;XMLTVBytes=$xml}
    }
    $fixture
} $RepositoryRoot
Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $RepositoryRoot -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -XMLTVBytes $fixture.XMLTVBytes -FaultHook $FaultHook | Out-Null
