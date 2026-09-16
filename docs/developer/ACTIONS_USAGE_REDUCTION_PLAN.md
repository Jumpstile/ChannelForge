# ChannelForge Actions Usage Reduction Plan

**Authorization status:** This plan is non-authorizing. It does not authorize workflow edits, pushes, pull requests, releases, packages, deployments, tester builds, or hosted CI execution.

## Preserve required coverage

- Keep `secret-scan` first and required.
- Keep `quality-gates` dependent on `secret-scan` and required.
- Preserve full-history secret scanning.
- Preserve exact-head validation and pinned canonical-content validation.
- Preserve full Pester, PSScriptAnalyzer, config schema validation, Markdown hygiene, Markdown link checks, GUI typecheck/tests/build, and Rust/Tauri checks while they remain part of `quality-gates`.
- Preserve main-branch validation for every applicable main run.
- Preserve concurrency cancellation for superseded PR runs; do not cancel or skip main-branch validation.

## Low-risk cache improvements

1. Configure npm cache dependency paths to include both the root `package-lock.json` and `gui/package-lock.json`, because the workflow installs both dependency trees.
2. Cache Cargo registry and git directories plus `gui/src-tauri/target` using keys that include runner OS and the Tauri `Cargo.lock` hash.
3. Treat cache misses and restore failures as ordinary misses; never use them to skip a check.
4. Keep deterministic pinned setup versions instead of relying on runner preinstalls.

## Run and retry discipline

- Avoid duplicate reruns for unchanged failures.
- Classify failure causes before retrying: billing/usage, runner/setup, dependency, test/code, or infrastructure.
- For polling, use `gh run view <run-id> --json status,conclusion,jobs`.
- Avoid long `gh run watch` loops that consume attention and can encourage unnecessary retries.
- Use hosted CI only after local gates are clean, the exact-head checkpoint is coherent, the packet is internally consistent, advisor/blocker notes are resolved, and the intended PR state is clear.

## Reductions not approved

- No path filters that bypass engine, accepted-state, source acquisition, web-server, UI, schema, documentation, or security validation.
- No removal or weakening of required checks.
- No splitting or filtering of full Pester without a separate test-contract decision.
- No silent removal of Rust/Tauri validation while it is part of `quality-gates`.
- No duplicate-workflow removal is indicated; the repository has one CI workflow.

This plan remains informational only. It does not authorize workflow edits, pushes, PR creation, releases, packages, deployments, tester builds, or hosted CI execution.
