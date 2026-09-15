# Troubleshooting

This page answers: **something went wrong — how do I fix it myself, or report it safely?**

## Environment problems

| Symptom                                                 | Likely cause                                         | What to do                                                                                    |
| ------------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `Import-Module` reports a parse error                   | Wrong PowerShell version or edition                  | Confirm `$PSVersionTable.PSVersion` is 7.6 or later and `$PSVersionTable.PSEdition` is `Core` |
| `Install-Module` fails with a trust prompt              | PSGallery not yet trusted                            | Run `Set-PSRepository -Name PSGallery -InstallationPolicy Trusted` first                      |
| `Invoke-Pester` reports "command not found"             | Pester not installed for this user, or wrong version | Re-run `Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck`  |
| A `Read-ChannelForge*` function throws "file not found" | Wrong working directory                              | Run commands from the repository root, or pass an absolute path                               |

This table mirrors [INSTALL.md](../reference/INSTALL.md)'s — check there too if your problem isn't here.

## Local web server

Start the read-only local web foundation from the repository root:

```powershell
pwsh -File .\scripts\Start-ChannelForgeWebServer.ps1
```

Then open `http://127.0.0.1:8765/`. The page should say **ChannelForge is
running**, **No lineup has been accepted yet**, and **Open Guided Setup to
begin**.

| Symptom                                    | Likely cause                         | What to do                                                                                              |
| ------------------------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| Browser reports connection refused         | The foreground server is not running | Start the command above and leave that window open                                                      |
| Server reports that the address is in use  | Another process owns port 8765       | Run `pwsh -File .\scripts\Start-ChannelForgeWebServer.ps1 -Port 8766` and open `http://127.0.0.1:8766/` |
| A request returns `405 Method Not Allowed` | The foundation is read-only          | Use `GET` or `HEAD`; state-changing methods are intentionally blocked                                   |
| A remote machine cannot connect            | The listener is loopback-only        | This foundation does not expose a public or LAN listener                                                |

The `/health` and `/api/status` endpoints return safe status JSON only. They do
not expose provider URLs, credentials, private paths, hashes, generation IDs,
or parser details. Stop the foreground server with `Ctrl+C`.

## Build problems

| Symptom                                                    | Likely cause                                                                                                         | What to do                                                                                                                                                       |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Refusing to read from outside the approved location`      | A configured path (e.g. `local_playlist`, or a `-ProviderPath` override) resolves outside the folder it's allowed to | Fix the path — this guardrail exists to stop accidental or malicious path traversal, never work around it                                                        |
| `Multiple local provider files found`                      | More than one `data/providers/*.local.json` exists                                                                   | Keep exactly one, or use an explicit `-ProviderPath` override (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md#advanced-pointing-at-a-specific-file)) |
| `Provider source '...' has a malformed or unsupported URL` | A source's `url` field isn't a well-formed `https://` URL                                                            | Every source URL is validated before the local or bounded remote path uses it — use a real or `example.invalid`-style well-formed URL                            |
| No channels in `merged.m3u`, or fewer than expected        | An enabled source is missing both a usable `local_playlist` and a supported remote `url`                             | The build fails closed with a configuration error before build reports are created; correct the source configuration                                             |
| `Provider file not found`                                  | Neither an override, a local file, nor the tracked fallback resolved to a real file                                  | Confirm `data/providers/provider.local.json` exists, or that the tracked `data/providers/mybunny.json` example wasn't deleted                                    |

## "Where are the logs?"

There isn't a separate log file today. `output/reports/build-summary.json` (machine-readable) and `output/reports/lineup-plan.md` (human-readable) are the record of what a build did — check those first. Neither ever contains a provider URL, account ID, or token, so they're safe to share if you need help (see below).

## Validation failures

If you're working on the repository itself (not just running a build), schema and lint failures come from the gate scripts described in [DEVELOPER_GUIDE.md](../developer/DEVELOPER_GUIDE.md#ci-quality-gates) — that's engineering-facing detail this page won't repeat.

## GUI lineup review

The lineup review screen is a read-only summary of one local M3U playlist and one local XMLTV guide after bounded structural checks and native exact identity matching.

- **Checked** means every playlist entry has one exact guide match.
- **Needs attention** means one or more playlist entries have no guide match, and/or the guide contains guide-only channels. Guide-only coverage is informational and does not remove anything.
- **Review needed** means duplicate or non-unique identity relationships prevent safe automatic selection. ChannelForge does not choose an ambiguous relationship automatically.
- **Blocked** means the files are missing, not ready, unavailable, stale, or unsafe to inspect. Return to Guided Setup and check both files again.

The review reports aggregate counts only. It does not display channel IDs, programme titles, stream URLs, filenames, paths, credentials, or parser errors. Review and plan preparation are read-only; only an acknowledged Save action can request native acceptance.

### GUI saved lineup

The GUI can prepare a saved-lineup plan only after native matching reports **Checked**. Needs-attention (including guide-only coverage), review-needed, blocked, checking, not-checked, stale, and unavailable states are intentionally save-blocking. The review page remains read-only until **Prepare save** returns a ready plan.

If **Save lineup** is disabled, first resolve the match state and run **Prepare save** again. The confirmation checkbox is required; it is deliberately not remembered between dialogs. Cancel, Escape, closing the dialog, or leaving the checkbox clear performs no native acceptance call and does not change accepted state.

If the native plan or acceptance is unavailable, confirm that the selected workspace contains the expected ChannelForge inputs and that `pwsh` is installed. Native output is not shown in the GUI. If acceptance reports a stale result, re-run the match and prepare a new plan; the old candidate is discarded and cannot be retried as accepted state.

After a successful native acceptance, **Your saved lineup** is available as a redacted, read-only view. It is not an export, scheduler, target-publishing, release, or tester-distribution feature.

## FAQ

**Why does the build fail instead of just skipping a bad source?**
A malformed provider/EPG URL or an out-of-bounds path fails the whole build on purpose. ChannelForge prefers a loud, early failure over silently producing a partial or wrong lineup — see [ADR 0005](../adr/0005-evidence-over-assumptions.md).

**Can I run a build without a real provider playlist, just to see it work?**
Yes — running `Build-Lineup.ps1` against the repository's tracked example data (no `*.local.json`, no real playlist) validates your source-of-truth configuration and produces a report with `Status: SOURCE_OF_TRUTH_VALIDATED`, just without a `merged.m3u` (no source has a `local_playlist` configured). This is a safe way to confirm your environment works before bringing in real data.

**Is there a web UI yet?**
The primary UI direction is a browser-based local web UI served by the ChannelForge engine. A minimal read-only loopback shell and health/status API are available at `http://127.0.0.1:8765/` after running the local server command above; full UI, API, Docker, and Windows server/service support are not implemented yet. Existing Tauri/React work is an optional reusable reference and future packaging path; it currently includes a native picker bridge that checks pre-parse availability, expected kind, and read access. A selected M3U playlist and local XMLTV guide receive bounded structural checks and a single-guide exact identity comparison. The optional wrapper reports only safe status, reason, and aggregate matched, unmatched, ambiguous, and guide-only counts. It never opens or displays stream URLs, programme titles, or guide channel IDs, and it does not build lineups, save changes, export, or update providers. If matching reports needs attention or review needed, choose corrective inputs and rerun the check; do not treat the optional wrapper as the deployment contract.

## Reporting a bug safely

1. Reproduce the problem and gather `output/reports/build-summary.json` / `lineup-plan.md` if relevant — these are safe to share as-is (no secrets).
2. **Never paste a real provider URL, account ID, token, or playlist file contents into an issue, even to demonstrate the bug.** Redact it first, or describe its shape (e.g. "a malformed `https://` URL") instead of pasting it.
3. Open a [GitHub Issue](https://github.com/Jumpstile/ChannelForge/issues) describing what you ran, what you expected, and what happened.
4. If you're unsure whether something you're about to paste is sensitive, treat it as sensitive — see [SECURITY.md](../reference/SECURITY.md) for the full policy on what counts as a secret in this project.

## Where to go next

- Still stuck after a build issue? → re-check [Build Your First Lineup](Build-Your-First-Lineup.md) and [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md).
- Want to know if something is a limitation rather than a bug? → [Current Limitations](CURRENT_LIMITATIONS.md).
