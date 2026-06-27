\# ADR 0003: Use clean layered architecture



\## Status



Accepted



\## Context



ChannelForge may eventually support multiple input formats and multiple output targets. If domain objects depend on IPTVBoss, Dispatcharr, Plex, or any specific infrastructure, the project will become difficult to extend and maintain.



\## Decision



ChannelForge will use a layered architecture:



1\. Domain layer

&#x20;  - Channel

&#x20;  - Provider

&#x20;  - Playlist

&#x20;  - Programme

&#x20;  - Rules

&#x20;  - Build context



2\. Application layer

&#x20;  - Build orchestration

&#x20;  - Validation

&#x20;  - Reports

&#x20;  - Deployment approval



3\. Infrastructure layer

&#x20;  - M3U

&#x20;  - XMLTV

&#x20;  - JSON

&#x20;  - CSV

&#x20;  - IPTVBoss

&#x20;  - Dispatcharr

&#x20;  - File system

&#x20;  - HTTP



Domain objects must not reference infrastructure-specific concepts.



\## Consequences



\- IPTVBoss is an output target, not the core model.

\- New outputs can be added without changing the domain.

\- Engines must consume and produce domain objects.

\- Configuration remains source-of-truth.

