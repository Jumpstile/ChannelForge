# Coming From IPTVBoss

This page answers: **if I used IPTVBoss, what does ChannelForge do for me today?**

ChannelForge is **Early Alpha**. It does not need IPTVBoss to run. It does not copy IPTVBoss screens or files. Where something is missing, this page says "not yet". The full table is in the [parity matrix](../architecture/IPTVBOSS_PARITY.md). For the complete list of limits, see [Current Limitations](CURRENT_LIMITATIONS.md).

## Your playlists and sources

- **Today:** you can add a local playlist file or a public HTTPS playlist. You can add more than one. See [Sources](Concepts/Sources.md) and [Build Your First Lineup](Build-Your-First-Lineup.md).
- **Not yet:** Xtream Codes logins. This is planned for later, not alpha.1 (proposed, owner can change).
- **Safe by default:** secrets stay out of reports and logs. See [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md).
- **Next step:** use a playlist URL or file.

## Event channels (AED-style patterns)

- **Today:** ChannelForge can read AED-derived guide data. It can suggest event patterns and show a report. The report changes nothing. See [What Is ChannelForge?](What-Is-ChannelForge.md).
- **Not yet:** importing AED definitions, exporting your rules, defaults and inheritance, a fallback-chain preview, and expert regex. ESPN+ prefix handling is later too (proposed, owner can change).
- **Next step:** read the pattern report and decide by hand.

## Finding where a channel is assigned

- **Not yet.** There is no lookup. Today you check the build reports.

## Layouts and output profiles

- **Not yet.** You get one accepted lineup and one generic M3U and XMLTV output. See [Use ChannelForge with Plex](Use-With-Plex.md).

## New groups and removed channels

- **Not yet:** ChannelForge does not list new or renamed groups for you.
- **Today:** if a refresh fails, ChannelForge keeps your last good copy and your accepted lineup. A changed source creates a review. Nothing is accepted for you.

## Scheduled and unattended runs

- **Today (Windows only):** you can opt in to a daily scheduled refresh. It never accepts changes by itself.
- **Not yet:** Docker, a Windows service, and last-success or next-run on the web page. Docker and service are later (proposed, owner can change).
- **Safe by default:** only one run can write at a time. If a lock is in the way, ChannelForge stops instead of guessing.
- **Next step:** see [Current Limitations](CURRENT_LIMITATIONS.md) before turning on a schedule.

## Duplicates and several playlists

- **Today:** several playlists can feed one lineup. See [Sources](Concepts/Sources.md) and [Channel IDs](Concepts/Channel-IDs.md).
- **Not yet:** full duplicate policy and custom channel numbers are still being built.

## Stuck?

See [Troubleshooting](TROUBLESHOOTING.md).
