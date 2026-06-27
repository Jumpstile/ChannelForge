# ChannelForge / IPTVBoss Greenfield Builder

This folder is the source-of-truth for Eli's OMV + IPTVBoss + Dispatcharr + Plex IPTV build.

## Status

This package is a **greenfield builder scaffold**, not a direct H2 database patch.

It contains the provider sources, EPG sources, channel numbering rules, local affiliate numbering, and category rules that we will use to generate/import the IPTVBoss configuration.

## Key rules

- Create `USER1` in IPTVBoss before creating layouts.
- Layout name: `Plex`
- Output M3U: `/output/merged.m3u`
- Output XMLTV: `/output/merged.xmltv`
- Exclude provider group: `Default`
- Keep Adult/XXX isolated in 900–999.
- Put NY and PA locals at top using real affiliate channel numbers.
- No international clutter in the primary lineup.

## First commands

From OMV, after copying this folder to:

`/srv/dev-disk-by-uuid-4d39f891-6950-43f3-9ac1-ba3dd583c8e8/appdata/iptvboss-builder`

run:

```bash
pwsh ./scripts/Validate-Config.ps1
pwsh ./scripts/Build-Lineup.ps1
```

If PowerShell 7 is not installed on OMV, these same scripts can be run from Windows PowerShell by pointing to the SMB folder.

## noVNC URL

Use the full noVNC interface:

`https://example.invalid/REDACTED

Clipboard workflow:

1. Copy on Windows.
2. Paste into noVNC clipboard sidebar.
3. In Linux terminal, press `Shift+Insert`.
