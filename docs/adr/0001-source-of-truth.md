\# ADR 0001: ChannelForge owns the source of truth



\## Status



Accepted



\## Context



IPTVBoss, Dispatcharr, Plex, and future tools may change over time. Provider playlists and EPGs may also change. Relying on GUI state or generated files as the canonical configuration makes the system fragile.



\## Decision



ChannelForge will keep provider sources, EPG sources, channel rules, numbering rules, aliases, and output targets in declarative source files.



Generated outputs are disposable artifacts.



\## Consequences



\- Builds must be deterministic.

\- Production files are generated from source data.

\- GUI-only configuration should be avoided where practical.

\- Generated files should not be edited manually.

