function New-ChannelForgeAcceptanceDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DecisionType,
        [AllowNull()][string]$CandidateEntryId,
        [AllowNull()][string]$BindingId,
        [Parameter(Mandatory)][string]$ReasonCode
    )

    $base = [ordered]@{
        Version = 'blocker-2-contract/v8-acceptance'
        DecisionType = $DecisionType
        CandidateEntryId = $CandidateEntryId
        BindingId = $BindingId
        ReasonCode = $ReasonCode
        ReviewStatus = 'Resolved'
    }
    $base.DecisionId = Get-ChannelForgeDomainHash -Domain 'decision-manifest/v2' -InputObject $base
    return [pscustomobject]$base
}
