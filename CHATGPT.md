# ChannelForge

ChannelForge is an evidence-driven PowerShell project for building accurate, trustworthy, deterministic television lineups from provider data, local rules, and guide sources.

## Required Reading

Before engineering work begins, read in this order:

1. [ONBOARDING.md](ONBOARDING.md) — environment verification, project rules, and implementation prerequisites
2. [CONSTITUTION.md](CONSTITUTION.md) — core principles, roles, and definition of done
3. [AI_COLLABORATION.md](AI_COLLABORATION.md) — operating rules, review habits, and security boundaries
4. [docs/reference/SECURITY.md](docs/reference/SECURITY.md) — secrets policy and local provider file conventions
5. ADRs in [docs/adr/](docs/adr/) — accepted architecture decisions (0001–0005)
6. [ROADMAP.md](ROADMAP.md) — milestones and current phase; review before choosing work

## Session Startup Checklist

Before any engineering session:

- [ ] Confirm the working directory is the ChannelForge repository.
- [ ] Run `git status` and `git remote -v`.
- [ ] Confirm the checkout is local and follows [ADR 0015](docs/adr/0015-local-worktrees-and-github-handoffs.md); do not use a shared NAS Git worktree.
- [ ] Confirm `src/`, `tests/`, `docs/`, and `data/` are present.
- [ ] Review open GitHub Issues relevant to the planned work.
- [ ] Identify the source of truth for the change.

## Engineering Non-Negotiables

| Rule                                                             | Canonical source                                                                        |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Evidence before implementation                                   | [ADR 0005](docs/adr/0005-evidence-over-assumptions.md)                                  |
| Tests before commits                                             | [ENGINEERING_PRINCIPLES.md](docs/engineering/ENGINEERING_PRINCIPLES.md)                 |
| Secrets never in Git                                             | [ADR 0002](docs/adr/0002-secrets-policy.md) · [SECURITY.md](docs/reference/SECURITY.md) |
| No commit, push, branch, or release without explicit instruction | [AI_COLLABORATION.md](AI_COLLABORATION.md)                                              |
| No silent overwrite of user work                                 | [CONSTITUTION.md](CONSTITUTION.md)                                                      |
| GitHub Issues are project memory                                 | [CONSTITUTION.md](CONSTITUTION.md)                                                      |
| Repository docs are the engineering source of truth              | [ADR 0001](docs/adr/0001-source-of-truth.md)                                            |

## Documentation Synchronization

When user-facing behavior changes, both repository docs and the GitHub Wiki must be reviewed. Record the outcome in the issue or pull request. See [DOCUMENTATION.md](DOCUMENTATION.md) and [DOCS_AND_WIKI.md](docs/reference/DOCS_AND_WIKI.md).

## Role

See [AI_COLLABORATION.md](AI_COLLABORATION.md) for the peer senior engineer role.

Architecture review, alternative design analysis, security and bug sweeps, documentation review, and risk identification are the primary contributions expected from this role.
