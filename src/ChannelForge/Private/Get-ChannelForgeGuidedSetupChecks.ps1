function Get-ChannelForgeGuidedSetupChecks {
    <#
    .SYNOPSIS
    Builds the logo and category checks shown before a beginner accepts (guided-setup/checks/v1).

    .DESCRIPTION
    Report only. Reads the candidate and returns plain headlines plus the module's own summary
    lines. It never changes the candidate and is never hashed. A failing category report gives
    an 'unavailable' row and no path, URL or id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Candidate,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $accept = 'You can accept, or fix this first (see Details).'
    $checks = [System.Collections.Generic.List[object]]::new()

    $logo = $Candidate.LogoReport
    $missing = [int]$logo.Empty + [int]$logo.NotHttps + [int]$logo.PrivateAddress
    $total = $missing + [int]$logo.Public
    $logoStatus = if ($missing -gt 0) { 'attention' } else { 'ok' }
    $logoHeadline = if ($missing -gt 0) { "$missing of $total channels have no public logo. $accept" } else { 'Every channel has a public logo. Looks fine.' }
    $logoDetails = @(if ($logo.Warning) { [string]$logo.Warning })
    [void]$checks.Add([pscustomobject][ordered]@{ Kind = 'logos'; Status = $logoStatus; Headline = $logoHeadline; Details = $logoDetails })

    try {
        $report = Get-ChannelForgeCategoryReport -CandidateDirectory ([string]$Candidate.CandidateDirectory) -RepositoryRoot $RepositoryRoot
        $lines = @(Get-ChannelForgeCategorySummaryLines -Report $report | Where-Object { $_ -and $_ -notlike '## *' })
        $suspect = @($report.Rows | Where-Object { $_.Decision -ceq 'conflict' -or $_.Confidence -ceq 'medium' }).Count
        $status = if ($suspect -gt 0) { 'attention' } else { 'ok' }
        $headline = if ($suspect -gt 0) { "$suspect channels may be in the wrong category. $accept" } else { 'Channels are sorted into categories. Looks fine.' }
        [void]$checks.Add([pscustomobject][ordered]@{ Kind = 'categories'; Status = $status; Headline = $headline; Details = $lines })
    }
    catch {
        [void]$checks.Add([pscustomobject][ordered]@{ Kind = 'categories'; Status = 'unavailable'; Headline = 'Category check could not run. You can still accept.'; Details = @() })
    }
    return @($checks)
}
