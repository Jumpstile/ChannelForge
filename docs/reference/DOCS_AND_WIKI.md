# Documentation Governance Standard

## Rule

Repository documentation is the engineering source of truth. [`docs/user/`](../user/README.md) is the user-facing knowledge base.

Repository docs explain what is true for engineering: architecture, governance, safety rules, schemas, tests, security, release gates, and accepted decisions.

`docs/user/` explains how users succeed with the product: first-run setup, workflows, feature guides, examples, troubleshooting, and FAQ material.

**Why `docs/user/` instead of a GitHub Wiki:** the original design called for a GitHub Wiki as a separate, user-facing knowledge base. GitHub Wiki is not available on ChannelForge's current GitHub plan, so the same journey-based information architecture was implemented directly in the repository at `docs/user/` instead (see Issue #12). This keeps user documentation versioned and reviewed exactly like code, with no loss of architecture — if a GitHub Wiki ever becomes available, the page structure in `docs/user/` is designed to move there with minimal rework.

## Repository Documentation Set

Every Jumpstile project should consider these repository docs as part of its engineering documentation plan:

- `README.md`
- `DOCUMENTATION.md`
- `CONSTITUTION.md`
- `ONBOARDING.md`
- `AI_COLLABORATION.md`
- `CONTRIBUTING.md`
- `ROADMAP.md`
- `CHANGELOG` or changelog file
- `SECURITY.md` or repository security reference
- `LESSONS_LEARNED.md`
- `RELEASE-SAFETY-CHECKLIST.md` or release checklist template
- ADRs and architecture docs

Repository docs must change in the same branch as the engineering behavior they describe.

## `docs/user/` Documentation Set

Every Jumpstile project should consider these user-documentation areas when user-facing behavior changes:

- First-run guide
- Beginner user guide
- Common workflows
- Troubleshooting
- Feature guides
- Compatibility explanations
- Examples
- FAQ

`docs/user/` can be more tutorial-oriented and task-focused than repository engineering docs.

## Documentation Completion Gate

Every change must review both repository docs and `docs/user/` when user-facing behavior changes.

Pull requests, issue completion summaries, and release reviews should state one of these outcomes:

- Repository docs updated.
- Repository docs reviewed; no update needed.
- `docs/user/` updated.
- `docs/user/` reviewed; no update needed.
- `docs/user/` needs follow-up issue.

Release checklists must include a `docs/user/` review item for user-facing changes.

## Duplication Rule

Do not duplicate everything between repository docs and `docs/user/`.

Repository docs should explain engineering truth. `docs/user/` pages should explain user-facing usage and answer a specific user question or task, not restate engineering rules.

`README.md` and `DOCUMENTATION.md` link to [`docs/user/README.md`](../user/README.md) as the entry point. `docs/user/` pages link back to repository docs only when a user needs deeper technical detail.

If a `docs/user/` page describes behavior controlled by code, configuration, security policy, or release gates, the repository docs remain authoritative. Update repository docs first, then update `docs/user/`.

## Documentation Status Values

Use these values in `DOCUMENTATION.md` and release/issue summaries:

- `Not started`: no pages exist yet for this area.
- `In Progress`: some pages exist; the set is not yet complete.
- `Complete`: the planned page set exists and links validate.
- `Needs update`: pages exist but no longer match current user-facing behavior.

## ChannelForge User Documentation Status

Status: `Complete`

`docs/user/` covers the full approved journey-based architecture: `Home`, `What Is ChannelForge?`, `Build Your First Lineup`, `Safe Local Configuration`, `Use ChannelForge with Plex`, `Current Limitations`, `Troubleshooting`, `Contribute`, the `Concepts/` set, and the `Reference/` set, plus the pre-existing `THE_CHANNELFORGE_WAY.md` and `PLEX_SMOKE_TEST.md`. `QUICK_START.md` was relocated to `docs/developer/` — its content is a developer environment check, not end-user guidance. See [Issue #12](https://github.com/Jumpstile/ChannelForge/issues/12) for history.

## Issue Tracking

User documentation work should be tracked in GitHub Issues with the
`type:documentation` and appropriate `component:*` labels. Priority, status,
milestone, and relationship decisions follow the [Issue Governance
Standard](ISSUE_GOVERNANCE.md). User-facing issue completion summaries should
explicitly state the repository docs and `docs/user/` review result.
