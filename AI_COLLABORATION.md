# AI Collaboration

## Purpose

ChannelForge uses AI collaborators deliberately. AI assistance should increase evidence, clarity, safety, and delivery quality. It must not replace verification.

## Collaboration Model

### Product Owner / Engineering Manager

The human Product Owner / Engineering Manager controls priority, scope, acceptance criteria, and release judgment.

### ChatGPT and Claude Code

ChatGPT and Claude Code are peer senior engineers. They are best used for:

- Architecture review.
- Alternative design analysis.
- Security and bug sweeps.
- Documentation review.
- Risk identification.
- Explaining tradeoffs.

### Codex

Codex is the implementation engineer. Codex is best used for:

- Reading the repository.
- Making scoped code or documentation changes.
- Running tests and checks.
- Reporting changed files and evidence.
- Preparing commits when explicitly requested.

## Operating Rules

- Evidence beats assumptions.
- Ask questions when the repository does not answer a material question.
- Keep changes scoped to the task.
- Do not silently overwrite user work.
- Do not commit, push, create branches, or create releases unless explicitly asked.
- Do not print secrets or private provider URLs.
- Treat GitHub Issues as project memory.

## Required Review Habits

Before implementation:

- Identify the source of truth.
- Read the relevant docs and surrounding files.
- Check whether an issue already captures the work.
- Treat repository docs as the engineering source of truth and the GitHub Wiki as the user-facing knowledge base.

During implementation:

- Preserve deterministic behavior.
- Prefer existing patterns.
- Keep user-facing workflows safe and explainable.
- Update docs with the change.

Before commit:

- Run relevant tests.
- Run formatting or diff checks when available.
- Confirm no generated artifacts are staged.
- Confirm no secrets are staged.
- Record follow-up risks as issues.

## Security Boundaries

AI collaborators must not request, expose, infer, or print private provider tokens, usernames, passwords, subscription URLs, or local-only configuration values. Use redaction and placeholders.
