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
        foreach ($ch in $allChannels) {
            $attributes = [System.Collections.Generic.List[string]]::new()

            if ($ch.TvgId) { $attributes.Add("tvg-id=`"$($ch.TvgId)`"") }
            if ($ch.TvgName) { $attributes.Add("tvg-name=`"$($ch.TvgName)`"") }
            if ($ch.Logo) { $attributes.Add("tvg-logo=`"$($ch.Logo)`"") }
            if ($null -ne $ch.AssignedNumber) { $attributes.Add("tvg-chno=`"$($ch.AssignedNumber)`"") }
            if ($ch.Group) { $attributes.Add("group-title=`"$($ch.Group)`"") }

            $attributeText = if ($attributes.Count -gt 0) { ' ' + ($attributes -join ' ') } else { '' }
            $lines.Add("#EXTINF:-1$attributeText,$($ch.DisplayName)")
            $lines.Add($ch.Url)
        }

        # -NoNewline plus an explicit trailing "`n" gives one deterministic
        # byte sequence regardless of platform line-ending defaults.
        (($lines -join "`n") + "`n") | Set-Content -LiteralPath $Path -Encoding utf8NoBOM -NoNewline
    }
}
