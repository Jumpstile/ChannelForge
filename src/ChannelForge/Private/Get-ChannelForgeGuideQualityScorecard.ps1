function Get-ChannelForgeGuideQualityScorecard {
    <#
    .SYNOPSIS
    Turns the outputs of existing guide reports into six quality gates (guide-quality-scorecard/v1). Pure, report only.

    .DESCRIPTION
    Contract:
    - Inputs are report objects that already exist. Nothing is read from disk, written, merged or changed.
      XguideReport = Get-ChannelForgeXguideReport; CategoryReport = Get-ChannelForgeCategoryReport;
      ReadinessResult = Get-ChannelForgeGuideReadiness; Programme = programme rows (ChannelId or RawChannelId, Start,
      Title, optional CanonicalEventId).
    - Gates: Accuracy, Completeness, Freshness, Deduplication, Classification, Availability.
      Each gate has Name, Verdict, Counts (plain numbers) and Reason (one line).
    - Verdict rule: any Fail-level finding gives Fail; else any Review-level finding gives Review; else Pass.
      A gate whose input was not supplied is NotMeasured, never Pass. No percentages.
        Accuracy:       Fail = readiness Contradiction. Review = xguide TitleDiffers or StartShift.
        Completeness:   Fail = a guide with no programmes. Review = xguide MissingChannel.
        Freshness:      Fail = a guide that ended before the build. Review = a guide more than 24 h behind, or readiness StaleSource.
        Deduplication:  Review = channels with the same title and start time and no CanonicalEventId. Count only, nothing is merged.
        Classification: Review = any ambiguous (conflict) or unknown (no-rule) channel. An ambiguous category is never Pass.
        Availability:   Fail = readiness SourceUnavailable. Review = readiness Unresolved.
    - Overall = the worst gate verdict (Fail, then Review). NotMeasured counts as Review for Overall.
    - Totals carry the input channel counts so a caller can prove no channel was dropped.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$XguideReport = $null,
        [AllowNull()][object]$CategoryReport = $null,
        [AllowNull()][object]$ReadinessResult = $null,
        [AllowNull()][object[]]$Programme = $null
    )

    function New-Gate([string]$Name, [bool]$Measured, [System.Collections.IDictionary]$Counts, [string[]]$Fail, [string[]]$Review) {
        $Fail = @($Fail | Where-Object { $_ })
        $Review = @($Review | Where-Object { $_ })
        if (-not $Measured) { $verdict = 'NotMeasured'; $reason = 'No report was supplied for this gate, so nothing is claimed.' }
        elseif ($Fail.Count -gt 0) { $verdict = 'Fail'; $reason = $Fail -join '; ' }
        elseif ($Review.Count -gt 0) { $verdict = 'Review'; $reason = $Review -join '; ' }
        else { $verdict = 'Pass'; $reason = 'No problems found in the supplied report.' }
        [pscustomobject][ordered]@{ Name = $Name; Verdict = $verdict; Counts = [pscustomobject]$Counts; Reason = $reason }
    }
    function Get-Number($Source, [string]$Name) { if ($null -eq $Source) { 0 } else { [int]$Source.$Name } }
    function Get-DuplicateGroupCount([object[]]$Rows) {
        $groups = @{}
        foreach ($p in $Rows) {
            $channel = if ([string]::IsNullOrEmpty($p.RawChannelId)) { [string]$p.ChannelId } else { [string]$p.RawChannelId }
            $identity = $p.PSObject.Properties['CanonicalEventId']
            if ($identity -and -not [string]::IsNullOrWhiteSpace([string]$identity.Value)) { continue }
            $key = '{0}|{1}' -f ([regex]::Replace(([string]$p.Title).Trim().ToLowerInvariant(), '\s+', ' ')), $p.Start.UtcTicks
            if (-not $groups.ContainsKey($key)) { $groups[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
            [void]$groups[$key].Add($channel)
        }
        @($groups.Values | Where-Object { $_.Count -gt 1 }).Count
    }

    $x = $XguideReport; $r = $ReadinessResult
    $xCounts = if ($x) { $x.Counts } else { $null }
    $rCounts = if ($r) { $r.StateCounts } else { $null }
    $guides = if ($x) { @($x.Guides) } else { @() }
    $ended = @($guides | Where-Object { $_.State -ceq 'ended' }).Count
    $empty = @($guides | Where-Object { $_.State -ceq 'empty' }).Count
    $behind = [math]::Max(0, (Get-Number $xCounts 'GuideBehind') - $ended - $empty)
    $titleDiffers = Get-Number $xCounts 'TitleDiffers'; $startShift = Get-Number $xCounts 'StartShift'
    $contradiction = Get-Number $rCounts 'Contradiction'; $stale = Get-Number $rCounts 'StaleSource'
    $unavailable = Get-Number $rCounts 'SourceUnavailable'; $unresolved = Get-Number $rCounts 'Unresolved'
    $missing = Get-Number $xCounts 'MissingChannel'

    $rows = if ($CategoryReport) { @($CategoryReport.Rows) } else { @() }
    $ambiguous = @($rows | Where-Object { $_.Decision -ceq 'conflict' }).Count
    $unknown = @($rows | Where-Object { $_.Decision -ceq 'no-rule' }).Count
    $high = @($rows | Where-Object { $_.Confidence -ceq 'high' }).Count
    $dupGroups = if ($null -ne $Programme) { Get-DuplicateGroupCount @($Programme) } else { 0 }

    $gates = @(
        New-Gate 'Accuracy' ($null -ne $x -or $null -ne $r) ([ordered]@{ TitleDiffers = $titleDiffers; StartShift = $startShift; Contradiction = $contradiction }) `
        @(if ($contradiction) { "$contradiction readiness contradictions" }) `
        @(if ($titleDiffers + $startShift) { "$titleDiffers title and $startShift start-time differences between guides" })
        New-Gate 'Completeness' ($null -ne $x) ([ordered]@{ MissingChannel = $missing; EmptyGuides = $empty }) `
        @(if ($empty) { "$empty guides have no programmes" }) `
        @(if ($missing) { "$missing channels are missing from some guides" })
        New-Gate 'Freshness' ($null -ne $x -or $null -ne $r) ([ordered]@{ EndedGuides = $ended; BehindGuides = $behind; StaleSource = $stale }) `
        @(if ($ended) { "$ended guides ended before this build" }) `
        @(if ($behind + $stale) { "$behind guides behind and $stale stale sources" })
        New-Gate 'Deduplication' ($null -ne $Programme) ([ordered]@{ DuplicateGroups = $dupGroups }) `
        @() @(if ($dupGroups) { "$dupGroups same-title same-time groups on different channels with no canonical identity" })
        New-Gate 'Classification' ($null -ne $CategoryReport) ([ordered]@{ High = $high; Ambiguous = $ambiguous; Unknown = $unknown }) `
        @() @(if ($ambiguous + $unknown) { "$ambiguous ambiguous and $unknown unknown channels" })
        New-Gate 'Availability' ($null -ne $r) ([ordered]@{ SourceUnavailable = $unavailable; Unresolved = $unresolved }) `
        @(if ($unavailable) { "$unavailable guide records have an unavailable source" }) `
        @(if ($unresolved) { "$unresolved guide records are unresolved" })
    )

    $overall = 'Pass'
    if (@($gates | Where-Object { $_.Verdict -in @('Review', 'NotMeasured') }).Count -gt 0) { $overall = 'Review' }
    if (@($gates | Where-Object { $_.Verdict -ceq 'Fail' }).Count -gt 0) { $overall = 'Fail' }

    return [pscustomobject][ordered]@{
        SchemaVersion = 'guide-quality-scorecard/v1'
        Overall       = $overall
        Totals        = [pscustomobject][ordered]@{
            CategoryChannelCount   = if ($CategoryReport) { [int]$CategoryReport.ChannelCount } else { $null }
            XguideSharedChannels   = if ($x) { [int]$x.SharedChannelCount } else { $null }
            ReadinessRecordCount   = if ($r) { @($r.Records).Count } else { $null }
            ProgrammeCount         = if ($null -ne $Programme) { @($Programme).Count } else { $null }
        }
        Gates         = $gates
    }
}
