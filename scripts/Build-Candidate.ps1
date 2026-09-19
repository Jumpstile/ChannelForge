param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ProviderPath,
    [string]$M3UPath,
    [string]$XMLTVPath,
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'output'),
    [string]$TransactionId = ([guid]::NewGuid().ToString('N').ToLowerInvariant()),
    [string]$FaultHook = '',
    [string]$CandidateContractVersion = 'blocker-2-contract/v7',
    [switch]$EmitEntrySlices
)
$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Parent $PSScriptRoot
if ($CandidateContractVersion -notin @('blocker-2-contract/v7','blocker-2-contract/v8')) { throw 'FAIL_CLOSED: unsupported CandidateContractVersion' }
if ($EmitEntrySlices -and $PSBoundParameters.ContainsKey('CandidateContractVersion') -and $CandidateContractVersion -eq 'blocker-2-contract/v7') { throw 'FAIL_CLOSED: explicit blocker-2-contract/v7 cannot be combined with -EmitEntrySlices.' }
if ($EmitEntrySlices -and -not $PSBoundParameters.ContainsKey('CandidateContractVersion')) { throw 'FAIL_CLOSED: candidate-v8 registry migration requires explicit -CandidateContractVersion blocker-2-contract/v8.' }
Import-Module (Join-Path $ModuleRoot 'src\ChannelForge\ChannelForge.psd1') -Force
New-ChannelForgeCandidateProposal -Root $Root -ProviderPath $ProviderPath -M3UPath $M3UPath -XMLTVPath $XMLTVPath -OutputRoot $OutputRoot -TransactionId $TransactionId -FaultHook $FaultHook -CandidateContractVersion $CandidateContractVersion -EmitEntrySlices:$EmitEntrySlices
