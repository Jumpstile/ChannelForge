function Update-ChannelForgeEventEvidence {
    <#
    .SYNOPSIS
    Refreshes the saved event schedule evidence from the free Wikipedia and TVmaze sources.
    .DESCRIPTION
    Owner-run only. No build, test or candidate run calls it. Together with the
    logo lookup refresh, it is the only place that uses the network.

    Each source (one per Wikipedia profile and one per TVmaze show in
    -ProfileDirectory) keeps its own cache file in -CacheDirectory. A source
    whose cache is still fresh is skipped unless you pass -Force. TV episode
    caches are fresh for 24 hours; Wikipedia league pages for 7 days.

    A good fetch is saved, and the previous copy is kept next to it as a
    ".lkg" (last known good) file. Anything else leaves the cache as it was
    and says why. If a page changed its layout, the status is PageChanged and
    nothing is guessed. TVmaze shows marked untrusted in shows.json (RAW,
    NJPW Strong) keep their times out of the evidence.

    Run with -WhatIf first. It fetches nothing and writes nothing; each source
    that would be fetched shows Status WouldFetch.

    Returns one object per source: Name, Kind, Status (Refreshed, SkippedFresh,
    PageChanged, FetchFailed, WriteFailed, or WouldFetch for -WhatIf), Reason,
    RecordCount, FetchedAt, CachePath.
    .PARAMETER ProfileDirectory
    Folder with the event profiles. Default: the data\event-profiles folder that ships with ChannelForge.
    .PARAMETER CacheDirectory
    Folder where the cache files go, one file per source. Created if missing.
    .PARAMETER Source
    Only refresh the sources with these names (a profile file name without .json, or a TVmaze show name).
    .PARAMETER Force
    Refresh even when the cache is still fresh.
    .PARAMETER Fetch
    For tests: a script block that takes a URL and returns the response text.
    .EXAMPLE
    Update-ChannelForgeEventEvidence -CacheDirectory .\state\evidence -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ProfileDirectory = (Join-Path (Get-ChannelForgeWebRepositoryRoot) 'data\event-profiles'),
        [Parameter(Mandatory)][string]$CacheDirectory,
        [string[]]$Source,
        [switch]$Force,
        [scriptblock]$Fetch = { param($Url) Get-ChannelForgeLogoListDownload -Url $Url }
    )

    $sources = @(Get-ChannelForgeEventEvidenceSource -ProfileDirectory $ProfileDirectory)
    if ($Source) {
        $unknown = @($Source | Where-Object { $wanted = $_; -not @($sources | Where-Object { $_.Name -eq $wanted }) })
        if ($unknown.Count -gt 0) {
            throw "Unknown source: $($unknown -join ', '). Known sources: $((@($sources.Name) | Sort-Object) -join ', ')."
        }
        $sources = @($sources | Where-Object { $Source -contains $_.Name })
    }

    foreach ($item in $sources) {
        $cachePath = Join-Path $CacheDirectory $item.CacheName
        $summary = { param($Status, $Reason, $Count, $At)
            [pscustomobject][ordered]@{ Name = $item.Name; Kind = $item.Kind; Status = $Status; Reason = $Reason
                RecordCount = $Count; FetchedAt = $At; CachePath = $cachePath } }

        $cached = Read-ChannelForgeEvidenceCache -Path $cachePath -MaxAge $item.MaxAge
        if ($cached.Status -eq 'Fresh' -and -not $Force) {
            & $summary 'SkippedFresh' "The cache is fresh until $($cached.ExpiresAt). Use -Force to refresh anyway." @($cached.Records).Count $cached.FetchedAt
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($cachePath, "Fetch $($item.Kind) source '$($item.Name)' and save it")) {
            & $summary 'WouldFetch' 'Nothing was fetched or written (-WhatIf).' 0 $null
            continue
        }

        $fetchedAt = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
        $arguments = if ($item.Kind -eq 'Wikipedia') { @{ ProfilePath = $item.Profile } } else { @{ Show = $item.Show } }
        $got = Get-ChannelForgeEventSourceEvidence @arguments -Fetch $Fetch -FetchedAt $fetchedAt
        if ($got.Status -ne 'Ok') {
            & $summary $got.Status $got.Reason 0 $null
            continue
        }

        $first = @($got.Records)[0]
        $saved = Save-ChannelForgeEvidenceCache -Path $cachePath -Records $got.Records -Source ([string]$first.Source) -Revision ([string]$first.Revision) -FetchedAt $fetchedAt
        if ($saved.Status -eq 'Saved') { & $summary 'Refreshed' $null @($got.Records).Count $fetchedAt }
        else { & $summary 'WriteFailed' $saved.Reason 0 $null }
    }
}
