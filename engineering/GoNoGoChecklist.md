# Go / No-Go Checklist

A release is not ready because it works locally.

A release is ready only when we are willing to stand behind it.

This is the canonical release gate and decision checklist. Pull-request review
and CI results are merge evidence; they do not replace this checklist or
authorize a release. The Product Owner / Engineering Manager records the final
GO/NO-GO decision. Contributors and agents may gather evidence and recommend a
decision, but they do not self-authorize a release.

## Candidate identity

- [ ] Release-candidate commit SHA is recorded.

- [ ] Version and tag are recorded.

- [ ] CI workflow run and relevant local test environment are recorded.

- [ ] Release issue, pull request, and evidence record are linked.

- [ ] Validation used an independent local clone or local Git worktree, not a
      shared SMB/NAS Git worktree.

- [ ] Local branch, exact HEAD, origin ref, clean status, and expected ancestry
      or baseline are recorded.

- [ ] Any NAS or mapped paths used for data, outputs, caches, staging, evidence,
      backups, packages, mirrors, or deployment are identified by role and
      pass their canonical-containment checks; they are not Git-worktree
      evidence.

## Engineering

- [ ] Full test suite passes locally.

- [ ] CI is green.

- [ ] PSScriptAnalyzer is clean or documented.

- [ ] Code review is complete.

- [ ] No release-blocking TODOs remain.

## Security

- [ ] Deep bug sweep completed.

- [ ] Vulnerability review completed.

- [ ] Secrets scan completed.

- [ ] Path validation reviewed.

- [ ] Input validation reviewed.

- [ ] Logging reviewed for secret leakage.

- [ ] Dependency review completed.

## Safety

- [ ] Pre-operation backup tested.

- [ ] Post-operation backup tested.

- [ ] Restore process tested.

- [ ] Production writes require explicit approval.

- [ ] Failure modes are documented.

## Documentation

- [ ] README updated.

- [ ] PROJECT.md updated if needed.

- [ ] STYLEGUIDE.md updated if needed.

- [ ] ADRs updated if architecture changed.

- [ ] Beginner instructions verified.

- [ ] Troubleshooting notes updated.

## User Experience

- [ ] Fresh install tested.

- [ ] Upgrade tested.

- [ ] Error messages are understandable.

- [ ] Success messages are clear.

- [ ] User can verify outcome.

## Decision

- [ ] GO

- [ ] NO-GO

If any required item is incomplete, the decision is NO-GO.
