# Roadmap

## Milestone 0 - Engineering Foundation

Goal: make the project safe, understandable, and durable before expanding features.

Expected outcomes:

- Constitution and collaboration rules.
- Contribution workflow.
- ADR process and template.
- Bug, vulnerability, and release checklists.
- Lessons learned discipline.
- GitHub Issues as project memory.
- Automated secret scanning.

## Milestone 1 - Alias Engine

Goal: make alias resolution deterministic, explainable, and reviewable.

Expected outcomes:

- Canonical alias model.
- Alias conflict detection.
- Alias review reports.
- Regression tests for known aliases.
- Safe fallback when no alias is known.

## Milestone 2 - Confidence Engine

Goal: score channel identity evidence and explain confidence.

Expected outcomes:

- Evidence model.
- Confidence scoring.
- Drift detection.
- Explainable decision reports.
- Review queue for ambiguous matches.

## Milestone 3 - GUI Foundation

Goal: establish the first GUI-first workflow for preview, review, approval, and recovery.

Expected outcomes:

- Workflow map.
- Preview surface.
- Approval states.
- Explainable decisions surfaced to users.
- Recovery path for mistakes.

## Milestone 4 - Provider/EPG Engine

Goal: make provider and EPG ingestion reliable, validated, and source-of-truth driven.

Expected outcomes:

- Provider source validation.
- EPG source validation.
- Local-only provider config workflow.
- Deterministic fixture inputs.
- CI validation for source data.

## Milestone 5 - Production Build

Goal: produce guarded production outputs with backups, approval gates, and release discipline.

Expected outcomes:

- Deterministic build outputs.
- Path-safety checks.
- Explicit production approval.
- Backup and restore workflow.
- Release checklist enforcement.
