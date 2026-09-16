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

| Area                                              | Intended behavior                                                                                                                                                                                                                                                       | Entry points                                                                                                                                                                                 | Files reviewed                                                                                                                                                                                                                                              | Evidence                                                                                                                                                                                                                                       | Gaps                                                                                                                                                                                         | Disposition    |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Candidate lineup build                            | Build deterministic M3U/XMLTV candidate artifacts and review reports without touching public or accepted outputs.                                                                                                                                                       | `scripts/Build-Lineup.ps1`, candidate namespace helpers                                                                                                                                      | `scripts/Build-Lineup.ps1`; `src/ChannelForge/Private/Publish-ChannelForgeCandidateNamespace.ps1`; `src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1`                                                                                         | Candidate-only tests preserve public and rollback bytes, reuse deterministic namespaces, and redact candidate reports.                                                                                                                         | None found in the reviewed path.                                                                                                                                                             | PASS           |
| Guided Setup / Beginner Workflow                  | Explain a proposal, require explicit acceptance for publication, and keep Stage D event-pattern preview report-only.                                                                                                                                                    | `scripts/Build-My-Lineup.ps1`                                                                                                                                                                | `scripts/Build-My-Lineup.ps1`; `tests/unit/BuildMyLineup.Tests.ps1`; `docs/user/Build-Your-First-Lineup.md`; `docs/user/Reference/CLI-Reference.md`                                                                                                         | Proposal, stale-candidate, acceptance, deterministic-report, redaction, and event-preview tests; source routes real acceptance through the generation publication boundary.                                                                    | The consumer view is a derived `output/guided-setup/accepted` projection and needs to remain documented as non-authoritative.                                                                | PASS           |
| Source refresh planner and executor               | Plan from validated cache evidence; refresh disposable caches only; preserve last-known-good content; never publish or change accepted output.                                                                                                                          | `scripts/Get-ChannelForgeSourceRefreshPlan.ps1`, `scripts/Invoke-ChannelForgeSourceRefresh.ps1`                                                                                              | Both scripts; `src/ChannelForge/Public/Get-ChannelForgeSourceRefreshPlan.ps1`; configured source importers; `schemas/source-refresh-result.schema.json`                                                                                                     | Planner and executor tests cover cache states, deterministic reports, no accepted/generation output, failed-refresh preservation, and redaction.                                                                                               | Wrapper-level `OutputRoot`/`CacheRoot` inputs are not consistently checked with `Assert-ChannelForgeWritePath`; a caller can direct report/cache writes outside the documented output roots. | PASS_WITH_GAPS |
| Scheduled refresh wrapper and registration/status | Require a validated eligible plan, bounded execution, one owned task/lock identity, explicit install/remove approval, and no accepted-state mutation.                                                                                                                   | `scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1`, `Install-ChannelForgeScheduledRefresh.ps1`, `Get-ChannelForgeScheduledRefreshStatus.ps1`, `Uninstall-ChannelForgeScheduledRefresh.ps1` | Scheduled scripts; `src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1`; scheduled schemas; `tests/unit/ScheduledRefreshPlanner.Tests.ps1`; `ScheduledRefreshRun.Tests.ps1`; `ScheduledRefreshRegistration.Tests.ps1`                   | Tests cover ineligible-plan blocking, exactly-once executor invocation, lock/report contracts, task ownership, explicit approval, UTC boundaries, and registration redaction.                                                                  | Scheduled installation intentionally changes the OS task scheduler after explicit approval; this is documented operational mutation, not an unattended lineup mutation.                      | PASS           |
| M3U import, normalization, merge, and export      | Parse untrusted playlist structure, preserve original names, normalize deterministically, resolve aliases, deduplicate and number deterministically, and export only caller-approved output.                                                                            | `Import-ChannelForgeM3UPlaylist`, `ConvertTo-ChannelForgeNormalizedChannel`, `Merge-ChannelForgeLineup`, `Export-ChannelForgeM3UPlaylist`                                                    | Public M3U/normalization/merge/export functions; private reader and safe entry serializer; `tests/unit/M3UPlaylist.Tests.ps1`; `Normalization.Tests.ps1`; `MergeChannelForgeLineup.Tests.ps1`                                                               | Tests cover malformed input, identity fields, original-name preservation, alias/dedup/numbering behavior, order independence, and deterministic output.                                                                                        | The low-level M3U exporter relies on its caller to apply `Assert-ChannelForgeWritePath`; the production caller does so, but the API contract is caller-dependent.                            | PASS_WITH_GAPS |
| XMLTV import, merge, programme, and export        | Accept bounded local XMLTV input, reject unsafe XML, preserve source-scoped evidence, merge deterministically, and write validated XMLTV only under an allowed root.                                                                                                    | `Import-ChannelForgeXmltvSource`, `Merge-ChannelForgeXmltvProgrammes`, `New-ChannelForgeProgramme`, `Export-ChannelForgeXmltv`                                                               | XMLTV public functions; XML reader/stream helpers; `tests/unit/XmltvParser.Tests.ps1`; `XmltvProgrammeMerge.Tests.ps1`; `XmltvSerialization.Tests.ps1`; compressed-ingestion tests                                                                          | Tests cover valid/repeated parses, local-only input, DTD rejection, source-scoped bindings, duplicate/conflict behavior, golden output, byte determinism, and path validation.                                                                 | None found in the reviewed path.                                                                                                                                                             | PASS           |
| M3U/XMLTV identity binding and guide readiness    | Publish only exact one-to-one identity matches, classify ambiguity/orphans explicitly, and aggregate evidence using fail-closed readiness states.                                                                                                                       | `Resolve-ChannelForgeM3UXmltvBinding`, `Get-ChannelForgeGuideReadiness`                                                                                                                      | Binding/readiness functions; `tests/unit/M3UXmltvBinding.Tests.ps1`; `GuideIntelligence.Tests.ps1`; relevant Build-Lineup projections                                                                                                                       | Tests reject whitespace/case/confusable identity variants, preserve source scope, classify exact/unbound/review/orphan states, and cover all readiness states.                                                                                 | None found in the reviewed path.                                                                                                                                                             | PASS           |
| Immutable acceptance, promotion, and recovery     | Construct acceptance only from complete decisions, publish one immutable generation graph atomically, preserve previous state, and recover deterministically after interruption.                                                                                        | `New-ChannelForgeAcceptance`, `Publish-ChannelForgeAcceptedGeneration`, `Recover-ChannelForgeAcceptedState`                                                                                  | Acceptance/publication/recovery functions; `src/ChannelForge/Private/Initialize-ChannelForgeGenerationStore.ps1`; `tests/unit/Issue102AcceptedState.Tests.ps1`; `Issue103PromotionRecovery.Tests.ps1`; candidate evidence tests                             | Tests cover decision coverage, XMLTV transitions, exact-byte reconstruction, atomic pointer replacement, previous-state preservation, immutable generation files, and restart recovery.                                                        | No second accepted-state authority was found: `state/accepted-lineup.json`/generation state is authoritative; Guided Setup consumer files are a derived view.                                | PASS           |
| GUI saved-lineup flow and validation              | Preserve reusable Guided Setup, selection, validation/review, saved-lineup, accessibility, copy, and design-token work while moving the primary product shell to a browser web UI; keep state changes behind the engine/API and immutable acceptance boundary.          | Future web UI engine/API entry points; current `GuidedSetupPage`, `LineupReviewPage`, `SavedLineupPage`; optional Tauri `prepare_saved_lineup_plan` and `accept_saved_lineup` adapters       | `gui/src/pages/GuidedSetupPage.tsx`; `gui/src/pages/LineupReviewPage.tsx`; `gui/src/pages/SavedLineupPage.tsx`; `gui/src/app/setupSelection.ts`; `gui/src/app/setupPicker.ts`; `gui/src-tauri/src/lib.rs`; GUI unit/e2e tests; Issue #150 architecture docs | Existing GUI tests and Rust bridge preserve blocked review states, explicit acknowledgement, redaction, and PowerShell-owned acceptance. Required CI now executes the TypeScript, Vitest, and optional-wrapper Rust checks.                    | Web HTTP/API entry points and native-assumption migration remain future work; this CI slice does not claim browser behavior.                                                                 | PASS_WITH_GAPS |
| Stage A guide evidence/readiness contracts        | Accept bounded typed evidence, normalize safe metadata, reject invalid identifiers/timestamps, preserve read-only evidence, and map stale/unavailable/contradictory evidence to blocked readiness.                                                                      | `New-ChannelForgeGuideEvidence`, `Get-ChannelForgeGuideReadiness`                                                                                                                            | Evidence/readiness functions; `GuideEvidenceRecord`, `GuideReadinessRecord`; Stage A fixtures; `tests/unit/GuideIntelligence.Tests.ps1`; `XmltvEvidenceRecord.Tests.ps1`                                                                                    | Tests cover provider/XMLTV/AED/schedule/accepted evidence types, metadata redaction, confidence thresholds, freshness transitions, required event families, and sanitized fixtures.                                                            | No schedule adapter or AED JSON importer is implemented; this is an explicit scope boundary, not an unreviewed implementation.                                                               | PASS           |
| Stage B native event-pattern inference            | Infer structured event patterns from examples/evidence without regex authoring, produce deterministic provenance/confidence/review state, and remain candidate-only.                                                                                                    | `Invoke-ChannelForgeGuidePatternInference`                                                                                                                                                   | Inference command; private analysis helpers; pattern classes; `tests/unit/GuidePatternInference.Tests.ps1`; Stage B fixtures                                                                                                                                | Tests cover examples/evidence contracts, required fields, timezone/date handling, event families, drift, sensitive input, deterministic output, `CandidateOnly`, `CanPublish=false`, and no accepted mutation.                                 | No automatic adoption or guide publication is present by design.                                                                                                                             | PASS           |
| Stage C event-pattern review surface              | Project Stage B into beginner-readable object/JSON/Markdown review output without writing files, accepting a rule, publishing a guide, or changing provider/downstream state.                                                                                           | `Get-ChannelForgeGuidePatternReview`                                                                                                                                                         | Review command; private review projection/Markdown helpers; `GuidePatternReviewReport`; `tests/unit/GuidePatternReview.Tests.ps1`                                                                                                                           | Tests cover confirmed, safe-candidate, blocked, drift, provenance, deterministic formats, redaction, and publication/accepted-state safety fields.                                                                                             | No independent report schema exists for the review projection.                                                                                                                               | PASS_WITH_GAPS |
| Stage D beginner event-pattern preview            | Add optional Guided Setup preview with examples/evidence input, minimum-example gating, report-only JSON/Markdown/text outputs, and explicit rejection of `-Accept` combination.                                                                                        | `scripts/Build-My-Lineup.ps1 -EventPatternPreview`                                                                                                                                           | Stage D workflow implementation; `tests/unit/BuildMyLineup.Tests.ps1`; Stage D docs and security notes                                                                                                                                                      | CI #219 includes Stage D regression tests covering disabled/blocked/confirmed/evidence/refusal/determinism/redaction behavior; source passes Stage B inference into Stage C review and writes only `output/reports`.                           | No acceptance-plan step exists yet; it is intentionally outside the merged Stage D scope.                                                                                                    | PASS           |
| Schemas and generated reports                     | Version machine-readable contracts, validate safety fields, keep reports deterministic, and redact raw source values and private paths.                                                                                                                                 | `schemas/*`; workflow/refresh/report writers                                                                                                                                                 | `schemas/source-refresh-*.json`; acceptance/generation schemas; Build-Lineup and Build-My-Lineup report writers; security docs                                                                                                                              | Schema tests, report redaction tests, deterministic-output tests, Markdown hygiene/link checks, and CI #219.                                                                                                                                   | Guided Setup summary/plan and Stage D preview JSON have version fields but no dedicated JSON schemas or schema validation step.                                                              | PASS_WITH_GAPS |
| CI, build, and test correctness gates             | Run formatting, schema, documentation, analyzer, secret, PowerShell, and required GUI checks before merge; run TypeScript/Vitest checks for the web-first UI source and Rust checks only for the optional wrapper; keep review evidence distinct from release approval. | `.github/workflows/powershell-ci.yml` (`secret-scan`, `quality-gates`), validation scripts, package scripts                                                                                  | `.github/workflows/powershell-ci.yml`; `scripts/Validate-*`; `package.json`; `tests/unit/*`; `gui/package.json`; `gui/vitest.config.ts`; `gui/src/test/*`; `gui/src-tauri/Cargo.toml`; Issue #145; Issue #150 ADR and architecture docs                     | The required `quality-gates` job now sets up Node.js 22/npm 10, runs `gui` TypeScript and Vitest checks, and runs locked Cargo tests for the optional wrapper without packaging or deployment. Existing required check names remain unchanged. | No engine-served web UI or HTTP/API source exists for browser-specific checks; adding such checks without a real target would be misleading.                                                 | PASS           |

### GUI acceptance authority check

The reviewed `accept_saved_lineup_inner` implementation revalidates the saved
plan, workspace-contained paths, generation identity, selected-file match
status, and candidate/build/parent hashes before invoking `run_saved_workflow`.
The Tauri path passes `-Accept` and the expected generation identities to
`Build-My-Lineup.ps1`; it does not write accepted lineup files itself.
The PowerShell workflow remains the publication path through the immutable
generation boundary. No second accepted-lineup authority was found. The
architecture reset does not change that conclusion; it requires future web UI
state changes to use the engine/API boundary rather than native-only access.
The Issue #145 CI portion is now `PASS`: the protected `quality-gates` job
executes GUI TypeScript, Vitest, and locked optional-wrapper Rust checks. The
overall GUI area remains `PASS_WITH_GAPS` only because the browser web UI and
engine HTTP/API entry points from Issue #150 are not implemented in this slice.
No browser behavior is claimed, and no fake web checks were added.

Local validation from the exact-base worktree passed `npm run typecheck`,
`npm test` (7 files, 64 tests), and
`cargo test --manifest-path src-tauri/Cargo.toml --locked` (24 tests across
3 suites). The branch has not been pushed, so new-branch CI remains pending.

### Stage E acceptance-plan slice

The Stage E command, focused tests, and the Stage B/C/D integration path were
inspected against Issue #121 intent and the #147 volatile-metadata guardrail.
The source produces deterministic object, JSON, distinct Markdown, and plain
text plans from Stage B or Stage C/D results. It preserves stable
title/time/pattern identity separately from volatile enrichment. The Stage E
volatile evaluator does not synthesize statistics, rosters, standings, or
schedule descriptions; the current Stage A/B path supplies no such facts
unless an evidence producer provides optional safe metadata. Absent that
metadata, the plan reports `NotProvided`. Volatile facts
are presented as current only when source identity/type, fetched and
source-data timestamps, freshness TTL, season context, subject identity,
confidence, and contradiction checks pass; stale NFL preseason statistics in a
regular-season context, stale prior-day MLB summaries, stale roster/player
facts, missing provenance, and contradictory facts are omitted or marked for
review. The focused tests cover each case and prove exact sensitive values are
absent while policy field names in `RedactedFields` remain expected metadata.
The generated report envelopes are now covered by dedicated schemas and
`tests/unit/GeneratedReportSchemas.Tests.ps1`: Guided Setup summary, Stage C
review JSON, Stage D preview JSON, and Stage E acceptance-plan JSON. Tests
validate required safety fields, deterministic output, exact sensitive-value
absence, Stage C/D hash redaction, Stage E identity states, and degraded
volatile statuses without requiring fact generation.
The source preserves `CandidateOnly`, sets `CanPublish = false` and
`CanAcceptNow = false`, reports exact eligibility or blocked reasons, applies
redaction, and has no acceptance, adoption, guide, provider, downstream,
filesystem, or accepted-state mutation path. Direct Stage B input includes the
opaque deterministic proposed rule identity; Stage C/D-only input explicitly
reports that identity as unavailable because those review formats intentionally
omit candidate hashes.

Disposition: `PASS`. The behavior fits the read-only acceptance-plan intent,
the #147 volatile guardrail, and the #144 generated-report schema contract.
The generated-plan JSON schema gap is resolved; the remaining audit gaps are
tracked separately below.

## Safety conclusions

The reviewed paths did not show unintended provider mutation, downstream
mutation, guide publication during candidate/review/preview flows, low-confidence
automatic promotion, or a second accepted-lineup authority. Accepted
publication is explicit and routes through the immutable generation boundary.
Candidate and review reports are redacted and path-confined in the reviewed
production entry points.

The audit identified two material `PASS_WITH_GAPS` themes:

1. [Issue #142](https://github.com/Jumpstile/ChannelForge/issues/142): Add
   explicit allowed-root checks at source-refresh wrapper boundaries for report
   and cache destinations.
2. [Issue #143](https://github.com/Jumpstile/ChannelForge/issues/143): Make the
   low-level M3U exporter path boundary explicit or enforce the allowed root at
   the API boundary; the production caller currently owns the guard.

Issue #145's CI gap is remediated by the required `quality-gates` steps above.
The browser web UI/API implementation remains future work under Issue #150 and
is not part of this CI slice.

These are follow-up remediation items. They do not authorize Stage E or any
other implementation slice to silently absorb unrelated changes. Until each
area is remediated or explicitly accepted by the Product Owner / Engineering
Manager, future slices touching it must preserve the `PASS_WITH_GAPS`
classification and include the gap in their intent-fit review.

## Issue #150 architecture reset

| Area                                     | Intended behavior                                                                                                                                                                                               | Entry points                                                                               | Files reviewed                                                                                                                                                                                                                         | Evidence                                                                                                                                                                                                                                                          | Gaps                                                                                                           | Disposition |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ----------- |
| UI architecture and deployment direction | Establish one primary browser-based local web UI served by the ChannelForge engine, with Docker and Windows server/service as primary deployment modes; retain Tauri only as optional packaging/reference work. | Future engine HTTP/API and web UI entry points; current `gui/` prototype as reference only | `docs/architecture/ARCHITECTURE.md`; `docs/adr/0016-web-first-local-ui.md`; `docs/developer/DEVELOPER_GUIDE.md`; `docs/user/CURRENT_LIMITATIONS.md`; `docs/user/What-Is-ChannelForge.md`; `README.md`; `gui/`; preserved GUI worktrees | Documentation explicitly assigns UI state changes to engine/API boundaries, preserves the accepted-generation authority, identifies reusable UI work, and lists native assumptions requiring re-evaluation. No runtime code or deployment implementation changed. | Web server/API, Docker, Windows service, appearance modes, and native-assumption migration remain future work. | PASS        |

The prior documentation-only reset had no provider, downstream,
guide-publication, accepted-state, package, release, deployment, or tester-build
mutation path.

## Issue #150 web server foundation slice

The foundation adds a local appliance entry point without attempting the full
product UI or deployment modes. `scripts/Start-ChannelForgeWebServer.ps1` loads
the module and starts `Start-ChannelForgeWebServer`, which binds only to
`127.0.0.1` or `[::1]`. `GET` and `HEAD` serve the existing `gui/dist` Vite
build when present, otherwise the safe placeholder shell; `/health` and
`/api/status` remain read-only JSON, and all other methods are rejected without
a state-changing route.

The implementation files are
`src/ChannelForge/Public/Get-ChannelForgeWebStatus.ps1`,
`src/ChannelForge/Public/New-ChannelForgeWebServer.ps1`,
`src/ChannelForge/Public/Start-ChannelForgeWebServer.ps1`,
`src/ChannelForge/Private/Get-ChannelForgeWebResponse.ps1`, and the repository
wrapper script. `tests/unit/WebServer.Tests.ps1` covers module import, listener
construction, loopback-only binding, static-root configuration, placeholder
fallback, built index and JavaScript/CSS assets, safe MIME types, `HEAD`
consistency, traversal rejection, unknown paths, mutation boundaries, and
redaction.

The static bridge is confined to the repository's `gui/dist` subtree, serves
only allowlisted HTML, JavaScript, CSS, image, and font types, rejects
directories and unknown types, and has no SPA fallback. It does not expose
provider URLs, credentials, private paths, hashes, generation IDs,
accepted-generation contents, or parser details. The status payload performs a
validated read-only accepted-generation check and exposes only derived lineup
status and fixed read-only classifications. No provider, downstream,
guide-publication, or accepted-state mutation path was added.

Malformed accepted-state metadata fails closed to a safe `503` response for the
affected request; it does not terminate the read-only server loop.

Local validation and the exact-base intent review support `PASS` for this
foundation slice. The overall Issue #150 architecture remains
`PASS_WITH_GAPS` because API-backed Guided Setup, the full browser UI/API
beyond this dashboard, Docker deployment, and Windows server/service
implementation remain future work.

## Issue #150 read-only status dashboard slice

| Area                     | Intended behavior                                                                                                                               | Entry points                                                                                            | Evidence                                                                                                                                          | Disposition |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| Browser status dashboard | Fetch same-origin `GET /api/status` and show beginner-safe running, lineup, next-action, read-only, and degraded states without changing state. | `gui/src/app/webStatus.ts`; `gui/src/components/StatusDashboard.tsx`; `gui/src/pages/WorkbenchPage.tsx` | Safe contract projection; loading, not-accepted, accepted, `503`, fetch-failure, invalid-shape, redaction, and GET-only tests in `gui/src/test/`. | PASS        |

The browser client accepts only the validated `Service`, `Status`, `Message`,
`LineupStatus`, and `ReadOnly` contract facts needed to derive a local boolean
summary. It discards the raw payload and never displays version, mutation
classifications, accepted-generation metadata, or implementation errors.

The dashboard makes one same-origin `GET` request to `/api/status`. It sends no
request body and has no POST, PUT, PATCH, or DELETE path. The engine remains the
only authority for provider, downstream, guide-publication, candidate,
acceptance, and accepted-state mutation.

The UI renders safe fixed copy for `200` not-accepted and accepted responses.
`503`, network failures, rejected promises, malformed JSON, and unknown payload
shapes all render the same beginner-safe unavailable state without a blank
screen. No provider URLs, credentials, private paths, hashes, generation IDs,
accepted-generation contents, or parser details are stored or rendered by the
dashboard.

Focused GUI tests and the required repository validation gates provide evidence
for this slice. Full Guided Setup API behavior, mutation flows, Docker,
Windows server/service deployment, packaging, release, and tester builds remain
outside scope.

## Public-readiness license, security, and Actions preparation

This documentation-only preparation slice materializes the owner-selected
source-available personal/non-commercial license model, documents contributor
intake constraints, adds a root security-policy publication gate, and records
non-authorizing Actions usage recommendations.

The slice does not change application behavior, provider acquisition, guide
handling, lineup generation, accepted state, release behavior, deployment,
tester distribution, branch protection, workflow behavior, repository
visibility, or hosted CI execution.

The public-readiness disposition remains `BLOCKED_PUBLIC`. GitHub Support
ticket `#4764498` is solved: known sensitive commits are not reachable from
hosted branch or tag tips, and all 61 affected PR diff/code surfaces were
removed while PR metadata and discussion history were preserved. Protection
and ruleset evidence is verified for `main`. The full hosted-ref privacy scan
passed with no classified findings; private vulnerability reporting remains
unverified, and the final exact-head public-readiness audit remains required.

Disposition: `PASS_WITH_GAPS`. The owner approved the source-available
personal/non-commercial license and the security-policy decisions are recorded.
The remaining gaps are private-reporting verification, Actions constraints,
repository visibility, and the final public-readiness gate.
