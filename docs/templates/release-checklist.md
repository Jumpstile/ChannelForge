# Release Checklist

Use this checklist before tagging or publishing a release.

## Build and Tests

- [ ] Working tree is clean.
- [ ] Full test suite passes locally.
- [ ] CI is green.
- [ ] Secret scanning passes.
- [ ] Generated artifacts are intentional.

## Review

- [ ] Bug sweep completed.
- [ ] Vulnerability sweep completed.
- [ ] Repository documentation reviewed.
- [ ] Wiki documentation reviewed for user-facing changes.
- [ ] ADRs updated if architecture changed.
- [ ] Open release blockers reviewed.

## Safety

- [ ] Production-impacting changes require explicit approval.
- [ ] Backup process verified.
- [ ] Restore process verified or documented.
- [ ] Failure modes documented.

## User Experience

- [ ] Beginner-facing instructions are current.
- [ ] Success criteria are clear.
- [ ] Error messages are understandable.
- [ ] User can verify outcome.

## Decision

- [ ] GO
- [ ] NO-GO

If any required item is incomplete, the release decision is NO-GO.
