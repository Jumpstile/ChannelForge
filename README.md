# ChannelForge

<p align="center">

<strong>One source. Many outputs. Zero guesswork.</strong>

</p>

<p align="center">

An evidence-driven television knowledge engine for building accurate, trustworthy, deterministic channel lineups.

</p>

<p align="center">

  <img alt="Status" src="https://img.shields.io/badge/status-early%20alpha-orange">

  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-7.6%2B-blue">

  <img alt="Tests" src="https://img.shields.io/badge/tests-Pester%205.7.1-purple">

</p>

---

## What is ChannelForge?

ChannelForge is a PowerShell project that turns provider playlists, guide data, local rules, and reference knowledge into clean television lineups.

It started as tooling for IPTVBoss, Dispatcharr, and Plex, but the bigger goal is this:

> **Establish confidence in television metadata.**

ChannelForge does not blindly trust playlist names.

It verifies, explains, repairs safely, and preserves user intent.

---

## Why it exists

Television metadata changes constantly.

Providers rename channels.

EPG IDs drift.

Logos change.

Duplicate streams appear.

Feeds go down.

Lineups get messy.

ChannelForge is designed to detect that drift, explain what changed, and eventually repair safe issues automatically.

---

## Five pillars

| Pillar | Meaning |

|---|---|

| **Truth** | Important facts should be supported by evidence. |

| **Trust** | Automated decisions should be explainable. |

| **Recoverability** | Changes should be reversible. |

| **Determinism** | Same input, same output. |

| **Self-Healing** | Safe repairs are automated; uncertain repairs require review. |

---

## Current status

> **Early Alpha — not production-ready yet**

Working today:

- PowerShell module layout

- GitHub Actions CI with config schema, Markdown, lint, and test quality gates

- Pester 5.7.1 tests

- Provider config import

- EPG source import

- M3U playlist parsing

- Deterministic merged M3U output from local playlists or configured remote provider M3U sources (alias resolution, numbering, dedup), plus Build-Lineup integration for configured local and bounded remote XMLTV sources with source-aware programme binding/merge and deterministic XMLTV output

- `BuildContext` domain object

- `Channel` domain object

- Channel normalization

- Architecture Decision Records

- Documentation architecture

### UI architecture

The primary UI direction is a browser-based local web UI served by the ChannelForge engine. Docker container and Windows server/service installation are the primary deployment modes; native/local development serves the same UI/API. This architecture is recorded in [ADR-0016](docs/adr/0016-web-first-local-ui.md). A minimal read-only loopback server and placeholder shell are available through `scripts/Start-ChannelForgeWebServer.ps1`; when `gui/dist` contains a Vite build, the server serves its `index.html` and allowlisted static assets instead. The built React/Vite landing surface now consumes `GET /api/status` and displays only beginner-safe running, lineup, next-action, read-only, loading, and unavailable states. Its visible Appearance control offers Light, Dark, and System; System is the default and follows the device setting. The selected mode persists in browser-local storage only and never writes repository or engine state. Full API-backed Guided Setup, Docker, and Windows server/service implementation remain future work.

The web UI's appearance control is presentation-only: it changes browser-local colors for the shell, dashboard, cards, controls, loading, and unavailable states. It sends no state-changing request and does not expose provider URLs, credentials, private paths, hashes, generation IDs, accepted-generation contents, or parser details.

Existing React/TypeScript/Tauri work is preserved as reusable layout, design-token, Guided Setup, validation/review, saved-lineup, accessibility, and beginner-copy reference work. Tauri is optional future packaging, not the primary product shell.

### GUI status

| Area                                      | Status                                                                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Browser web UI served by engine           | Built UI with read-only `/api/status` dashboard and Light/Dark/System appearance control; Guided Setup actions pending |
| Docker deployment                         | Architecture recorded; implementation pending                                                                          |
| Windows server/service install            | Architecture recorded; implementation pending                                                                          |
| Optional Tauri Workbench shell/navigation | Works now (prototype)                                                                                                  |
| Guided Setup layout                       | Preview only (prototype)                                                                                               |
| Native file-picker bridge                 | Works now (prototype)                                                                                                  |
| Display-safe selection state              | Works now (prototype)                                                                                                  |
| Pre-parse selection checks                | Works now (prototype)                                                                                                  |
| Playlist structural validation            | Works now — structural only (prototype)                                                                                |
| Guide structural validation               | Works now — structural only (prototype)                                                                                |
| Playlist/guide exact matching             | Implemented — local checks passed (prototype)                                                                          |
| Lineup review                             | Implemented — local checks passed (prototype)                                                                          |
| Saved lineup                              | Implemented — native acceptance + local checks                                                                         |
| Automatic updates                         | Planned / not built yet                                                                                                |

---

## Engineering foundation

Core project governance and engineering memory:

- [Onboarding](ONBOARDING.md)

- [Constitution](CONSTITUTION.md)

- [AI collaboration](AI_COLLABORATION.md)

- [Claude adapter](CLAUDE.md)

- [Codex adapter](CODEX.md)

- [ChatGPT adapter](CHATGPT.md)

- [Contributing](CONTRIBUTING.md)

- [Documentation](DOCUMENTATION.md)

- [Roadmap](ROADMAP.md)

- [Lessons learned](LESSONS_LEARNED.md)

- [Evidence over assumptions ADR](docs/adr/0005-evidence-over-assumptions.md)

- [ADR template](docs/templates/adr-template.md)

- [Bug sweep checklist](docs/templates/bug-sweep-checklist.md)

- [Vulnerability sweep checklist](docs/templates/vulnerability-sweep-checklist.md)

- [Release checklist](docs/templates/release-checklist.md)

- [Repository docs and user documentation](docs/reference/DOCS_AND_WIKI.md)

---

## Repository map

```text

ChannelForge/

├── data/                  Source data and rules (see *.example.json for local secrets setup)

├── docs/                  Project documentation

│   ├── adr/               Architecture Decision Records

│   ├── architecture/      System design and project identity

│   ├── developer/         Contributor and coding docs

│   ├── engineering/       Engineering standards

│   ├── reference/         Install, security, and reference docs

│   └── user/              Beginner-facing docs

├── schemas/               JSON Schema contracts for data/ config files

├── src/ChannelForge/      PowerShell module

├── tests/                 Pester tests and fixtures

└── README.md
```
