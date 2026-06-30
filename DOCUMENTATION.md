# Documentation

Repository documentation is the engineering source of truth. GitHub Wiki is the user-facing knowledge base.

For the full standard, see [Documentation Governance Standard](docs/reference/DOCS_AND_WIKI.md).

## Wiki Status

Status: `Planned`

ChannelForge has not yet published its complete GitHub Wiki user knowledge base. Until the Wiki is published, repository docs remain the complete documentation set.

When available, the Wiki should live at the project Wiki URL and cover first-run setup, beginner usage, screenshots, common workflows, troubleshooting, feature guides, compatibility explanations, examples, and FAQ material.

## Repository Documentation

Core engineering documentation:

- [README](README.md)
- [Documentation governance](docs/reference/DOCS_AND_WIKI.md)
- [Constitution](CONSTITUTION.md)
- [Onboarding](ONBOARDING.md)
- [AI collaboration](AI_COLLABORATION.md)
- [Contributing](CONTRIBUTING.md)
- [Project guide](PROJECT.md)
- [Principles](PRINCIPLES.md)
- [Style guide](STYLEGUIDE.md)
- [Roadmap](ROADMAP.md)
- [Lessons learned](LESSONS_LEARNED.md)
- [Security reference](docs/reference/SECURITY.md)
- [Release checklist](docs/templates/release-checklist.md)
- [Developer guide](docs/developer/DEVELOPER_GUIDE.md)
- [Architecture docs](docs/architecture/)
- [Architecture Decision Records](docs/adr/)

## Release Blocker Status

No open release blockers. Issue #19 (historical provider token exposure in commit `91a3913`) is closed: the token was rotated 2026-06-28, and the Product Owner approved leaving Git history as-is (Option A). The decision and rationale are documented in [LESSONS_LEARNED.md](LESSONS_LEARNED.md) and [docs/reference/SECURITY.md](docs/reference/SECURITY.md).

## Documentation Completion Gate

When user-facing behavior changes, completion evidence must review both repository docs and Wiki docs.

Use these outcomes in pull requests, issue completion summaries, and release reviews:

- Repository docs updated or reviewed with no update needed.
- Wiki docs updated, reviewed with no update needed, marked as not enabled, or tracked as follow-up.

Do not duplicate full repository docs into the Wiki. Repository docs explain engineering truth; Wiki docs explain user-facing usage.
