function Get-ChannelForgeLogoSourceComparison {
    [CmdletBinding()]
    param(
        # Rows with Id and Logo (playlist side).
        [AllowEmptyCollection()][object[]]$PlaylistRow = @(),
        # Rows with Id and Icon (guide side).
        [AllowEmptyCollection()][object[]]$GuideRow = @()
    )

    # Report only. Per channel id: do the playlist logo and the guide icon
    # agree? Returns a state word and a short fingerprint per side. The link
    # text itself is never returned. Fetches nothing, changes nothing.
    function Get-Fingerprint([AllowNull()][string]$Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.Trim())
        $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
        [System.BitConverter]::ToString($hash, 0, 6).Replace('-', '').ToLowerInvariant()
    }

    $playlist = [hashtable]::new([System.StringComparer]::Ordinal)
    foreach ($row in $PlaylistRow) { $id = ([string]$row.Id).Trim(); if ($id -and -not $playlist.ContainsKey($id)) { $playlist[$id] = Get-Fingerprint $row.Logo } }
    $guide = [hashtable]::new([System.StringComparer]::Ordinal)
    foreach ($row in $GuideRow) { $id = ([string]$row.Id).Trim(); if ($id -and -not $guide.ContainsKey($id)) { $guide[$id] = Get-Fingerprint $row.Icon } }

    foreach ($id in @($playlist.Keys + $guide.Keys | Sort-Object -Unique -CaseSensitive)) {
        $p = $playlist[$id]
        $g = $guide[$id]
        $state = if (-not $p -and -not $g) { 'Missing' }
        elseif (-not $g) { 'PlaylistOnly' }
        elseif (-not $p) { 'GuideOnly' }
        elseif ($p -ceq $g) { 'Agreement' }
        else { 'Conflict' }
        [pscustomobject][ordered]@{ Id = $id; State = $state; PlaylistFingerprint = $p; GuideFingerprint = $g }
    }
}
