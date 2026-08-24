# ChannelForge Flight Manual

ChannelForge uses checklist discipline for important engineering operations.

Checklists are not a substitute for skill. They are how skilled engineers avoid preventable mistakes.

## Operating model

Every major change follows this lifecycle:

1. Preflight

2. Taxi

3. Takeoff

4. Cruise

5. Descent

6. Landing

7. Postflight

## Preflight

Before implementation begins:

- [ ] Requirement is understood.

- [ ] Scope is clear.

- [ ] Architecture impact is reviewed.

- [ ] Existing tests are reviewed.

- [ ] Security impact is considered.

- [ ] Backup or recovery needs are identified.

- [ ] Documentation impact is identified.

## Taxi

During implementation:

- [ ] Code follows the module layout.

- [ ] Code is readable before it is clever.

- [ ] Non-obvious logic is commented.

- [ ] No secrets are introduced.

- [ ] No production data is modified.

## Takeoff

Before commit:

- [ ] Relevant tests pass locally.

- [ ] Full unit test suite passes locally.

- [ ] New behavior has tests.

- [ ] Bug fixes have regression tests.

- [ ] Documentation is updated.

## Cruise

During review:

- [ ] Architecture is still clean.

- [ ] Function names clearly describe behavior.

- [ ] Inputs are validated.

- [ ] Errors are helpful.

- [ ] Comments explain intent.

- [ ] Beginner documentation is clear.

## Descent

Before merge:

- [ ] CI is green.

- [ ] Security review is complete.

- [ ] Backup/recovery behavior is reviewed.

- [ ] Generated output behavior is reviewed.

- [ ] No merge-blocking TODOs remain.

A green CI run and a merged pull request are review and merge evidence; they do
not authorize a release.

## Landing

For release:

- [ ] The canonical [Go / No-Go Checklist](GoNoGoChecklist.md) is complete.

- [ ] The exact candidate commit SHA, version/tag, CI run, and evidence record
      are recorded.

- [ ] The Product Owner / Engineering Manager has recorded the GO/NO-GO
      decision.

- [ ] Version is correct.

- [ ] Changelog is updated.

- [ ] Release notes are written.

- [ ] Tag is created.

- [ ] Release artifacts are verified.

## Postflight

After release or major feature completion:

- [ ] What surprised us?

- [ ] What should become a test?

- [ ] What should become a checklist item?

- [ ] What belongs in LESSONS_LEARNED.md?

- [ ] What can be simplified next?
