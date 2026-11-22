function Get-ChannelForgeEventEvidenceSource {
    # Lists the event evidence sources in a profile directory: one per Wikipedia profile (*.json in the folder itself)
    # and one per show in tvmaze\shows.json. Each item has Name, Kind (Wikipedia | TVmaze), Profile or Show, CacheName
    # (a safe file name) and MaxAge (24 hours for TV episodes, 7 days for league pages). Nothing here is called by the build.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileDirectory)

    foreach ($file in @(Get-ChildItem -LiteralPath $ProfileDirectory -Filter '*.json' -File | Sort-Object Name)) {
        [pscustomobject]@{ Name = $file.BaseName; Kind = 'Wikipedia'; Profile = $file.FullName; Show = $null
            CacheName = "wikipedia-$($file.BaseName).json"; MaxAge = [timespan]::FromDays(7) }
    }
    $showsPath = Join-Path (Join-Path $ProfileDirectory 'tvmaze') 'shows.json'
    if (Test-Path -LiteralPath $showsPath -PathType Leaf) {
        foreach ($show in @(Get-Content -LiteralPath $showsPath -Raw | ConvertFrom-Json)) {
            [pscustomobject]@{ Name = [string]$show.name; Kind = 'TVmaze'; Profile = $null; Show = $show
                CacheName = "tvmaze-$([int]$show.showId).json"; MaxAge = [timespan]::FromHours(24) }
        }
    }
}
