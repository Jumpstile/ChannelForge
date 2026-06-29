# Bug Sweep Checklist

Use this checklist before release or before merging risky behavior.

## Scope

- [ ] Issue or milestone identified.
- [ ] Changed files reviewed.
- [ ] User-facing workflows identified.
- [ ] Production-impacting paths identified.

## Correctness

- [ ] Happy path tested.
- [ ] Empty input tested.
- [ ] Missing file tested.
- [ ] Malformed input tested.
- [ ] Duplicate input tested.
- [ ] Ordering is deterministic.
- [ ] Errors are understandable.

## Regression

- [ ] Existing behavior reviewed.
- [ ] Existing tests still pass.
- [ ] New regression tests added for fixed bugs.
- [ ] Backward compatibility reviewed.

## Recovery

- [ ] Failure mode is documented.
- [ ] User can verify outcome.
- [ ] Rollback or recovery path exists where needed.

## Issues

- [ ] New bugs or follow-ups captured in GitHub Issues.
