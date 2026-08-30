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
    $generation='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    $a='a'*64; $b='b'*64; $c='c'*64
    $m3u=[Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Restart`nhttps://example.invalid/restart`n")
    $m3uHash=Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $m3u
    $m3uDecision=New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
    $decision=New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
    $output=New-ChannelForgeAcceptedOutputManifest -GenerationId $generation -ActiveM3UHash $m3uHash -ActiveXMLTVStatus NotGenerated -ActiveXMLTVHash $null -AcceptedStateHash $b
    $state=New-ChannelForgeAcceptedState -GenerationId $generation -BuildIdentity $b -CandidateManifestHash $a -DecisionManifestHash $decision.DecisionManifestHash -AcceptedOutputManifestHash $output.OutputManifestHash -PreviousStateHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -AcceptedBindingIds @($c) -AcceptedXMLTVStatus NotGenerated -AcceptedAtUtc '2026-08-29T00:00:00Z'
    $output.AcceptedStateHash=$state.AcceptedStateHash
    $manifest=[ordered]@{Version='blocker-2-contract/v8-acceptance';GenerationId=$generation;BuildIdentity=$b;CandidateManifestHash=$a;DecisionManifestHash=$decision.DecisionManifestHash;AcceptedStateHash=$state.AcceptedStateHash;AcceptedOutputManifestHash=$output.OutputManifestHash;ActiveM3UHash=$output.ActiveM3UHash;ActiveXMLTVHash=$null;PreviousOutputManifestHash=$null;GenerationManifestHash=$null}
    $manifest.GenerationManifestHash=Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
    [pscustomobject]@{GenerationManifest=[pscustomobject]$manifest;AcceptedState=$state;AcceptedOutputManifest=$output;DecisionManifest=$decision;M3UBytes=$m3u}
}
Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $RepositoryRoot -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes -FaultHook $FaultHook | Out-Null
