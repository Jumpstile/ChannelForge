# Documentation

Repository documentation is the engineering source of truth. [`docs/user/`](docs/user/README.md) is the user-facing knowledge base.

For the full standard, see [Documentation Governance Standard](docs/reference/DOCS_AND_WIKI.md).

## User Documentation Status

Status: `Complete`

ChannelForge's user-facing documentation lives in [`docs/user/`](docs/user/README.md), versioned and reviewed in the repository alongside the code, not published as a separate GitHub Wiki — **GitHub Wiki is not available on the current GitHub plan.** The same journey-based information architecture originally designed for a Wiki was adopted directly into `docs/user/`, so a future migration to a GitHub Wiki (if the plan ever changes) is a straightforward content move, not a redesign.

`docs/user/` covers the full approved journey-based architecture, reviewed for completeness and coherence in [Issue #12](https://github.com/Jumpstile/ChannelForge/issues/12). The rest of the repository's engineering documentation remains the canonical reference for engineering-level detail that `docs/user/` intentionally summarizes and links to rather than duplicates.

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
- [User documentation](docs/user/README.md)

## Release Blocker Status

No open release blockers. Issue #19 (historical provider token exposure in commit `91a3913`) is closed: the token was rotated 2026-06-28, and the Product Owner approved leaving Git history as-is (Option A). The decision and rationale are documented in [LESSONS_LEARNED.md](LESSONS_LEARNED.md) and [docs/reference/SECURITY.md](docs/reference/SECURITY.md).

## Documentation Completion Gate

When user-facing behavior changes, completion evidence must review both repository engineering docs and `docs/user/`.

Use these outcomes in pull requests, issue completion summaries, and release reviews:

- Repository docs updated or reviewed with no update needed.
- `docs/user/` updated, reviewed with no update needed, or tracked as follow-up.

Do not duplicate full repository engineering docs into `docs/user/`. Repository docs explain engineering truth; `docs/user/` explains user-facing usage and links to repository docs for deeper detail.
