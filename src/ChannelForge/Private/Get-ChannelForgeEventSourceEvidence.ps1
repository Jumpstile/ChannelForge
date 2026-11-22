function Get-ChannelForgeEventSourceEvidence {
    # Fetches one event source page, turns it into evidence records and (with -EvidencePath) saves them with
    # Import-ChannelForgeScheduleEvidence. Wikipedia: -ProfilePath names a profile in data\event-profiles; the page is
    # the rendered HTML from the MediaWiki parse API, which also gives the revision id. TVmaze: -Show is one item of
    # data\event-profiles\tvmaze\shows.json; the page is the show's episode list. Every request goes through -Fetch
    # (a script block taking a URL and returning the response text); the default is the pinned HTTPS transport.
    # Returns Status (Ok | PageChanged | FetchFailed | WriteFailed), Reason, Records, Written (count). Anything but Ok
    # leaves the evidence file as it was. Nothing here is called by the build.
    [CmdletBinding(DefaultParameterSetName = 'Wikipedia')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Wikipedia')][string]$ProfilePath,
        [Parameter(Mandatory, ParameterSetName = 'Tvmaze')][object]$Show,
        [string]$EvidencePath,
        [scriptblock]$Fetch = { param($Url) Get-ChannelForgeLogoListDownload -Url $Url },
        [string]$FetchedAt = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    )

    $result = { param($Status, $Reason, $Records = @(), $Written = 0) [pscustomobject]@{ Status = $Status; Reason = $Reason; Records = @($Records); Written = $Written } }
    if ($PSCmdlet.ParameterSetName -eq 'Wikipedia') {
        $title = [string](Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json).pageTitle
        $url = 'https://en.wikipedia.org/w/api.php?action=parse&prop=text%7Crevid&format=json&formatversion=2&redirects=0&page=' + [uri]::EscapeDataString($title)
    }
    else {
        $url = "https://api.tvmaze.com/shows/$([int]$Show.showId)/episodes"
    }

    try { $body = [string](& $Fetch $url) }
    catch {
        $category = $_.Exception.Data['ChannelForgeFailureCategory']
        return & $result 'FetchFailed' $(if ($category) { "The page could not be fetched [$category]." } else { 'The page could not be fetched.' })
    }

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Wikipedia') {
            $page = ($body | ConvertFrom-Json -ErrorAction Stop).parse
            if (-not $page -or -not $page.revid -or -not $page.text) { return & $result 'PageChanged' "'$title': the reply has no page text and revision." }
            $converted = ConvertFrom-ChannelForgeWikipediaEvidence -Text ([string]$page.text) -ProfilePath $ProfilePath -Revision ([string]$page.revid) -FetchedAt $FetchedAt
            if ($converted.Status -ne 'Ok') { return & $result $converted.Status $converted.Reason }
            $records = @($converted.Records)
        }
        else {
            $trust = $null -eq $Show.PSObject.Properties['trustTimes'] -or [bool]$Show.trustTimes
            $records = @(ConvertFrom-ChannelForgeTvmazeEvidence -Json $body -FetchedAt $FetchedAt -TrustTimes $trust)
            if ($records.Count -eq 0) { return & $result 'PageChanged' "TVmaze show $([int]$Show.showId): no readable episodes." }
            foreach ($record in $records) { $record.Revision = "api.tvmaze.com/shows/$([int]$Show.showId)/episodes" }
        }
    }
    catch { return & $result 'PageChanged' 'The reply could not be read.' }

    if (-not $EvidencePath) { return & $result 'Ok' $null $records 0 }

    $csv = Join-Path ([System.IO.Path]::GetTempPath()) ('cf-evidence-' + [guid]::NewGuid().ToString('N') + '.csv')
    try {
        @($records | ForEach-Object {
            [pscustomobject]@{ kind = $_.Kind; name = $_.Name; date = $_.Date; time = $_.Time; venue = $_.Venue; city = $_.City
                source = $_.Source; license = $_.License; attribution = $_.Attribution; fetchedAt = $_.FetchedAt; revision = $_.Revision }
        }) | Export-Csv -LiteralPath $csv -Encoding utf8NoBOM
        $saved = Import-ChannelForgeScheduleEvidence -SourcePath $csv -EvidencePath $EvidencePath
    }
    catch { return & $result 'WriteFailed' $_.Exception.Message $records }
    finally { Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue }
    if (@($saved.Rejected).Count -gt 0) { return & $result 'WriteFailed' (@($saved.Rejected) -join ' ') $records ($saved.Added + $saved.Updated) }
    & $result 'Ok' $null $records ($saved.Added + $saved.Updated)
}
