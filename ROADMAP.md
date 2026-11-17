# Roadmap

The milestones below match the GitHub milestones. Work goes in this order: get the guides and events right, ship a first usable alpha, then build the rest on top of it. Issue numbers are listed on GitHub, which is the source of truth.

Older documents (some ADRs and code comments) cite "Roadmap Milestone 0" to "Roadmap Milestone 5" from before 2026-11-16. That old numbering maps to the milestones below like this:

- Old Milestone 0 (Engineering Foundation) is Milestone 0.
- Old Milestone 1 (Alias Engine) and old Milestone 2 (Confidence Engine) are Milestone 4.
- Old Milestone 3 (GUI Foundation) is Milestone 3.
- Old Milestone 4 (Provider/EPG Engine) is Milestone 1.
- Old Milestone 5 (Production Build) is Milestones 2 and 5.

## Milestone 0 - Engineering Foundation and Direction

Goal: make the project safe, understandable, and durable before expanding features.

Expected outcomes:

- Constitution and collaboration rules.
- Contribution workflow.
- ADR process and template.
- Bug, vulnerability, and release checklists.
- Lessons learned discipline.
- GitHub Issues as project memory.
- Automated secret scanning.
- Path-safety checks at every place that writes a file.

## Milestone 1 - Guides and Events

Goal: build a correct guide for every channel, including live-event channels, with no manual steps.

Expected outcomes:

- Provider and guide source validation.
- Guide (EPG) acquisition and deterministic merge, with provenance.
- Logos and categories checked before a user accepts anything.
- Guided setup with multiple sources.
- Automatic event guides: finding event channels, agreeing on event times, and a guide entry for each.
- Optional per-channel override when the automatic guess is wrong.

## Milestone 2 - First Usable Alpha

Goal: a person can install ChannelForge and get a working lineup and guide.

Expected outcomes:

- Target-specific outputs that are deterministic.
- Parity with the everyday features of the tool it replaces.
- Integration checks for paths, permissions, and reachability.
- Windows portable bundle with upgrade and a clean-machine test.
- The First Usable Alpha release checklist.

## Milestone 3 - Review UX and GUI

Goal: a first GUI-first workflow for preview, review, approval, and recovery.

Expected outcomes:

- Workflow map.
- Preview surface.
- Approval states.
- Explainable decisions surfaced to users.
- Recovery path for mistakes.

## Milestone 4 - Identity and Registry

Goal: make channel identity deterministic, explainable, and reviewable, then score the evidence.

Expected outcomes:

- Canonical alias model, conflict detection, and review reports.
- Safe fallback when no alias is known.
- Evidence model, confidence scoring, and drift detection.
- Review queue for ambiguous matches.
- Station registry and fast local storage.

### Current slice status

Stage A and Stage B now provide the read-only evidence and native event-pattern candidate contracts. Stage B accepts representative examples or Stage A evidence, extracts structured channel/event fields, normalizes and cross-checks timezone representations, reports deterministic confidence/provenance/review state, and detects naming drift without adopting or publishing a rule. Schedule adapters, persistent learned knowledge, expert overrides, automatic relearning, and guide publication remain future work.

## Milestone 5 - Source Operations and Stream Health

Goal: keep sources healthy and recover safely when something breaks.

Expected outcomes:

- Source refresh status, change previews, and last-known-good recovery.
- Bounded stream-health checks and stable fallback order.
- Desired-state reconciliation with verified deploys.
- Backup pools and a Plex channel budget.
- Backup and restore workflow.

## Milestone 6 - Policy and Extensibility

Goal: shareable policy and a stable way to add adapters.

Expected outcomes:

- Versioned policy packs and safe sync.
- AI-assisted rule authoring that is review-only.
- A stable adapter SDK.

## Milestone 7 - Autonomous Operations

Goal: scheduled operations that need little attention.

Expected outcomes:

- Scheduled refresh and notifications.
- Bounded capacity tests.
- Optional viewing analytics.

## Milestone 8 - Cross-Service Discovery and Future Scope

Goal: backlog only. One guide across linear TV and streaming services. It is not part of the active lineup work.
