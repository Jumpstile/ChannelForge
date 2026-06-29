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
            $tvgId = ConvertTo-ChannelForgeSafeM3UText -Text $ch.TvgId
            $tvgName = ConvertTo-ChannelForgeSafeM3UText -Text $ch.TvgName
            $logo = ConvertTo-ChannelForgeSafeM3UText -Text $ch.Logo
            $group = ConvertTo-ChannelForgeSafeM3UText -Text $ch.Group
            $displayName = ConvertTo-ChannelForgeSafeM3UText -Text $ch.DisplayName
            $url = ConvertTo-ChannelForgeSafeM3UText -Text $ch.Url

            $attributes = [System.Collections.Generic.List[string]]::new()

            if ($tvgId) { $attributes.Add("tvg-id=`"$tvgId`"") }
            if ($tvgName) { $attributes.Add("tvg-name=`"$tvgName`"") }
            if ($logo) { $attributes.Add("tvg-logo=`"$logo`"") }
            if ($null -ne $ch.AssignedNumber) { $attributes.Add("tvg-chno=`"$($ch.AssignedNumber)`"") }
            if ($group) { $attributes.Add("group-title=`"$group`"") }

            $attributeText = if ($attributes.Count -gt 0) { ' ' + ($attributes -join ' ') } else { '' }
            $lines.Add("#EXTINF:-1$attributeText,$displayName")
            $lines.Add($url)
        }

        # -NoNewline plus an explicit trailing "`n" gives one deterministic
        # byte sequence regardless of platform line-ending defaults.
        (($lines -join "`n") + "`n") | Set-Content -LiteralPath $Path -Encoding utf8NoBOM -NoNewline
    }
}
