# Issue Governance Standard

> Status: Living document

## Purpose

GitHub Issues are durable project memory for scope, evidence, decisions,
follow-ups, and relationships. This standard defines the minimum classification
and triage record for new work. An issue records and coordinates work; it does
not override the Constitution or independently authorize a merge or release.

## Required classification

During triage, every active issue must have:

- Exactly one `type:*` label.
- Exactly one `priority:*` label.
- At least one `component:*` label.
- Exactly one `status:*` label.
- A milestone assignment, or an explicit record that no milestone has been
  accepted yet.
- A relationships section listing related issues and pull requests, or
  `None` when no relationship is known.

Use the repository's namespaced labels for new work. Common examples include
`type:bug`, `type:documentation`, `type:feature`, `type:governance`,
`type:security`, `type:technical-debt`, and `type:ux`; `priority:critical`,
`priority:high`, `priority:medium`, and `priority:low`; the applicable
`component:*` label; and a status such as `status:needs-design`,
`status:needs-investigation`, `status:ready`, `status:in-progress`,
`status:blocked`, or `status:verified`. Do not add a new label when an
existing namespaced label expresses the classification.

Templates may set a type, an unambiguous component, and an initial status. They
must not guess priority or milestone. The Product Owner / Engineering Manager
owns priority, scope, acceptance criteria, milestone decisions, risk
acceptance, and landing or release judgment.

## Status meaning

- `status:needs-design`: the problem or acceptance boundary still needs
  deliberate definition.
- `status:needs-investigation`: the evidence or root cause is not yet known.
- `status:ready`: scope and acceptance criteria are clear enough to begin.
- `status:in-progress`: authorized work is actively underway.
- `status:blocked`: a documented dependency prevents progress.
- `status:verified`: the stated result is confirmed by recorded evidence.

Do not mark an issue `ready` or `verified` merely because a discussion exists
or a related pull request is open.

## Relationships and evidence

Record relationships with explicit GitHub issue or pull-request links. Use
phrasing such as `Related to #N`, `Blocks #N`, `Blocked by #N`, or `Duplicate
of #N` when the relationship does not intentionally close an issue. Use
`Fixes #N` or `Closes #N` only when the authorized change is intended to close
that issue and its acceptance criteria are complete.

Issue and pull-request evidence should identify the exact branch or commit,
changed scope, validation results, and any deferred criteria. A successful CI
run or merged pull request is review evidence, not release evidence; release
decisions follow the [Go / No-Go Checklist](../../engineering/GoNoGoChecklist.md).

## Template rule

Every issue template must link to this standard and provide a place to record
the priority, component, status, milestone, and relationship decisions during
triage. Existing issues are not silently migrated by changing a template; any
taxonomy correction to an existing issue must be recorded deliberately.
