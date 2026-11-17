function ConvertTo-ChannelForgeGuideEvidenceFromPlaylist {
    <#
    .SYNOPSIS
    Turns playlist channels plus one guide's programme rows into GuideEvidenceRecord objects for Get-ChannelForgeGuideReadiness. Pure, read only.

    .DESCRIPTION
    One record per channel, built with New-ChannelForgeGuideEvidence. Nothing is invented from programme text.
    - Channel has programmes: XMLTV evidence. StartUtc/EndUtc is the span the guide covers for that channel.
      The guide is Stale when that span ended before BuildTimeUtc, else Current. State is SafeCandidate:
      one source, never cross-checked. Source relationship stays Unknown.
    - Channel has no programmes (or no tvg-id): ProviderM3UMetadata evidence, Unresolved, reasons
      EvidenceMissing and NoEventData. It is never dropped.
    - Title is the channel display name, so each channel is one readiness group. Programme titles are not used.
    Channels are sorted first, so the result does not depend on input order.
    Programme rows: ChannelId or RawChannelId, Start, End (as read by Read-ChannelForgeXmltvSourceFile).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Channel = @(),
        [AllowEmptyCollection()][object[]]$Programme = @(),
        [Parameter(Mandatory)][datetime]$BuildTimeUtc,
        [string]$SourceId = 'guide'
    )

    $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $build = $BuildTimeUtc.ToUniversalTime()

    $span = @{}
    foreach ($p in @($Programme)) {
        $key = if ([string]::IsNullOrEmpty($p.RawChannelId)) { [string]$p.ChannelId } else { [string]$p.RawChannelId }
        if ([string]::IsNullOrEmpty($key) -or $p.End -le $p.Start) { continue }
        if (-not $span.ContainsKey($key)) { $span[$key] = @{ Start = $p.Start; End = $p.End; Count = 0 } }
        if ($p.Start -lt $span[$key].Start) { $span[$key].Start = $p.Start }
        if ($p.End -gt $span[$key].End) { $span[$key].End = $p.End }
        $span[$key].Count++
    }

    $ordered = @($Channel | Where-Object { $null -ne $_ } | Sort-Object { [string]$_.TvgId }, { [string]$_.DisplayName })
    foreach ($c in $ordered) {
        $tvgId = [string]$c.TvgId
        $hasId = -not [string]::IsNullOrEmpty($tvgId)
        $reference = if ($tvgId -cmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { $tvgId }
        elseif ($hasId) { 'id-' + (Get-ChannelForgeDomainHash -Domain 'channelforge/guide-id/v1' -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($tvgId))).Substring(0, 32) }
        $name = [string]$c.DisplayName
        $common = @{ SourceId = $SourceId; DisplayName = $name; Group = [string]$c.Group }
        if ($hasId) { $common.ChannelReference = $reference; $common.Title = $name }

        if ($hasId -and $span.ContainsKey($tvgId)) {
            $s = $span[$tvgId]
            New-ChannelForgeGuideEvidence -EvidenceType XMLTV @common `
                -StartUtc $s.Start.UtcDateTime.ToString($format, $culture) -EndUtc $s.End.UtcDateTime.ToString($format, $culture) `
                -ConfidenceState SafeCandidate -ConfidenceScore 70 `
                -FreshnessState $(if ($s.End.UtcDateTime -lt $build) { 'Stale' } else { 'Current' })
        }
        else {
            $codes = @('EvidenceMissing', 'NoEventData')
            New-ChannelForgeGuideEvidence -EvidenceType ProviderM3UMetadata @common -ReasonCodes $codes
        }
    }
}
