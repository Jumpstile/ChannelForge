# ChannelForge

<p align="center">

  <strong>One source. Many outputs. Zero guesswork.</strong>

</p>

<p align="center">

  An evidence-driven television knowledge engine for building accurate, trustworthy, deterministic channel lineups.

</p>

<p align="center">

  <img alt="Status" src="https://img.shields.io/badge/status-early%20alpha-orange">

  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-7%2B-blue">

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

- Deterministic merged M3U output from local playlists (alias resolution, numbering, dedup), plus Build-Lineup integration for configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` sources with source-aware programme binding/merge and deterministic XMLTV output; remote acquisition remains deferred

- `BuildContext` domain object

- `Channel` domain object

- Channel normalization

- Architecture Decision Records

- Documentation architecture

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

- [Repository docs and GitHub Wiki](docs/reference/DOCS_AND_WIKI.md)

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
