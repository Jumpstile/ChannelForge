# Contributing

## Prerequisite

Complete [ONBOARDING.md](ONBOARDING.md) before using this guide. This document assumes the repository, project rules, AI collaboration model, ADRs, and current project memory have already been reviewed.

If onboarding has not been completed, stop and start there.

## Workflow

1. Open or identify a GitHub Issue for the work and apply the [Issue Governance
   Standard](docs/reference/ISSUE_GOVERNANCE.md).
2. Confirm the evidence and acceptance criteria.
3. Create a focused branch.
4. Make the smallest change that solves the issue.
5. Update tests and documentation.
6. Run relevant checks.
7. Commit only intentional files.
8. Push and let CI verify the change.
9. Obtain review and merge through the authorized repository process; a green CI run is evidence, not release approval.

This is the normal workflow for an authorized contributor. It does not itself authorize an AI collaborator to create a branch, commit, push, merge, or release; those action boundaries are defined in [AI_COLLABORATION.md](AI_COLLABORATION.md).

## Documentation Sources

Repository docs are the engineering source of truth. Architecture decisions, security rules, release gates, templates, and contributor workflow belong in versioned repository files.

The [`docs/user/`](docs/user/README.md) directory is the user-facing knowledge base. It should explain first-run setup, common workflows, screenshots, troubleshooting, and examples for users.

When both need updates, update repository docs first, then update `docs/user/`.

For user-facing changes, issue and pull request completion summaries must state the repository docs review result and the `docs/user/` review result. Use [DOCUMENTATION.md](DOCUMENTATION.md) and [Documentation Governance Standard](docs/reference/DOCS_AND_WIKI.md) as the guide.

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

The [Go / No-Go Checklist](engineering/GoNoGoChecklist.md) is the canonical
release gate and decision record. For a release candidate:

- Complete the canonical checklist and the [release evidence
  template](docs/templates/release-checklist.md).
- Record the exact candidate commit SHA, version/tag, CI run, and supporting
  review evidence.
- Have the Product Owner / Engineering Manager record the GO/NO-GO decision.

A green CI run, pull-request approval, or merged pull request is review and
merge evidence; none is release approval by itself.
