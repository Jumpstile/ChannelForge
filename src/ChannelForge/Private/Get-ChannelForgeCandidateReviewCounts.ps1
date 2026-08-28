function Get-ChannelForgeCandidateReviewCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$RawM3UOccurrences,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$RawXmltvOccurrences,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$BindingProjection
    )

    # These predicates are the frozen v7 review-count domains. Raw counts are
    # source-level evidence counts; status counts are derived from the
    # canonical binding projection emitted by the manifest builder.
    $xmltvChannels = @($RawXmltvOccurrences | Where-Object {
            $null -ne $_.PSObject.Properties['RawChannelIdPresence']
        })

    return [pscustomobject][ordered]@{
        RawM3UOccurrenceCount   = [int]@($RawM3UOccurrences).Count
        RawXMLTVOccurrenceCount = [int]$xmltvChannels.Count
        ExactBindingCount       = [int]@($BindingProjection | Where-Object {
                [string]$_.Status -eq 'ExactBound'
            }).Count
        UnboundCount            = [int]@($BindingProjection | Where-Object {
                [string]$_.BindingKind -eq 'M3U' -and [string]$_.Status -eq 'Unbound'
            }).Count
        ReviewNeededCount       = [int]@($BindingProjection | Where-Object {
                [string]$_.Status -eq 'ReviewNeeded'
            }).Count
        XMLTVOnlyCount          = [int]@($BindingProjection | Where-Object {
                [string]$_.BindingKind -eq 'XMLTVOnly'
            }).Count
    }
}
