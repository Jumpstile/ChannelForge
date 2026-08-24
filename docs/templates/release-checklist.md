# Release Checklist

Use this template to record evidence for a release candidate before tagging or
publishing. The canonical release gates and decision rule are in the
[Go / No-Go Checklist](../../engineering/GoNoGoChecklist.md); this template
does not replace that checklist or authorize a release.

## Candidate identity

- Commit SHA:
- Version/tag:
- CI workflow run(s):
- Release issue or pull request:
- Evidence record:

## Build and Tests

- [ ] Working tree is clean.
- [ ] Full test suite passes locally.
- [ ] CI is green.
- [ ] Secret scanning passes.
- [ ] PSScriptAnalyzer is clean or documented.
- [ ] Generated artifacts are intentional.

## Review

- [ ] Bug sweep completed.
- [ ] Vulnerability sweep completed.
- [ ] Code review is complete.
- [ ] Dependency review is complete.
- [ ] Repository documentation reviewed.
- [ ] `docs/user/` documentation reviewed for user-facing changes.
- [ ] ADRs updated if architecture changed.
- [ ] Open release blockers reviewed.

## Safety

- [ ] Production-impacting changes require explicit approval.
- [ ] Backup process verified.
- [ ] Restore process verified or documented.
- [ ] Failure modes documented.
- [ ] Path and input validation reviewed.
- [ ] Logging reviewed for secret leakage.

## User Experience

- [ ] Beginner-facing instructions are current.
- [ ] Success criteria are clear.
- [ ] Error messages are understandable.
- [ ] User can verify outcome.

## Decision

- Decision owner (Product Owner / Engineering Manager):
- Decision evidence:

- [ ] GO
- [ ] NO-GO

If any required item is incomplete, the release decision is NO-GO.
