# ADR 0003: Use clean layered architecture

## Status

Accepted

## Context

ChannelForge may eventually support multiple input formats and multiple output targets. If domain objects depend on IPTVBoss, Dispatcharr, Plex, or any specific infrastructure, the project will become difficult to extend and maintain.

## Decision

ChannelForge will use a layered architecture:

1. Domain layer

   - Channel

   - Provider

   - Playlist

   - Programme

   - Rules

   - Build context

2. Application layer

   - Build orchestration

   - Validation

   - Reports

   - Deployment approval

3. Infrastructure layer

   - M3U

   - XMLTV

   - JSON

   - CSV

   - IPTVBoss

   - Dispatcharr

   - File system

   - HTTP

Domain objects must not reference infrastructure-specific concepts.

## Consequences

- IPTVBoss is an output target, not the core model.

- New outputs can be added without changing the domain.

- Engines must consume and produce domain objects.

- Configuration remains source-of-truth.
