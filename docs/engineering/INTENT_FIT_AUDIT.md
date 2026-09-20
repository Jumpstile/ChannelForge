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

| Area                                              | Intended behavior                                                                                                                                                                                                                                                       | Entry points                                                                                                                                                                                 | Files reviewed                                                                                                                                                                                                                                                                                     | Evidence                                                                                                                                                                                                                                       | Gaps                                                                                                                                                                                         | Disposition    |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Candidate lineup build                            | Build deterministic M3U/XMLTV candidate artifacts and review reports without touching public or accepted outputs.                                                                                                                                                       | `scripts/Build-Lineup.ps1`, candidate namespace helpers                                                                                                                                      | `scripts/Build-Lineup.ps1`; `src/ChannelForge/Private/Publish-ChannelForgeCandidateNamespace.ps1`; `src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1`                                                                                                                                | Candidate-only tests preserve public and rollback bytes, reuse deterministic namespaces, and redact candidate reports.                                                                                                                         | None found in the reviewed path.                                                                                                                                                             | PASS           |
| Guided Setup / Beginner Workflow                  | Explain a proposal, require explicit acceptance for publication, and keep Stage D event-pattern preview report-only.                                                                                                                                                    | `scripts/Build-My-Lineup.ps1`                                                                                                                                                                | `scripts/Build-My-Lineup.ps1`; `tests/unit/BuildMyLineup.Tests.ps1`; `docs/user/Build-Your-First-Lineup.md`; `docs/user/Reference/CLI-Reference.md`                                                                                                                                                | Proposal, stale-candidate, acceptance, deterministic-report, redaction, and event-preview tests; source routes real acceptance through the generation publication boundary.                                                                    | The consumer view is a derived `output/guided-setup/accepted` projection and needs to remain documented as non-authoritative.                                                                | PASS           |
| Source refresh planner and executor               | Plan from validated cache evidence; refresh disposable caches only; preserve last-known-good content; never publish or change accepted output.                                                                                                                          | `scripts/Get-ChannelForgeSourceRefreshPlan.ps1`, `scripts/Invoke-ChannelForgeSourceRefresh.ps1`                                                                                              | Both scripts; `src/ChannelForge/Public/Get-ChannelForgeSourceRefreshPlan.ps1`; configured source importers; `schemas/source-refresh-result.schema.json`                                                                                                                                            | Planner and executor tests cover cache states, deterministic reports, no accepted/generation output, failed-refresh preservation, and redaction.                                                                                               | Wrapper-level `OutputRoot`/`CacheRoot` inputs are not consistently checked with `Assert-ChannelForgeWritePath`; a caller can direct report/cache writes outside the documented output roots. | PASS_WITH_GAPS |
| Scheduled refresh wrapper and registration/status | Require a validated eligible plan, bounded execution, one owned task/lock identity, explicit install/remove approval, and no accepted-state mutation.                                                                                                                   | `scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1`, `Install-ChannelForgeScheduledRefresh.ps1`, `Get-ChannelForgeScheduledRefreshStatus.ps1`, `Uninstall-ChannelForgeScheduledRefresh.ps1` | Scheduled scripts; `src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1`; scheduled schemas; `tests/unit/ScheduledRefreshPlanner.Tests.ps1`; `ScheduledRefreshRun.Tests.ps1`; `ScheduledRefreshRegistration.Tests.ps1`                                                          | Tests cover ineligible-plan blocking, exactly-once executor invocation, lock/report contracts, task ownership, explicit approval, UTC boundaries, and registration redaction.                                                                  | Scheduled installation intentionally changes the OS task scheduler after explicit approval; this is documented operational mutation, not an unattended lineup mutation.                      | PASS           |
| M3U import, normalization, merge, and export      | Parse untrusted playlist structure, preserve original names, normalize deterministically, resolve aliases, deduplicate and number deterministically, and export only caller-approved output.                                                                            | `Import-ChannelForgeM3UPlaylist`, `ConvertTo-ChannelForgeNormalizedChannel`, `Merge-ChannelForgeLineup`, `Export-ChannelForgeM3UPlaylist`                                                    | Public M3U/normalization/merge/export functions; private reader and safe entry serializer; `tests/unit/M3UPlaylist.Tests.ps1`; `Normalization.Tests.ps1`; `MergeChannelForgeLineup.Tests.ps1`                                                                                                      | Tests cover malformed input, identity fields, original-name preservation, alias/dedup/numbering behavior, order independence, and deterministic output.                                                                                        | The low-level M3U exporter relies on its caller to apply `Assert-ChannelForgeWritePath`; the production caller does so, but the API contract is caller-dependent.                            | PASS_WITH_GAPS |
| XMLTV import, merge, programme, and export        | Accept bounded local XMLTV input, reject unsafe XML, preserve source-scoped evidence, merge deterministically, and write validated XMLTV only under an allowed root.                                                                                                    | `Import-ChannelForgeXmltvSource`, `Merge-ChannelForgeXmltvProgrammes`, `New-ChannelForgeProgramme`, `Export-ChannelForgeXmltv`                                                               | XMLTV public functions; XML reader/stream helpers; `tests/unit/XmltvParser.Tests.ps1`; `XmltvProgrammeMerge.Tests.ps1`; `XmltvSerialization.Tests.ps1`; compressed-ingestion tests                                                                                                                 | Tests cover valid/repeated parses, local-only input, DTD rejection, source-scoped bindings, duplicate/conflict behavior, golden output, byte determinism, and path validation.                                                                 | None found in the reviewed path.                                                                                                                                                             | PASS           |
| M3U/XMLTV identity binding and guide readiness    | Publish only exact one-to-one identity matches, classify ambiguity/orphans explicitly, and aggregate evidence using fail-closed readiness states.                                                                                                                       | `Resolve-ChannelForgeM3UXmltvBinding`, `Get-ChannelForgeGuideReadiness`                                                                                                                      | Binding/readiness functions; `tests/unit/M3UXmltvBinding.Tests.ps1`; `GuideIntelligence.Tests.ps1`; relevant Build-Lineup projections                                                                                                                                                              | Tests reject whitespace/case/confusable identity variants, preserve source scope, classify exact/unbound/review/orphan states, and cover all readiness states.                                                                                 | None found in the reviewed path.                                                                                                                                                             | PASS           |
| Immutable acceptance, promotion, and recovery     | Construct acceptance only from complete decisions, publish one immutable generation graph atomically, preserve previous state, and recover deterministically after interruption.                                                                                        | `New-ChannelForgeAcceptanceDecision`, `Publish-ChannelForgeReviewedCandidate`, `New-ChannelForgeAcceptance`, `Publish-ChannelForgeAcceptedGeneration`, `Recover-ChannelForgeAcceptedState`   | Acceptance/publication/recovery functions; `src/ChannelForge/Private/Publish-ChannelForgeReviewedCandidate.ps1`; `src/ChannelForge/Private/Initialize-ChannelForgeGenerationStore.ps1`; `tests/unit/Issue102AcceptedState.Tests.ps1`; `Issue103PromotionRecovery.Tests.ps1`; `WebServer.Tests.ps1` | Tested with CLI and browser acceptance paths; parent mismatch, duplicate submission, ambiguity, candidate-byte, and recovery failures remain fail-closed.                                                                                      |
| GUI saved-lineup flow and browser Guided Setup    | Preserve reusable Guided Setup, selection, validation/review, saved-lineup, accessibility, copy, and design-token work while moving the primary product shell to a browser web UI; keep state changes behind the engine/API and immutable acceptance boundary.          | `GuidedSetupPage`, `submitGuidedSetupProposal`, `acceptGuidedSetupProposal`, `Get-ChannelForgeWebResponse`                                                                                   | `gui/src/pages/GuidedSetupPage.tsx`; `gui/src/app/guidedSetupProposal.ts`; browser unit/e2e/visual tests; `tests/unit/WebServer.Tests.ps1`; Issue #169 docs                                                                                                                                        | Browser review and explicit acknowledgement acceptance are implemented; hashes, paths, and raw content remain redacted and provider/downstream/scheduler mutation is absent.                                                                   |
| Stage A guide evidence/readiness contracts        | Accept bounded typed evidence, normalize safe metadata, reject invalid identifiers/timestamps, preserve read-only evidence, and map stale/unavailable/contradictory evidence to blocked readiness.                                                                      | `New-ChannelForgeGuideEvidence`, `Get-ChannelForgeGuideReadiness`                                                                                                                            | Evidence/readiness functions; `GuideEvidenceRecord`, `GuideReadinessRecord`; Stage A fixtures; `tests/unit/GuideIntelligence.Tests.ps1`; `XmltvEvidenceRecord.Tests.ps1`                                                                                                                           | Tests cover provider/XMLTV/AED/schedule/accepted evidence types, metadata redaction, confidence thresholds, freshness transitions, required event families, and sanitized fixtures.                                                            | No schedule adapter or AED JSON importer is implemented; this is an explicit scope boundary, not an unreviewed implementation.                                                               | PASS           |
| Stage B native event-pattern inference            | Infer structured event patterns from examples/evidence without regex authoring, produce deterministic provenance/confidence/review state, and remain candidate-only.                                                                                                    | `Invoke-ChannelForgeGuidePatternInference`                                                                                                                                                   | Inference command; private analysis helpers; pattern classes; `tests/unit/GuidePatternInference.Tests.ps1`; Stage B fixtures                                                                                                                                                                       | Tests cover examples/evidence contracts, required fields, timezone/date handling, event families, drift, sensitive input, deterministic output, `CandidateOnly`, `CanPublish=false`, and no accepted mutation.                                 | No automatic adoption or guide publication is present by design.                                                                                                                             | PASS           |
| Stage C event-pattern review surface              | Project Stage B into beginner-readable object/JSON/Markdown review output without writing files, accepting a rule, publishing a guide, or changing provider/downstream state.                                                                                           | `Get-ChannelForgeGuidePatternReview`                                                                                                                                                         | Review command; private review projection/Markdown helpers; `GuidePatternReviewReport`; `tests/unit/GuidePatternReview.Tests.ps1`                                                                                                                                                                  | Tests cover confirmed, safe-candidate, blocked, drift, provenance, deterministic formats, redaction, and publication/accepted-state safety fields.                                                                                             | No independent report schema exists for the review projection.                                                                                                                               | PASS_WITH_GAPS |
| Stage D beginner event-pattern preview            | Add optional Guided Setup preview with examples/evidence input, minimum-example gating, report-only JSON/Markdown/text outputs, and explicit rejection of `-Accept` combination.                                                                                        | `scripts/Build-My-Lineup.ps1 -EventPatternPreview`                                                                                                                                           | Stage D workflow implementation; `tests/unit/BuildMyLineup.Tests.ps1`; Stage D docs and security notes                                                                                                                                                                                             | CI #219 includes Stage D regression tests covering disabled/blocked/confirmed/evidence/refusal/determinism/redaction behavior; source passes Stage B inference into Stage C review and writes only `output/reports`.                           | No acceptance-plan step exists yet; it is intentionally outside the merged Stage D scope.                                                                                                    | PASS           |
| Schemas and generated reports                     | Version machine-readable contracts, validate safety fields, keep reports deterministic, and redact raw source values and private paths.                                                                                                                                 | `schemas/*`; workflow/refresh/report writers                                                                                                                                                 | `schemas/source-refresh-*.json`; acceptance/generation schemas; Build-Lineup and Build-My-Lineup report writers; security docs                                                                                                                                                                     | Schema tests, report redaction tests, deterministic-output tests, Markdown hygiene/link checks, and CI #219.                                                                                                                                   | Guided Setup summary/plan and Stage D preview JSON have version fields but no dedicated JSON schemas or schema validation step.                                                              | PASS_WITH_GAPS |
| CI, build, and test correctness gates             | Run formatting, schema, documentation, analyzer, secret, PowerShell, and required GUI checks before merge; run TypeScript/Vitest checks for the web-first UI source and Rust checks only for the optional wrapper; keep review evidence distinct from release approval. | `.github/workflows/powershell-ci.yml` (`secret-scan`, `quality-gates`), validation scripts, package scripts                                                                                  | `.github/workflows/powershell-ci.yml`; `scripts/Validate-*`; `package.json`; `tests/unit/*`; `gui/package.json`; `gui/vitest.config.ts`; `gui/src/test/*`; `gui/src-tauri/Cargo.toml`; Issue #145; Issue #150 ADR and architecture docs                                                            | The required `quality-gates` job now sets up Node.js 22/npm 10, runs `gui` TypeScript and Vitest checks, and runs locked Cargo tests for the optional wrapper without packaging or deployment. Existing required check names remain unchanged. | No engine-served web UI or HTTP/API source exists for browser-specific checks; adding such checks without a real target would be misleading.                                                 | PASS           |

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
Issue #166 candidate-proposal entry point is extended by Issue #169 with a
durable opaque review session, strict browser acceptance, immutable publisher
reuse, stale-parent rejection, and duplicate-submit safety. No second browser
acceptance authority or downstream publication path was added.

Local validation from the exact-base worktree passed GUI TypeScript
typechecking, `npm test` (9 files, 73 tests),
`npm run test:e2e -- --project=chromium` (8 tests),
`npm run test:visual -- --project=chromium` (14 tests), and
`cargo test --manifest-path src-tauri/Cargo.toml --locked` (24 tests across
3 suites). Focused PowerShell acceptance, accepted-state, recovery, and module
manifest tests also passed; full-suite and hosted-branch evidence remain
tracked separately.

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

## Issue #166 browser Guided Setup proposal slice

| Area                     | Intended behavior                                                                                                                                          | Entry points                                                                                                 | Evidence                                                                                                               | Disposition |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- | ----------- |
| Browser proposal request | Accept exactly one bounded M3U upload and an optional XMLTV upload through a strict same-origin JSON contract, then reuse the candidate engine in-process. | `POST /api/guided-setup/proposal`; `New-ChannelForgeCandidateProposal`; `gui/src/app/guidedSetupProposal.ts` | `tests/unit/WebServer.Tests.ps1`; `gui/src/test/guided-setup-browser.test.tsx`; `gui/src/test/navigation.test.tsx`     | PASS        |
| Candidate-only safety    | Return an allowlisted aggregate proposal projection and never mutate accepted state, provider state, downstream state, or guide publication.               | `Get-ChannelForgeGuidedSetupProposalResponse`; `GuidedSetupPage` browser branch                              | Mutation snapshot, safety-field, redaction, method-allowlist, malformed-input, and cleanup assertions in focused tests | PASS        |

The request is `application/json` with `schemaVersion: 1`, one
`m3u.contentBase64` object, and optional `xmltv.contentBase64`. Duplicate or
unknown properties, invalid base64, content-type mismatch, declared-length
mismatches, and oversized encoded/decoded bodies fail closed. The 24 MiB
encoded body, 4 MiB M3U, and 12 MiB XMLTV bounds are enforced at the HTTP and
decoded-file boundaries. The server stages fixed filenames under a GUID-named
`output/.web-guided-setup` request directory, calls the public candidate-only
module boundary, projects only counts/warnings/safe identity hashes, and removes
the request directory in `finally`.

No browser Accept/Publish control was added. The proposal response explicitly
reports `PublicationState=CandidateOnly`, `CanPublish=false`, and `none` for
accepted-state, provider, downstream, and guide-publication mutation. Existing
GET/HEAD status/static behavior remains covered by the same web server suite.

Disposition: `PASS` for the Issue #166 proposal boundary. Browser acceptance,
downstream integrations, Docker, Windows service installation, packaging,
release, and tester distribution remain outside this slice and outside the
approval.

## Issue #169 browser immutable acceptance slice

The browser review session is server-owned and identified only by an opaque
lowercase 32-hex proposal ID. A self-hashed session binds the content-addressed
candidate namespace to the accepted parent generation, accepted-state hash,
and accepted-output manifest hash. The acceptance request is a strict
`schemaVersion: 1` envelope containing only `proposalId` and
`acknowledged: true`; it is POST-only and bounded to 8 KiB.

`POST /api/guided-setup/accept` revalidates the session, exact reviewed bytes,
coverage, guide ambiguity, and current parent before calling the shared
`Publish-ChannelForgeReviewedCandidate` boundary. That boundary constructs the
decision and acceptance manifests and delegates to the immutable generation
publisher. CLI and browser acceptance therefore have one authority; no browser
route writes accepted pointers, provider files, downstream outputs, or
scheduler state. Duplicate sessions are terminal, and stale parents fail
closed.

Focused WebServer, generation recovery, GUI unit, browser E2E, and visual
checks provide evidence for the slice. Stable redacted screenshots are
published in the README and user build/limitations documentation. Disposition:
`PASS` for the Issue #169 browser acceptance intent. Docker, Windows service
installation, automatic refresh, and downstream publication remain explicit
scope boundaries.

## Public-readiness license, security, and Actions preparation

This documentation-only preparation slice materializes the owner-selected
source-available personal/non-commercial license model, documents contributor
intake constraints, adds a root security-policy publication gate, and records
non-authorizing Actions usage recommendations.

The slice does not change application behavior, provider acquisition, guide
handling, lineup generation, accepted state, release behavior, deployment,
tester distribution, branch protection, or workflow behavior. Repository
visibility was changed separately by the owner on 2026-09-18 to make hosted CI
run on the public-repository billing model; that operational change is not a
release authorization.

The repository-publication disposition is `PASS`. GitHub Support ticket
`#4764498` is solved: known sensitive commits are not reachable from hosted
branch or tag tips, and all 61 affected PR diff/code surfaces were removed
while PR metadata and discussion history were preserved. The full hosted-ref
privacy scan passed with no classified findings. Repository visibility is
public, GitHub private vulnerability reporting is enabled, and protection and
ruleset evidence is verified for `main`. PR #163 merged and post-merge public
`main` CI passed on `9879b302709e8d9c72a7c4dd552add5ce031a5f1`.

Disposition: `PASS` for repository publication. This does not change the
product-stage assessment: ChannelForge remains Early Alpha and
`PUBLIC_RELEASE_STATUS=NOT_RELEASE_READY`. Product release authorization now
moves to the First Usable Alpha gate in
`docs/release/FIRST_USABLE_ALPHA.md` and issue #164. Do not reopen the
repository-publication audit unless new evidence shows a regression in the
controls above.

## Issue #171 durable source enrollment slice

The intended behavior is durable, server-owned enrollment of browser-uploaded
local M3U bytes and optional XMLTV bytes after immutable lineup acceptance,
without making enrollment a second accepted-lineup authority. The implementation
keeps those boundaries separate:

| Area                                | Entry points                                                                                   | Evidence target                                                                                                                     | Disposition                                       |
| ----------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| Enrollment record and managed bytes | `Write-ChannelForgeSourceEnrollment`, `state/source-enrollment.json`, `state/managed-sources/` | Canonical self-hash, content fingerprints, atomic replacement, containment and reparse checks                                       | PASS_WITH_GAPS pending exact-head full gates      |
| Acceptance ordering                 | `Get-ChannelForgeGuidedSetupProposalResponse`, `Get-ChannelForgeGuidedSetupAcceptanceResponse` | Accepted generation publishes through existing publisher; enrollment failure returns accepted + repair-required without erasing LKG | PASS_WITH_GAPS pending focused WebServer evidence |
| Refresh reuse                       | `Get-ChannelForgeSourceRefreshPlan -EnrollmentPath`, `Invoke-ChannelForgeSourceRefresh.ps1`    | Stable bytes reuse; changed bytes produce review-only candidate; no accepted mutation                                               | PASS_WITH_GAPS pending focused refresh evidence   |
| Beginner status surface             | `Get-ChannelForgeWebStatus`, `/api/sources/refresh`, `StatusDashboard`                         | Redacted saved/changed/unavailable status, Refresh now, Replace sources                                                             | PASS_WITH_GAPS pending GUI/browser evidence       |

Remote credential enrollment, unattended remote acquisition, auto-acceptance,
downstream publication, and scheduled source mutation remain outside this
slice. The accepted generation remains the only lineup authority.

## Issue #173 Windows portable bundle slice

The intended behavior is a beginner-usable Windows x64 portable local server
that launches the existing ChannelForge engine/API/UI on loopback without a
Windows Service or administrator rights. The bundle must pin its PowerShell
runtime, preserve the existing engine/API/state authorities, update only
immutable application files, protect user state, and provide recoverable
uninstall boundaries.

| Area                             | Entry points                                                                                                           | Evidence                                                                                                                                                                                   | Disposition                                                  |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| Bundle build and runtime pinning | `scripts/Build-ChannelForgeWindowsPackage.ps1`, `runtime/pwsh`                                                         | `package-manifest.json` records source SHA, runtime version/tree hash, every file length/SHA256; deterministic ZIP and exclusion checks passed                                             | PASS_WITH_GAPS pending ARCADE clean-machine artifact capture |
| Existing server authority        | `scripts/Start-ChannelForge.ps1`, `scripts/Start-ChannelForgeWebServer.ps1`, `src/ChannelForge`                        | Launcher starts the existing server wrapper on `127.0.0.1:8765`; packaged launcher health and HTTP smoke passed; no second server implementation added                                     | PASS                                                         |
| Single update authority          | `tools/Invoke-ChannelForgeAutoUpdate.ps1`, `tools/ChannelForgeAutoUpdate.Core.psm1`                                    | Local and release paths reuse manifest verification, backup-first replacement, protected-state allowlist, restore-on-failure, and restart checks; focused updater/destructive tests passed | PASS                                                         |
| Protected state and uninstall    | `state/`, `config/`, `output/`, `cache/`, `logs/`, `UpdateBackups/`; `scripts/Uninstall-ChannelForgeWindowsBundle.ps1` | Package excludes runtime state; default uninstall retains user data; explicit purge is bounded and confirmed; lifecycle smoke passed                                                       | PASS                                                         |
| Packaged-layout validation       | `tests/unit/ChannelForgeWindowsPackage.Tests.ps1`, updater tests                                                       | Manifest tamper/unmanifested-file checks, install/update/state-retention/uninstall smoke, and bundled launcher health smoke cover actual extracted package layout                          | PASS                                                         |

Provider files, accepted generations, downstream outputs, and guide
publication remain owned by the existing engine/state contracts. The package
does not contain provider secrets or runtime state. Stable screenshots under
`docs/user/assets/alpha1-windows/` are real implementation captures and were
checked for transient Playwright references and private-path leakage.

Disposition: `PASS_WITH_GAPS`. Hosted exact-head quality-gates and secret-scan
pass on PR #174, but ARCADE clean-machine validation and its final packaged
screenshots remain required before merge, release, or tester distribution.
