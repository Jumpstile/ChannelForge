function Get-ChannelForgeGuideQualityReport {
    <#
    .SYNOPSIS
    Shows six guide quality gates (accuracy, completeness, freshness, deduplication, classification, availability) in one report.

    .DESCRIPTION
    Read-only report (contract guide-quality-scorecard/v1). Pass in the outputs of the existing reports:
    Get-ChannelForgeXguideReport, Get-ChannelForgeCategoryReport, Get-ChannelForgeGuideReadiness and the programme rows.
    A gate with no input is NotMeasured, never Pass. It writes nothing and changes nothing.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$XguideReport = $null,
        [AllowNull()][object]$CategoryReport = $null,
        [AllowNull()][object]$ReadinessResult = $null,
        [AllowNull()][object[]]$Programme = $null
    )

    return Get-ChannelForgeGuideQualityScorecard -XguideReport $XguideReport -CategoryReport $CategoryReport -ReadinessResult $ReadinessResult -Programme $Programme
}
