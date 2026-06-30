# Documentation Governance Standard

## Rule

Repository documentation is the engineering source of truth. GitHub Wiki is the user-facing knowledge base.

Repository docs explain what is true for engineering: architecture, governance, safety rules, schemas, tests, security, release gates, and accepted decisions.

Wiki docs explain how users succeed with the product: first-run setup, workflows, screenshots, feature guides, examples, troubleshooting, and FAQ material.

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

## GitHub Wiki Documentation Set

Every Jumpstile project should consider these Wiki areas when user-facing behavior changes:

- First-run guide
- Beginner user guide
- Screenshots
- Common workflows
- Troubleshooting
- Feature guides
- Compatibility explanations
- Examples
- FAQ

The Wiki can be more tutorial-oriented, screenshot-heavy, and task-focused than repository engineering docs.

## Documentation Completion Gate

Every change must review both repository docs and Wiki docs when user-facing behavior changes.

Pull requests, issue completion summaries, and release reviews should state one of these outcomes:

- Repository docs updated.
- Repository docs reviewed; no update needed.
- Wiki docs updated.
- Wiki docs reviewed; no update needed.
- Wiki docs need follow-up issue.
- Wiki is not enabled or not yet published.

Release checklists must include a Wiki review item for user-facing changes.

## Duplication Rule

Do not duplicate everything between repository docs and the Wiki.

Repository docs should explain engineering truth. Wiki pages should explain user-facing usage.

`README.md` and `DOCUMENTATION.md` should link to the Wiki when it is available. Wiki pages should link back to repository docs only when users need deeper technical detail.

If a Wiki page describes behavior controlled by code, configuration, security policy, or release gates, the repository docs remain authoritative. Update repository docs first, then update the Wiki.

## Wiki Status Values

Use these values in `DOCUMENTATION.md` and release/issue summaries:

- `Not enabled`: GitHub Wiki is unavailable for the repository.
- `Planned`: Wiki is expected, but user-facing pages are not yet drafted.
- `Drafted`: Wiki content exists but is not ready as the user-facing reference.
- `Published`: Wiki content is live and current for users.
- `Needs update`: Wiki exists but no longer matches current user-facing behavior.

## ChannelForge Wiki Status

Status: `Planned`

ChannelForge tracks user-facing Wiki work separately from engineering documentation. Until the Wiki is published, repository docs remain the only complete documentation set.

## Issue Tracking

Wiki work should be tracked in GitHub Issues with documentation labels. User-facing issue completion summaries should explicitly state the repository docs and Wiki review result.
