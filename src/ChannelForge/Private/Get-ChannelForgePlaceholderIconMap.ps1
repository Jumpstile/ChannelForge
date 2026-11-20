function Get-ChannelForgePlaceholderIconMap {
    [CmdletBinding()]
    param(
        # Placeholder channels: Id (guide channel id) and EntryId (the playlist entry it stands for).
        [AllowEmptyCollection()][AllowNull()][object[]]$Channel = @(),
        # Candidate manifest entries: EntryId and EntryOutputSlice (ByteOffset, ByteLength in M3UBytes).
        [AllowEmptyCollection()][AllowNull()][object[]]$Entry = @(),
        # The candidate merged.m3u bytes.
        [AllowNull()][byte[]]$M3UBytes
    )

    # Guide file logos for name-only placeholder channels (issue #191): each gets the
    # tvg-logo its own playlist entry was published with. The playlist export already
    # decided it (public https kept, pin wins, else group default, else none), so no
    # rule is repeated here. The manifest Logo field is redacted and is not used.
    # Channels with no published logo have no entry. Never drops a channel.
    $map = [hashtable]::new([System.StringComparer]::Ordinal)
    if ($null -eq $M3UBytes -or $M3UBytes.Length -eq 0) { return , $map }
    $sliceByEntry = @{}
    foreach ($e in @($Entry)) { if ($null -ne $e -and $null -ne $e.EntryOutputSlice) { $sliceByEntry[[string]$e.EntryId] = $e.EntryOutputSlice } }
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    foreach ($c in @($Channel)) {
        $id = [string]$c.Id
        $slice = $sliceByEntry[[string]$c.EntryId]
        if ($id.Length -eq 0 -or $null -eq $slice -or $map.ContainsKey($id)) { continue }
        $offset = [int]$slice.ByteOffset
        $length = [int]$slice.ByteLength
        if ($null -eq $slice.ByteOffset -or $offset -lt 0 -or $length -le 0 -or $offset + $length -gt $M3UBytes.Length) { continue }
        $extinf = ($utf8.GetString($M3UBytes, $offset, $length) -split "`n", 2)[0]
        $match = [regex]::Match($extinf, 'tvg-logo="([^"]*)"')
        if ($match.Success -and $match.Groups[1].Value.Length -gt 0) { $map[$id] = $match.Groups[1].Value }
    }
    return , $map
}
