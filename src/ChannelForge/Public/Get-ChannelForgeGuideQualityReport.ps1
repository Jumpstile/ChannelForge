function Get-ChannelForgeGuideQualityReport {
    <#
    .SYNOPSIS
    Shows six guide quality gates (accuracy, completeness, freshness, deduplication, classification, availability) in one report.

    .DESCRIPTION
    Read-only report (contract guide-quality-scorecard/v1). Pass in the outputs of the existing reports:
    Get-ChannelForgeXguideReport, Get-ChannelForgeCategoryReport, Get-ChannelForgeGuideReadiness and the programme rows.
    Optional PlaylistGuideId = the tvg-id of each playlist channel; it lets Completeness count playlist channels with no programmes.
    A gate with no input, or that compared nothing, is NotMeasured, never Pass. It writes nothing and changes nothing.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$XguideReport = $null,
        [AllowNull()][object]$CategoryReport = $null,
        [AllowNull()][object]$ReadinessResult = $null,
        [AllowNull()][object[]]$Programme = $null,
        [AllowNull()][string[]]$PlaylistGuideId = $null
    )

    return Get-ChannelForgeGuideQualityScorecard -XguideReport $XguideReport -CategoryReport $CategoryReport -ReadinessResult $ReadinessResult -Programme $Programme -PlaylistGuideId $PlaylistGuideId
}
