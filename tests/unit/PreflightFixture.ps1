function New-Project { $p = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path (Join-Path $p 'output/reports'), (Join-Path $p 'output/cache') | Out-Null; $p }
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
