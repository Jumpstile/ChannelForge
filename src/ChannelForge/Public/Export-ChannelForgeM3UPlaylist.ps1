function Export-ChannelForgeM3UPlaylist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Channel[]]$Channel,

        [Parameter(Mandatory)]
        [string]$Path,

        # Optional group name -> public https logo URL (Get-ChannelForgePublishLogo).
        [hashtable]$GroupDefaultLogo = @{},

        # Optional TvgId -> pinned logo link (Get-ChannelForgeLogoPinMap).
        [hashtable]$LogoPin = @{},

        # Optional TvgId -> pinned group (Get-ChannelForgePublishGroup).
        [hashtable]$GroupPin = @{},

        # Fill empty provider groups from the category list (candidate v10).
        [switch]$FillEmptyGroups,

        # Optional approved folder; the file must resolve inside it.
        [string]$AllowedRoot
    )

    # With -AllowedRoot the write is confined here, before anything is built
    # or written. Without it the caller owns the guard via
    # Assert-ChannelForgeWritePath, as with Backup-IPTVBoss.ps1.
    begin {
        if ($PSBoundParameters.ContainsKey('AllowedRoot')) {
            Assert-ChannelForgeWritePath -Path $Path -AllowedRoot $AllowedRoot
        }
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
        $published = @(Get-ChannelForgePublishLogo -Channel $allChannels.ToArray() -GroupDefaultLogo $GroupDefaultLogo -LogoPin $LogoPin)
        $publishedGroup = @(Get-ChannelForgePublishGroup -Channel $allChannels.ToArray() -GroupPin $GroupPin -FillFromCategories:$FillEmptyGroups)
        for ($i = 0; $i -lt $allChannels.Count; $i++) {
            $ch = $allChannels[$i]
            $sourceLogo = $ch.Logo
            $ch.Logo = $published[$i].Logo
            try { $entryBytes = ConvertTo-ChannelForgeM3UEntryBytes -Channel $ch -PublishGroup $publishedGroup[$i].Group }
            finally { $ch.Logo = $sourceLogo }
            $entryText = [System.Text.UTF8Encoding]::new($false, $true).GetString($entryBytes)
            $lines.Add($entryText.TrimEnd("`n"))
        }

        $logoReport = Get-ChannelForgeLogoReport -Channel $published
        if ($logoReport.Warning) { Write-Warning $logoReport.Warning }

        # -NoNewline plus an explicit trailing "`n" gives one deterministic
        # byte sequence regardless of platform line-ending defaults.
        (($lines -join "`n") + "`n") | Set-Content -LiteralPath $Path -Encoding utf8NoBOM -NoNewline
    }
}
