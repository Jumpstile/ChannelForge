# IPTVBoss Docker integration research

## Source

Public project: `groenator/iptvboss-docker`

## Why it matters

The project provides containerized IPTVBoss operation in VNC, headless, and Xpra forms. The container keeps IPTVBoss user data on a host-mounted persistent directory and can run IPTVBoss in scheduled headless mode.

Observed public integration seams:

- Persistent host mount: `/headless/IPTVBoss`
- IPTVBoss installation path inside the image: `/usr/lib/iptvboss`
- Headless scheduled command: `/usr/lib/iptvboss/bin/iptvboss -nogui`
- Optional container-managed cron scheduling through `CRON_SCHEDULE`
- Optional XC server startup
- rclone included for syncing IPTVBoss data externally

## ChannelForge implication

ChannelForge should treat IPTVBoss as an optional upstream guide-generation source, not as an internal dependency or second system of record.

A supported integration should prefer normal filesystem artifacts that IPTVBoss deliberately places in its persistent data/output directory. ChannelForge may consume generated M3U/XMLTV and other documented export artifacts from that directory when configured by the user.

Do not screen-scrape the IPTVBoss GUI and do not depend on undocumented application databases, private storage schemas, or internal AED files merely because they happen to be visible in a container volume.

ChannelForge now has a read-only native event-pattern candidate model for supplied examples and Stage A evidence. A documented IPTVBoss AED import/export format may later be translated into that structured model; until a real documented export fixture is available, do not infer its schema or depend on private storage. AED-derived XMLTV remains a safe interoperability boundary.

## Recommended deployment relationship

A future container deployment may run IPTVBoss and ChannelForge as separate services with explicit shared/export paths:

1. IPTVBoss refreshes its own sources and writes validated guide/output artifacts.
2. ChannelForge reads those artifacts as one provenance-bearing source.
3. ChannelForge independently compares them with provider metadata, supplemental XMLTV, schedule evidence, and accepted local knowledge.
4. ChannelForge never treats IPTVBoss application state as accepted-lineup authority.

ChannelForge should not rely on IPTVBoss cron as its own autonomous scheduler. Container-managed IPTVBoss scheduling is useful for interoperability and migration, while ChannelForge Issue #35 remains responsible for ChannelForge's own bounded refresh, health, last-known-good, and eventual unattended-operation semantics.

## Safety boundary

- Preserve source provenance.
- Do not expose provider credentials or private stream URLs in diagnostics.
- Do not mutate IPTVBoss configuration unless a future documented integration explicitly supports it.
- Do not infer AED persistence formats from reverse engineering when a documented export is unavailable.
- Keep IPTVBoss optional so ChannelForge can progressively replace AED dependency with native event intelligence without breaking users who continue to use IPTVBoss.
