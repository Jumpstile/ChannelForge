# ADR-0016: Web-first local UI and server-first deployment

## Status

Accepted

## Context

ChannelForge's existing GUI work is a React/TypeScript application wrapped in Tauri. That work established useful layout, design-token, Guided Setup, source-selection, validation, review, saved-lineup, accessibility, and beginner-copy patterns. The native wrapper also contains shell-specific commands, native file-picker access, direct filesystem assumptions, and local PowerShell invocation.

Issue #150 corrects the product architecture direction. ChannelForge should not require a separate desktop shell merely to display a front end. Users should run the engine on a Docker host, NAS or home server, always-on local machine, or Windows machine installed as a local server/service, then use a browser for setup, review, acceptance, refresh health, reports, and settings.

The architecture must preserve the existing immutable-generation and accepted-state safety contract. A browser UI must not create a second accepted-lineup authority, expose provider secrets or private paths, or bypass engine validation by receiving direct filesystem or process authority.

## Decision

ChannelForge's primary UI is a browser-based local web UI served by the ChannelForge engine.

The browser consumes one documented local HTTP/API surface. The engine remains the authority for configuration, source acquisition, candidate generation, validation, review, explicit acceptance, immutable generation publication, reports, and generated M3U/XMLTV outputs.

The primary deployment modes are:

1. **Docker container** — the engine serves the web UI and API from one container. Persistent mounts must support configuration, disposable source cache, immutable generations, accepted pointers, reports/logs, and generated M3U/XMLTV outputs.
2. **Windows server/service install** — the installed engine serves the same web UI and API locally as a server/service process. Persistent storage must preserve the same configuration, cache, generation, pointer, report, log, and output boundaries.
3. **Windows x64 portable local server** — the alpha bundle serves the same engine/API on loopback with a pinned PowerShell runtime, no administrator requirement, and per-user `%LOCALAPPDATA%` storage. It is intentionally not a Windows Service; its launcher owns the foreground server process and health check.

Native/local development may serve the same UI/API without Docker. Docker,
Windows server/service, the portable local server, and native/local modes must
share the same engine commands, accepted-generation contract, redaction rules,
and mutation boundaries.
A Tauri/native wrapper is optional future packaging only. It is not the primary shell, must not duplicate product logic, and must not define a second product surface or state authority.

Existing Tauri UI work is preserved and should be reused where practical:

- visual layout direction, navigation, status hierarchy, and accessibility patterns;
- design tokens and theme language, including future appearance-mode support;
- Guided Setup / Beginner Workflow screen structure;
- playlist and XMLTV guide selection UX;
- structural validation, exact-match, ambiguity, and review surfaces;
- saved-lineup candidate, explicit acknowledgement, and read-only accepted-state concepts;
- beginner-facing copy, terminology, reason codes, and progressive disclosure.

Before web UI implementation, native assumptions must be re-evaluated. This includes Tauri shell commands, native file-picker behavior, direct filesystem access, local process invocation, and every state-changing path outside the engine HTTP/API boundary. Browser state-changing behavior must call documented engine commands and remain behind the immutable acceptance boundary.

This ADR records architecture only. It does not implement the web server, HTTP API, Docker packaging, Windows service installation, Light/Dark/System appearance mode, or UI migration.

## Consequences

- Browser access is sufficient for normal product use; users do not need to install a desktop shell merely to host the UI.
- The web UI can target Docker and Windows server/service installs without creating deployment-specific product behavior.
- The existing Tauri work remains valuable as a design and behavior reference rather than being deleted or treated as the deployment contract.
- Native-only behavior cannot be copied into the browser without an engine/API contract and explicit safety review.
- Issue #145 must distinguish primary web UI TypeScript/Vitest checks from optional Tauri/Rust compatibility checks.
- Docker, Windows service, engine HTTP/API, web UI migration, and appearance-mode implementation remain follow-up work.

## Verification

- Architecture and developer documentation identify browser web UI as primary and Tauri as optional packaging.
- Current-limitations and beginner documentation state which web/server deployment capabilities are not implemented.
- Existing GUI reuse and native-assumption re-evaluation lists are explicit.
- Issue #141 intent-fit evidence records the UI authority, entry points, safety boundary, and deferred implementation work.
- Future web UI checks must include TypeScript and Vitest; Tauri/Rust checks apply only when the optional wrapper is in scope.
- Future implementation review must prove that Docker, Windows server/service, and native/local modes share one engine/API and accepted-generation authority.

## Related Issues

- #10
- #127
- #135
- #136
- #141
- #145
- #149
- #150
