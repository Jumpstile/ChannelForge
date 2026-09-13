# Product Intent-Fit Audit

## Standing gate

Passing tests is necessary but not sufficient for a ChannelForge change. Before a
slice is handed to a tester, merged, packaged, released, deployed, or called
ready, a reviewer must compare the written behavior with the behavior the slice
was intended to implement.

The review must answer, from source and evidence:

1. What behavior was intended?
2. Which entry points implement it?
3. What state, files, providers, downstream systems, and reports can change?
4. What behavior is deliberately blocked or deferred?
5. Do tests and documentation verify the intended boundary rather than merely
   exercising code paths?

If the implementation does not fit intent, hold the slice and record the gap.
Do not hand an unreviewed slice to a tester as a discovery mechanism. A green CI
run proves that configured checks passed; it does not replace this review.

## Required PR evidence

Every behavior-changing PR must include an intent-fit note in its description,
review record, or linked issue containing:

- the intended behavior and the exact entry points;
- the files and tests inspected;
- the safety boundary, including accepted-state, provider, downstream, and
  guide-publication effects;
- any report redaction and output-path boundary;
- `PASS`, `PASS_WITH_GAPS`, `HOLD`, or `NOT_REVIEWED` disposition;
- follow-up issue references for every material gap.

Documentation-only changes still need a scope check. A reviewer may state that
implementation behavior was not affected, but must not skip the check silently.

## Review procedure

Use a clean worktree from the exact proposed base and inspect source before
relying on test counts. Trace the normal path and the failure path. Confirm that
writes are confined to documented roots, that candidate and accepted state have
one authority, and that user-facing reports do not expose private source values.
Then compare relevant tests and documentation with the intended behavior.

Allowed dispositions:

- **PASS** — source behavior fits intent and relevant evidence covers the
  boundary.
- **PASS_WITH_GAPS** — the intended path is present, but a material guard,
  coverage, schema, or documentation gap remains and is recorded.
- **HOLD** — behavior conflicts with intent, or a safety boundary is not
  trustworthy enough to hand off.
- **NOT_REVIEWED** — the area was deliberately outside the slice and remains
  unassessed; it is not approval.

## Issue #141 baseline audit

Base reviewed: `4a789f86815b8d2a5df8a2f6305b603c0b0693aa` after PR #140.

Evidence includes source inspection, the relevant repository tests, and the
successful post-merge PowerShell CI run #219 (`34765711793`) for that exact
base. Tests were used as boundary evidence; test counts alone were not treated
as intent-fit approval.

| Area                                              | Intended behavior                                                                                                                                                                                  | Entry points                                                                                                                                                                                 | Files reviewed                                                                                                                                                                                                                            | Evidence                                                                                                                                                                                                             | Gaps                                                                                                                                                                                         | Disposition    |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Candidate lineup build                            | Build deterministic M3U/XMLTV candidate artifacts and review reports without touching public or accepted outputs.                                                                                  | `scripts/Build-Lineup.ps1`, candidate namespace helpers                                                                                                                                      | `scripts/Build-Lineup.ps1`; `src/ChannelForge/Private/Publish-ChannelForgeCandidateNamespace.ps1`; `src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1`                                                                       | Candidate-only tests preserve public and rollback bytes, reuse deterministic namespaces, and redact candidate reports.                                                                                               | None found in the reviewed path.                                                                                                                                                             | PASS           |
| Guided Setup / Beginner Workflow                  | Explain a proposal, require explicit acceptance for publication, and keep Stage D event-pattern preview report-only.                                                                               | `scripts/Build-My-Lineup.ps1`                                                                                                                                                                | `scripts/Build-My-Lineup.ps1`; `tests/unit/BuildMyLineup.Tests.ps1`; `docs/user/Build-Your-First-Lineup.md`; `docs/user/Reference/CLI-Reference.md`                                                                                       | Proposal, stale-candidate, acceptance, deterministic-report, redaction, and event-preview tests; source routes real acceptance through the generation publication boundary.                                          | The consumer view is a derived `output/guided-setup/accepted` projection and needs to remain documented as non-authoritative.                                                                | PASS           |
| Source refresh planner and executor               | Plan from validated cache evidence; refresh disposable caches only; preserve last-known-good content; never publish or change accepted output.                                                     | `scripts/Get-ChannelForgeSourceRefreshPlan.ps1`, `scripts/Invoke-ChannelForgeSourceRefresh.ps1`                                                                                              | Both scripts; `src/ChannelForge/Public/Get-ChannelForgeSourceRefreshPlan.ps1`; configured source importers; `schemas/source-refresh-result.schema.json`                                                                                   | Planner and executor tests cover cache states, deterministic reports, no accepted/generation output, failed-refresh preservation, and redaction.                                                                     | Wrapper-level `OutputRoot`/`CacheRoot` inputs are not consistently checked with `Assert-ChannelForgeWritePath`; a caller can direct report/cache writes outside the documented output roots. | PASS_WITH_GAPS |
| Scheduled refresh wrapper and registration/status | Require a validated eligible plan, bounded execution, one owned task/lock identity, explicit install/remove approval, and no accepted-state mutation.                                              | `scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1`, `Install-ChannelForgeScheduledRefresh.ps1`, `Get-ChannelForgeScheduledRefreshStatus.ps1`, `Uninstall-ChannelForgeScheduledRefresh.ps1` | Scheduled scripts; `src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1`; scheduled schemas; `tests/unit/ScheduledRefreshPlanner.Tests.ps1`; `ScheduledRefreshRun.Tests.ps1`; `ScheduledRefreshRegistration.Tests.ps1` | Tests cover ineligible-plan blocking, exactly-once executor invocation, lock/report contracts, task ownership, explicit approval, UTC boundaries, and registration redaction.                                        | Scheduled installation intentionally changes the OS task scheduler after explicit approval; this is documented operational mutation, not an unattended lineup mutation.                      | PASS           |
| M3U import, normalization, merge, and export      | Parse untrusted playlist structure, preserve original names, normalize deterministically, resolve aliases, deduplicate and number deterministically, and export only caller-approved output.       | `Import-ChannelForgeM3UPlaylist`, `ConvertTo-ChannelForgeNormalizedChannel`, `Merge-ChannelForgeLineup`, `Export-ChannelForgeM3UPlaylist`                                                    | Public M3U/normalization/merge/export functions; private reader and safe entry serializer; `tests/unit/M3UPlaylist.Tests.ps1`; `Normalization.Tests.ps1`; `MergeChannelForgeLineup.Tests.ps1`                                             | Tests cover malformed input, identity fields, original-name preservation, alias/dedup/numbering behavior, order independence, and deterministic output.                                                              | The low-level M3U exporter relies on its caller to apply `Assert-ChannelForgeWritePath`; the production caller does so, but the API contract is caller-dependent.                            | PASS_WITH_GAPS |
| XMLTV import, merge, programme, and export        | Accept bounded local XMLTV input, reject unsafe XML, preserve source-scoped evidence, merge deterministically, and write validated XMLTV only under an allowed root.                               | `Import-ChannelForgeXmltvSource`, `Merge-ChannelForgeXmltvProgrammes`, `New-ChannelForgeProgramme`, `Export-ChannelForgeXmltv`                                                               | XMLTV public functions; XML reader/stream helpers; `tests/unit/XmltvParser.Tests.ps1`; `XmltvProgrammeMerge.Tests.ps1`; `XmltvSerialization.Tests.ps1`; compressed-ingestion tests                                                        | Tests cover valid/repeated parses, local-only input, DTD rejection, source-scoped bindings, duplicate/conflict behavior, golden output, byte determinism, and path validation.                                       | None found in the reviewed path.                                                                                                                                                             | PASS           |
| M3U/XMLTV identity binding and guide readiness    | Publish only exact one-to-one identity matches, classify ambiguity/orphans explicitly, and aggregate evidence using fail-closed readiness states.                                                  | `Resolve-ChannelForgeM3UXmltvBinding`, `Get-ChannelForgeGuideReadiness`                                                                                                                      | Binding/readiness functions; `tests/unit/M3UXmltvBinding.Tests.ps1`; `GuideIntelligence.Tests.ps1`; relevant Build-Lineup projections                                                                                                     | Tests reject whitespace/case/confusable identity variants, preserve source scope, classify exact/unbound/review/orphan states, and cover all readiness states.                                                       | None found in the reviewed path.                                                                                                                                                             | PASS           |
| Immutable acceptance, promotion, and recovery     | Construct acceptance only from complete decisions, publish one immutable generation graph atomically, preserve previous state, and recover deterministically after interruption.                   | `New-ChannelForgeAcceptance`, `Publish-ChannelForgeAcceptedGeneration`, `Recover-ChannelForgeAcceptedState`                                                                                  | Acceptance/publication/recovery functions; `src/ChannelForge/Private/Initialize-ChannelForgeGenerationStore.ps1`; `tests/unit/Issue102AcceptedState.Tests.ps1`; `Issue103PromotionRecovery.Tests.ps1`; candidate evidence tests           | Tests cover decision coverage, XMLTV transitions, exact-byte reconstruction, atomic pointer replacement, previous-state preservation, immutable generation files, and restart recovery.                              | No second accepted-state authority was found: `state/accepted-lineup.json`/generation state is authoritative; Guided Setup consumer files are a derived view.                                | PASS           |
| GUI saved-lineup flow and validation              | Validate selected files before review, keep invalid/stale paths blocked, require explicit acknowledgement before native acceptance, redact source values, and expose accepted state read-only.     | `GuidedSetupPage`, `LineupReviewPage`, `SavedLineupPage`, Tauri `prepare_saved_lineup_plan` and `accept_saved_lineup` commands                                                               | `gui/src/pages/GuidedSetupPage.tsx`; `gui/src/pages/LineupReviewPage.tsx`; `gui/src/pages/SavedLineupPage.tsx`; `gui/src/app/setupSelection.ts`; `gui/src/app/setupPicker.ts`; `gui/src-tauri/src/lib.rs`; GUI unit/e2e tests             | GUI tests cover blocked review actions, stale selection, explicit acknowledgement, saved-lineup availability only after native success, redaction, and accepted-view read-only behavior.                             | GUI checks are not part of the PowerShell CI workflow; see CI gap below.                                                                                                                     | PASS_WITH_GAPS |
| Stage A guide evidence/readiness contracts        | Accept bounded typed evidence, normalize safe metadata, reject invalid identifiers/timestamps, preserve read-only evidence, and map stale/unavailable/contradictory evidence to blocked readiness. | `New-ChannelForgeGuideEvidence`, `Get-ChannelForgeGuideReadiness`                                                                                                                            | Evidence/readiness functions; `GuideEvidenceRecord`, `GuideReadinessRecord`; Stage A fixtures; `tests/unit/GuideIntelligence.Tests.ps1`; `XmltvEvidenceRecord.Tests.ps1`                                                                  | Tests cover provider/XMLTV/AED/schedule/accepted evidence types, metadata redaction, confidence thresholds, freshness transitions, required event families, and sanitized fixtures.                                  | No schedule adapter or AED JSON importer is implemented; this is an explicit scope boundary, not an unreviewed implementation.                                                               | PASS           |
| Stage B native event-pattern inference            | Infer structured event patterns from examples/evidence without regex authoring, produce deterministic provenance/confidence/review state, and remain candidate-only.                               | `Invoke-ChannelForgeGuidePatternInference`                                                                                                                                                   | Inference command; private analysis helpers; pattern classes; `tests/unit/GuidePatternInference.Tests.ps1`; Stage B fixtures                                                                                                              | Tests cover examples/evidence contracts, required fields, timezone/date handling, event families, drift, sensitive input, deterministic output, `CandidateOnly`, `CanPublish=false`, and no accepted mutation.       | No automatic adoption or guide publication is present by design.                                                                                                                             | PASS           |
| Stage C event-pattern review surface              | Project Stage B into beginner-readable object/JSON/Markdown review output without writing files, accepting a rule, publishing a guide, or changing provider/downstream state.                      | `Get-ChannelForgeGuidePatternReview`                                                                                                                                                         | Review command; private review projection/Markdown helpers; `GuidePatternReviewReport`; `tests/unit/GuidePatternReview.Tests.ps1`                                                                                                         | Tests cover confirmed, safe-candidate, blocked, drift, provenance, deterministic formats, redaction, and publication/accepted-state safety fields.                                                                   | No independent report schema exists for the review projection.                                                                                                                               | PASS_WITH_GAPS |
| Stage D beginner event-pattern preview            | Add optional Guided Setup preview with examples/evidence input, minimum-example gating, report-only JSON/Markdown/text outputs, and explicit rejection of `-Accept` combination.                   | `scripts/Build-My-Lineup.ps1 -EventPatternPreview`                                                                                                                                           | Stage D workflow implementation; `tests/unit/BuildMyLineup.Tests.ps1`; Stage D docs and security notes                                                                                                                                    | CI #219 includes Stage D regression tests covering disabled/blocked/confirmed/evidence/refusal/determinism/redaction behavior; source passes Stage B inference into Stage C review and writes only `output/reports`. | No acceptance-plan step exists yet; it is intentionally outside the merged Stage D scope.                                                                                                    | PASS           |
| Schemas and generated reports                     | Version machine-readable contracts, validate safety fields, keep reports deterministic, and redact raw source values and private paths.                                                            | `schemas/*`; workflow/refresh/report writers                                                                                                                                                 | `schemas/source-refresh-*.json`; acceptance/generation schemas; Build-Lineup and Build-My-Lineup report writers; security docs                                                                                                            | Schema tests, report redaction tests, deterministic-output tests, Markdown hygiene/link checks, and CI #219.                                                                                                         | Guided Setup summary/plan and Stage D preview JSON have version fields but no dedicated JSON schemas or schema validation step.                                                              | PASS_WITH_GAPS |
| CI, build, and test correctness gates             | Run formatting, schema, documentation, analyzer, secret, and PowerShell test gates before merge, while making review evidence distinct from release approval.                                      | `.github/workflows/powershell-ci.yml`, validation scripts, package scripts                                                                                                                   | `.github/workflows/powershell-ci.yml`; `scripts/Validate-*`; `package.json`; `tests/unit/*`; `gui/package.json`                                                                                                                           | CI #219 passed for the exact base; workflow visibly runs secret scan, Prettier, schema, Markdown, analyzer, and all Pester tests.                                                                                    | The current workflow does not run GUI Vitest/TypeScript/Rust checks, so product-wide GUI intent can regress without this CI gate.                                                            | PASS_WITH_GAPS |

### GUI acceptance authority check

The reviewed `accept_saved_lineup_inner` implementation revalidates the saved
plan, workspace-contained paths, generation identity, selected-file match
status, and candidate/build/parent hashes before invoking `run_saved_workflow`.
The Tauri path passes `-Accept` and the expected generation identities to
`Build-My-Lineup.ps1`; it does not write accepted lineup files itself. The
PowerShell workflow remains the publication path through the immutable
generation boundary. This supports the conclusion that no second accepted-lineup
authority was found. The GUI path remains `PASS_WITH_GAPS` because the current
CI workflow does not execute its Vitest, TypeScript, or Rust/Tauri checks.

## Safety conclusions

The reviewed paths did not show unintended provider mutation, downstream
mutation, guide publication during candidate/review/preview flows, low-confidence
automatic promotion, or a second accepted-lineup authority. Accepted
publication is explicit and routes through the immutable generation boundary.
Candidate and review reports are redacted and path-confined in the reviewed
production entry points.

The audit identified four material `PASS_WITH_GAPS` themes:

1. [Issue #142](https://github.com/Jumpstile/ChannelForge/issues/142): Add
   explicit allowed-root checks at source-refresh wrapper boundaries for report
   and cache destinations.
2. [Issue #143](https://github.com/Jumpstile/ChannelForge/issues/143): Make the
   low-level M3U exporter path boundary explicit or enforce the allowed root at
   the API boundary; the production caller currently owns the guard.
3. [Issue #144](https://github.com/Jumpstile/ChannelForge/issues/144): Add
   schemas and validation for Guided Setup, Stage C, and Stage D generated JSON
   reports, including their safety fields.
4. [Issue #145](https://github.com/Jumpstile/ChannelForge/issues/145): Add GUI
   TypeScript/Vitest/Tauri validation to the repository CI gate.

These are follow-up remediation items. They do not authorize Stage E or any
other implementation slice to silently absorb unrelated changes. Until each
area is remediated or explicitly accepted by the Product Owner / Engineering
Manager, future slices touching it must preserve the `PASS_WITH_GAPS`
classification and include the gap in their intent-fit review.
