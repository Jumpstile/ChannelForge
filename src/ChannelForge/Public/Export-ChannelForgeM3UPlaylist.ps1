function Export-ChannelForgeM3UPlaylist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Channel[]]$Channel,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # This function only writes the file it is told to write. Confining the
    # write to an approved location (e.g. the project's output/ folder) is
    # the caller's responsibility via Assert-ChannelForgeWritePath - the same
    # separation Build-Lineup.ps1 and Backup-IPTVBoss.ps1 already follow.
    begin {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('#EXTM3U')
        $allChannels = [System.Collections.Generic.List[Channel]]::new()
    }

    process {
        foreach ($ch in $Channel) {
            $allChannels.Add($ch)
        }
    }

    end {
        # Stream URLs are the actual playable content of this file, unlike
        # provider/EPG source URLs or report output - they are not redacted
        # here (see docs/developer/DEVELOPER_GUIDE.md, "Report redaction").
        # Every field below comes from untrusted provider text (M3U
        # attributes, alias-resolved names) and is sanitized just before
        # writing, never earlier, so the domain object always keeps the
        # original value.
        foreach ($ch in $allChannels) {
            $entryBytes = ConvertTo-ChannelForgeM3UEntryBytes -Channel $ch
            $entryText = [System.Text.UTF8Encoding]::new($false, $true).GetString($entryBytes)
            $lines.Add($entryText.TrimEnd("`n"))
        }

        # -NoNewline plus an explicit trailing "`n" gives one deterministic
        # byte sequence regardless of platform line-ending defaults.
        (($lines -join "`n") + "`n") | Set-Content -LiteralPath $Path -Encoding utf8NoBOM -NoNewline
    }
}
