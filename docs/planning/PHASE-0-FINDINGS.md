# Phase 0 findings and issue dependency map

Date: November 12, 2026. Code: `main` at a156acb. No product code changed in Phase 0.

## 1. Findings

1. **Test baseline.** main a156acb: 882 passed, 0 failed, 1 skipped (24.8 minutes, Pester unit suite)
2. **ADR 0007 check.** Passes. `docs/architecture/MODULE_CONTRACT_MATRIX.md` exists and documents all twelve modules (responsibilities, inputs, outputs, non-goals, allowed and forbidden dependencies, tests). The governance gate (#72 and its contract dependencies) is closed.
3. **Guide ids.** A colliding or missing guide id never stops a build and never drops a channel (PR #207, frozen contract v1.0). Strict mode is `-AmbiguousAction Cancel`.
4. **Security checks.** Fast checks, gated checks, CodeQL, Semgrep rules, SBOM and Dependabot are on `main` (PR #208). Not yet on `main`: the frozen-contract check and the adversarial test (they need the blocker-2 contract docs), the development monitor, and dependency review (GitHub's dependency graph is off).
5. **Real-lineup evidence (Plex + Dispatcharr, Nov 12).** Plex's image service refuses to fetch icons from private addresses, so channel icons on a local address show in Plex Web but never on Apple TV. On the real 479-channel guide, 156 channels had no icon and 7 pointed at a dead host. Rule for Phase 1 (#191, #40, #41): every channel icon is a public https link, is checked, and no channel ships without one (placeholder and event channels get a group-level default).
6. **Open-issue count.** 77 open issues. 51 have a milestone (M0 to M9). 26 have none; most of those are alpha-gate and requirement issues (#141 to #197).

## 2. Dependency map

Arrows mean "needs". Only stated dependencies and clear title-level dependencies are used.

**A. Foundations (rules everything else follows)**

- #27 architecture, #33 simplicity standard, #60 MVP priority, #141 intent-fit gate. These are standing gates, not build steps.
- #36 data store (indexes for identity, guide, events) is needed by #35, #38, #39, #40, #41, #43, #47 and #193.

**B. Guide truth (Phase 1)**

- #40 EPG acquisition and merge (multi-lineup identity, validation, provenance) is the base for #43, #45, #46, #57, #59, #153, #175 and #191.
- #175 guided setup (multi-source, bindings, validation) needs #40. #184 (audit provenance) needs #175.
- #191 guide quality and categories needs #175 and #40, and feeds #186 and #190.
- #41 channel visual identity (logos) needs #40. Finding 5 adds: public https only, checked, never blank.
- #25 alias tester, #26 config defaults, #42 station registry and #45 reference-data adapter support matching quality. #45 needs #42 and #40.
- #142, #143, #144 are small hardening items under #141.

**C. Events (Phase 3)**

- Stated chain: #29 foundation, then #30 discovery, then #31 learning, then #32 event guide delivery. #28 is the epic over all four.
- #121 (event patterns) and #38 (sports channel lifecycle and artwork) build on #28 to #32. #147 (freshness and provenance gates) guards #121.
- Own event guides for sports, wrestling, PPV and adult channels belong here, not in Phase 1.

**D. Outputs and operations (Phases 3 and 4)**

- #46 compatibility profiles needs #39, #40, #41. #49 reconciliation needs #46. #53 doctor, #54 backup pool, #55 Plex budget need #49 and #46.
- #50 adapter SDK needs #46 and #35. #90 (Xtream adapter) needs #50. #57 source operations needs #40 and #35.
- #35 autonomous operations (largest thread, 185 comments) needs #36, #40 and #42. #52 notifications needs #35, #49 and #50.
- #39 stream health needs #36 and #35.

**E. Living-room product (Phases 2 and 4)**

- #62 epic ("One Guide, Every Screen") groups #63 search, #64 watchlist, #65 continue watching, #67 deep links, #68 DVR and timeshift, #69 profiles, #70 best source, #71 subscriptions.
- #186 universal live guide needs #28 to #30, #35, #40, #175. #187 provider availability needs #50 and #67. #188 SER8 client needs #62, #63, #67, #70.
- #189 account connections needs #187 and #188 (only when a connected service needs them). #196 backend and thin client, #197 other platforms, #192 composition, #193 performance and #194 zero-instruction UX all sit on #188.
- #190 six-month delivery gate and #195 delivery system sit over everything in E.

**F. Delivery gates (Phase 5)**

- #164 alpha readiness gate needs #173 (portable server bundle) and #175. #190 needs #175, #186 to #189.

## 3. Order the map supports

1. Phase 1: #40, then #175, then #191 and #41. Needs #36 only for speed targets, not to start.
2. Phase 2: #187 (capability declaration), #67 (launch), #188 (SER8 client).
3. Phase 3: #29, #30, #31, #32, then #121 and #38. Then #35 and #57.
4. Phase 4: #46 and #49, then #63, #70, #189.
5. Phase 5: #164, #173, #190.

## 4. Gaps and risks found

- 26 open issues have no milestone. They should get one or be closed as duplicates once Phase 1 starts.
- #35 has 185 comments and #60 has 193. Both are hard to read; each needs a short current-state summary at the top (planned in Phase 1).
- #148 (Dispatcharr v0.31.0 watch) is out of date: the real setup runs Dispatcharr 0.33.0.
- The strategy date of March 31, 2027 is not confirmed.
