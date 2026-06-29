# Contributing (Developer Reference)

> Status: Living document

## Purpose

This page is the code-level companion to the root [CONTRIBUTING.md](../../CONTRIBUTING.md), which defines the contribution workflow, review rules, and release discipline. Read that document first. This page covers the mechanics of making a change inside `src/ChannelForge`.

## Audience

Future contributors and maintainers making code changes.

## Before you start

- Complete [ONBOARDING.md](../../ONBOARDING.md).
- Read [FIRST_READ.md](FIRST_READ.md).
- Identify or open the GitHub Issue the change addresses.

## Local setup

See [INSTALL.md](../reference/INSTALL.md) for PowerShell 7, Git, and Pester setup.

## Making a code change

1. Find the relevant layer in [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) — domain (`Classes/`), application (`Public/`, `Private/`), or infrastructure.
2. Follow [STYLEGUIDE.md](../../STYLEGUIDE.md) for naming, comments, error handling, and validation.
3. Add or update a Pester test in `tests/unit` for every behavior change, including malformed/edge-case input.
4. Run the test suite locally:

   ```powershell
   Invoke-Pester ./tests/unit
   ```

5. Update the relevant doc (`ARCHITECTURE.md`, `DEVELOPER_GUIDE.md`, `README.md`, or an ADR) if the change affects structure, public behavior, or an accepted decision.

## Security checks before committing

- No real provider or EPG URLs, account IDs, tokens, usernames, or passwords in tracked files. Use `https://example.invalid/...` placeholders (see [SECURITY.md](../reference/SECURITY.md)).
- No generated playlists, XMLTV files, databases, logs, or backups staged for commit.
- Real local configuration belongs only in ignored `*.local.json` / `*.local.csv` files.

## Pull requests

Follow the workflow and review rules in the root [CONTRIBUTING.md](../../CONTRIBUTING.md): focused branch, smallest change that solves the issue, tests and docs updated, CI green before merge.
