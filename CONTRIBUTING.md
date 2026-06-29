# Contributing

## Prerequisite

Complete [ONBOARDING.md](ONBOARDING.md) before using this guide. This document assumes the repository, project rules, AI collaboration model, ADRs, and current project memory have already been reviewed.

If onboarding has not been completed, stop and start there.

## Workflow

1. Open or identify a GitHub Issue for the work.
2. Confirm the evidence and acceptance criteria.
3. Create a focused branch.
4. Make the smallest change that solves the issue.
5. Update tests and documentation.
6. Run relevant checks.
7. Commit only intentional files.
8. Push and let CI verify the change.

## Documentation Sources

Repository docs are the engineering source of truth. Architecture decisions, security rules, release gates, templates, and contributor workflow belong in versioned repository files.

The GitHub Wiki is the user-facing knowledge base. It should explain first-run setup, common workflows, screenshots, troubleshooting, and examples for users.

When both need updates, update repository docs first, then update the Wiki.

## Commit Rules

- Tests before commits.
- Documentation is part of the product.
- Do not commit generated reports, logs, backups, local config, or secrets.
- Do not commit real provider URLs.
- Use clear commit messages that explain the user-visible or engineering purpose.
- Do not add AI/tool attribution footers or a `Co-Authored-By:` trailer to commit
  messages unless explicitly requested (see [AI_COLLABORATION.md](AI_COLLABORATION.md)).

## Review Rules

Every change should be reviewed for:

- Correctness.
- Determinism.
- Security.
- Regression risk.
- Documentation.
- User experience.
- Recovery and rollback when production data may be touched.

## Release Discipline

No release is ready until:

- CI is green.
- Relevant tests pass locally.
- Bug sweep is complete.
- Vulnerability sweep is complete.
- Documentation is current.
- Release checklist is complete.
