# IPTVBoss Parity Matrix

This page tracks issue 154: which useful IPTVBoss outcomes ChannelForge has, which it does not, and where each one is routed.

- IPTVBoss is **not a runtime dependency** of ChannelForge. Nothing here requires it. ChannelForge only reads AED-derived XMLTV and can back up IPTVBoss files (`scripts/Backup-IPTVBoss.ps1`).
- This page does not copy IPTVBoss internals, private formats, or screens.
- Statuses come from the repo audit of issues 154 and 164. They are not upgraded here. "Not run" means no test was run for this page.
- Anything not built is marked **NOT BUILT**.
- Items marked "proposed, owner can change" are a recommendation, not a decision.

Status words: **Built**, **Partial**, **Not built**, **Out of alpha.1**.

Issue numbers are only the ones listed in issue 154. "None listed" means issue 154 gives no number for that outcome; the owner must route it.

| Outcome                                             | Status                                                 | Evidence (file or doc)                                                                                                                                        | Issue         |
| --------------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| AED import or translate                             | Not built. NOT BUILT (by design)                       | `docs/research/iptvboss-docker-integration.md`: no documented export format. Only AED-derived XMLTV is read.                                                  | #121          |
| Export native event rules in a stable format        | Out of alpha.1 (proposed, owner can change). NOT BUILT | No export command in `src/ChannelForge/Public`.                                                                                                               | #121          |
| Several event rules without hand-written regex      | Partial                                                | `Invoke-ChannelForgeGuidePatternInference`, `Get-ChannelForgeGuidePatternReview`; report-only. Tests `GuidePattern*.Tests.ps1`.                               | #121          |
| Defaults and inheritance                            | Not built. NOT BUILT                                   | No inheritance code found in product code.                                                                                                                    | #26           |
| League and single-team event groups                 | Partial                                                | `Get-ChannelForgeEventChannelCandidate`, `Get-ChannelForgeEventChannelReport`; `docs/planning/EVENT-AWARE-CHANNELS-DESIGN-NOTE.md`. Group types not verified. | #28, #30, #38 |
| ESPN+ / platform-prefixed event visibility          | Out of alpha.1 (proposed, owner can change). NOT BUILT | Only in design notes. Not verified in code.                                                                                                                   | #121          |
| Fallback-chain preview before a rule affects output | Partial                                                | Pattern review is report-only. No fallback-chain preview found.                                                                                               | #121          |
| Expert regex escape hatch                           | Not built. NOT BUILT                                   | `docs/user/CURRENT_LIMITATIONS.md` lists expert regex as not in alpha.1.                                                                                      | #121          |
| "Where is this assigned?" lookup                    | Not built. NOT BUILT                                   | No lookup command, API route, or GUI page.                                                                                                                    | None listed   |
| Layouts, output profiles, linked views              | Not built. NOT BUILT                                   | One profile file only: `data/compatibility/generic-m3u-xmltv.profile.json`; `docs/architecture/DOWNSTREAM_COMPATIBILITY_PROFILES.md`.                         | None listed   |
| New group and new channel detection                 | Not built. NOT BUILT                                   | Refresh reports unchanged, changed, or unavailable per source only (`scripts/Invoke-ChannelForgeSourceRefresh.ps1`).                                          | #35           |
| Delayed removal of missing channels                 | Partial                                                | Source level only: last-known-good kept on failed refresh (`scripts/Invoke-ChannelForgeSourceRefresh.ps1`). No channel-level grace state.                     | #35           |
| Provider mode: static URL and local file            | Built                                                  | `Get-ChannelForgeRemoteSourceBytes`, `Import-ChannelForgeConfiguredM3USource`; `docs/adr/0014-secure-bounded-https-acquisition-transport.md`.                 | None listed   |
| Provider mode: Xtream Codes                         | Out of alpha.1 (proposed, owner can change). NOT BUILT | Only mentioned in ADR 0014 and `docs/planning/PHASE-0-FINDINGS.md`.                                                                                           | None listed   |
| Token and credential provenance, no secret leaks    | Partial                                                | `docs/adr/0002-secrets-policy.md`; redacted status. Remote credential enrollment is unchecked in `docs/release/FIRST_USABLE_ALPHA.md`.                        | None listed   |
| Fail closed on auth errors or provider mode change  | Partial                                                | A failed source keeps its last-known-good copy. Auth-error handling not verified.                                                                             | None listed   |
| Scheduled refresh without the browser               | Partial                                                | Windows Task Scheduler only: `scripts/Install-ChannelForgeScheduledRefresh.ps1`. Review-only, never auto-accepts.                                             | #35           |
| Docker operation                                    | Out of alpha.1 (proposed, owner can change). NOT BUILT | No Dockerfile. `docs/user/CURRENT_LIMITATIONS.md`: implementation pending.                                                                                    | #35           |
| Windows service                                     | Out of alpha.1 (proposed, owner can change). NOT BUILT | `docs/user/CURRENT_LIMITATIONS.md`: not implemented.                                                                                                          | #35           |
| Run status, last success, next run in the web UI    | Partial                                                | `Get-ChannelForgeWebStatus.ps1` shows source status and next action. No last success or next run there. CLI: `Get-ChannelForgeScheduledRefreshStatus.ps1`.    | #35           |
| Lock safety, no overlapping writes                  | Built                                                  | Exclusive lock lease in `Initialize-ChannelForgeGenerationStore.ps1`; used by `Invoke-ChannelForgeGenerationStore.ps1`; fails closed.                         | None listed   |
| Stale lock versus active run, safe recovery         | Partial                                                | Stale threshold and heartbeat settings in `Initialize-ChannelForgeScheduledOperation.ps1`. A live heartbeat write was not verified.                           | None listed   |
| Resume after interruption                           | Partial                                                | Accepted state has a journal and `Recover-ChannelForgeAcceptedState`. Refresh resume not verified.                                                            | #35           |
| Beginner-first standard                             | Process rule, not testable                             | Audit: unverifiable.                                                                                                                                          | None listed   |
| No IPTVBoss at runtime, no copying                  | Built                                                  | No runtime dependency found. `tests/*BackupIptvBossScript.Tests.ps1` covers the backup script only.                                                           | None listed   |

## Related issues listed in issue 154

#147 (event metadata freshness), #24 (AI-assisted rule authoring, review-only), #31 (controlled auto-learning, rollback), #40 (multi-guide XMLTV merge), #153 (multi-M3U aggregation, channel numbers, duplicates). The audit found these only partly or not at all in the repo, so the matrix does not claim them as built.

## Not verified

- Issue comments and live GitHub state. Issue numbers are not tracked inside the repo.
- Group types for event channels, ESPN+ code paths, auth-error handling, live lock heartbeat, refresh resume.
