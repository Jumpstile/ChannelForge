# Coming From IPTVBoss

This page answers: **if I used IPTVBoss, what does ChannelForge do for me today?**

ChannelForge is **Early Alpha**. It does not need IPTVBoss to run. It does not copy IPTVBoss screens or files. Where something is missing, this page says "not yet". The full table is in the [parity matrix](../architecture/IPTVBOSS_PARITY.md). For the complete list of limits, see [Current Limitations](CURRENT_LIMITATIONS.md).

## Your playlists and sources

- **Today:** you can add a local playlist file or a public HTTPS playlist. You can add more than one. See [Sources](Concepts/Sources.md) and [Build Your First Lineup](Build-Your-First-Lineup.md).
- **Not yet:** Xtream Codes logins. This is planned for later, not alpha.1 (proposed, owner can change).
- **Links with a login in them:** a command to save the login for a remote source is built and waiting for the owner's hand test. It is not in alpha.1 and is planned for the next release. See [Remote Credential Enrollment](Remote-Credential-Enrollment.md).
- **Safe by default:** secrets stay out of reports and logs. See [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md).
- **Next step:** use a playlist URL or file.

## Event channels (AED-style patterns)

- **Today:** ChannelForge can read AED-derived guide data. It can suggest event patterns and show a report. The report changes nothing. See [What Is ChannelForge?](What-Is-ChannelForge.md).
- **Not yet:** importing AED definitions, exporting your rules, defaults and inheritance, a fallback-chain preview, and expert regex. ESPN+ prefix handling is later too (proposed, owner can change).
- **Next step:** read the pattern report and decide by hand.

## Finding where a channel is assigned

- **Today:** ChannelForge has an internal report that tells where a channel is assigned. It has no command yet, so you cannot run it from a prompt.
- **Not yet:** a screen for it. There is no web page for this before Milestone 3.
- **Next step:** until then, check the build reports.

## Layouts and output profiles

- **Today:** ChannelForge ships compatibility profiles for Plex, IPTVBoss and Dispatcharr in `data/compatibility`. A profile lists what that program is known to accept. You still get one accepted lineup and one generic M3U and XMLTV output. See [Use ChannelForge with Plex](Use-With-Plex.md).
- **Preview:** `scripts/Show-ChannelForgeTargetPreview.ps1` shows what a target might drop. It only reports. It changes nothing. Most rows say "unknown" today. Unknown means no proof yet. It is never treated as supported.
- **Not yet:** a separate output file for each program.
- **Next step:** run the preview with `-Profile` and `-PlaylistPath`.

## New groups and removed channels

- **Today:** after a source refresh, ChannelForge reports which groups and channels are new and which are missing. It lists names only, never links. Run `scripts/Invoke-ChannelForgeSourceRefresh.ps1` to get it. The first refresh has nothing to compare with.
- **Safe by default:** if a refresh fails, ChannelForge keeps your last good copy and your accepted lineup. A changed source creates a review. Nothing is accepted for you.

## Scheduled and unattended runs

- **Today (Windows only):** you can opt in to a daily scheduled refresh. It never accepts changes by itself.
- **Not yet:** Docker, a Windows service, and last-success or next-run on the web page. Docker and service are later (proposed, owner can change).
- **Safe by default:** only one run can write at a time. If a lock is in the way, ChannelForge stops instead of guessing.
- **Next step:** see [Current Limitations](CURRENT_LIMITATIONS.md) before turning on a schedule.

## Duplicates and several playlists

- **Today:** several playlists can feed one lineup. See [Sources](Concepts/Sources.md) and [Channel IDs](Concepts/Channel-IDs.md).
- **Today:** when two channels are the same, ChannelForge keeps one and lists each dropped copy as a review item. You decide what to do.
- **Today:** you can save your own channel number for a channel with `Set-ChannelForgeUserChannelNumber`. Numbers are whole numbers from 1 to 9999. They are kept in `state/channel-decisions.json` and used on every build.
- **Not yet:** a full duplicate policy, and a screen for channel numbers.

## Checking your setup

- **Today:** `scripts/Invoke-ChannelForgeDoctor.ps1` prints a health report. Each finding is Pass, Fail or Unknown, with a next step. Unknown is never shown as Pass.

## Not in ChannelForge yet

- A web screen to manage all this comes with Milestone 3.
- ChannelForge does not play channels yet. Playback is planned.
- ChannelForge does not write catch-up (replay) settings.

## Stuck?

See [Troubleshooting](TROUBLESHOOTING.md).
