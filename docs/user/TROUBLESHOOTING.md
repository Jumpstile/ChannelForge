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

To serve the existing React/Vite build first:

```powershell
Push-Location .\gui
npm ci
npm run build
Pop-Location
pwsh -File .\scripts\Start-ChannelForgeWebServer.ps1
```

Then open `http://127.0.0.1:8765/`. When `gui/dist/index.html` is absent, the
safe placeholder appears. When the build exists, the landing dashboard fetches
`GET /api/status` from the same origin and should say **ChannelForge is
running**, show whether **No lineup has been accepted yet** or **An accepted
lineup is available**, and give the matching Guided Setup next action. It also
explains that the page is read-only and cannot change your lineup.

If the status request returns `503`, fails over the network, or contains an
unknown shape, the dashboard shows **ChannelForge status is unavailable**.
Refresh after confirming that the local server is still running; raw server
errors are intentionally not shown.

| Symptom                                             | Likely cause                                                | What to do                                                                                                                                        |
| --------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Browser reports connection refused                  | The foreground server is not running                        | Start the command above and leave that window open                                                                                                |
| Server reports that the address is in use           | Another process owns port 8765                              | Run `pwsh -File .\scripts\Start-ChannelForgeWebServer.ps1 -Port 8766` and open `http://127.0.0.1:8766/`                                           |
| Built UI does not appear                            | `gui/dist/index.html` is absent                             | Run the build commands above, or use the safe placeholder intentionally                                                                           |
| A static asset returns `404 Not Found`              | The path is unknown or its type is unsafe                   | Confirm the asset exists under `gui/dist` and uses a supported static extension; directory listing is disabled                                    |
| A request returns `405 Method Not Allowed`          | The method is not allowed for that endpoint                 | Use `GET`/`HEAD` for status/static reads, `POST` for the bounded Guided Setup proposal/acceptance or empty-body saved-source refresh              |
| A status endpoint returns `503 Service Unavailable` | Accepted-state metadata failed validation                   | The dashboard shows a safe unavailable message; the server stays read-only; inspect accepted-state recovery diagnostics before changing any state |
| Dashboard says status is unavailable                | Server stopped, network failure, or invalid status response | Confirm the loopback server is running, then refresh; raw response details are intentionally hidden                                               |
| A remote machine cannot connect                     | The listener is loopback-only                               | This foundation does not expose a public or LAN listener                                                                                          |

The `/health` and `/api/status` endpoints return safe status JSON only. They do
not expose provider URLs, credentials, private paths, hashes, generation IDs,
or parser details. Stop the foreground server with `Ctrl+C`.

## Browser Guided Setup review and acceptance

The browser flow accepts one or more M3U/M3U8 playlists and optional XMLTV
guides, supplied as local files or public HTTPS URLs. Local file contents are
sent as a bounded JSON/base64 request; the browser never sends a local path.
The server returns an opaque review handle and stores the candidate in its
server-owned review namespace. **Workspace ready** is informational; this flow
does not ask the user to choose a folder.

| Symptom                                       | Likely cause                                                                              | What to do                                                                                                                          |
| --------------------------------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Analyze is unavailable                        | One or more playlist or guide rows are incomplete                                         | Complete every configured row; the footer counts ready playlists                                                                    |
| Analysis stopped after an error               | The request or one of its sources could not be safely analyzed                            | Read the focused error banner, correct the file or URL, and retry; selected sources remain available                                |
| Required analysis data is missing             | The installed package is incomplete                                                       | Repair or reinstall ChannelForge; user configuration is not replaced by this repair                                                 |
| A playlist or guide is invalid                | Its content does not match M3U/M3U8 or XMLTV structure                                    | Choose a valid source file; parser details and local paths are intentionally hidden                                                 |
| A source URL is unsupported                   | It is not a public HTTPS URL, or it contains credentials, query parameters, or a fragment | Use a local file or a public HTTPS URL without credentials, query parameters, or fragments                                          |
| A public HTTPS source is unavailable          | The remote host could not be safely retrieved                                             | Check the URL and connection, then retry                                                                                            |
| Acceptance is blocked                         | A candidate review blocker needs resolution                                               | Resolve the displayed review blocker; ChannelForge never guesses a guide binding                                                    |
| Acceptance says the proposal is stale         | Another acceptance changed the reviewed parent                                            | Return to Guided Setup and analyze the files again; ChannelForge never rebases a stale review automatically                         |
| Acceptance says the proposal was already used | The opaque review session is terminal                                                     | Do not resubmit it; analyze a new proposal when the source files change                                                             |
| Acceptance verification failed                | The durable candidate or session was altered                                              | Do not retry the same handle; analyze the files again and preserve the server response for diagnostics                              |
| A guide is unbound                            | No playlist was explicitly selected for that guide                                        | Select one or more playlists, or explicitly choose **All playlists**; unbound guides remain enrolled for review but are not applied |

Each guide starts unbound, including when only one playlist is configured.
Choose the playlist(s) a guide covers before analysis. **All playlists** is a
separate explicit choice. No selection means the guide remains unbound;
it is not interpreted as “all playlists.” An unbound guide can remain in the
accepted source enrollment, but it is not applied to a playlist or published as guide output.

The proposal endpoint caps the encoded request at 24 MiB, and the acceptance
endpoint caps its strict acknowledgement envelope at 8 KiB. The browser sends
only `schemaVersion`, the opaque `proposalId`, and `acknowledged=true` to
`POST /api/guided-setup/accept`; it never sends files, paths, hashes, parent
state, or a force option.

The acceptance boundary verifies candidate bytes, coverage, ambiguity state,
and the accepted parent before publishing the immutable generation graph. It
does not refresh downstream consumer files, configure a scheduler, or mutate
provider state. `/api/status` is updated after successful acceptance; its
status page remains read-only.

### Saved-source status and refresh

After browser acceptance, the Workbench reports **Sources saved** when the
server-owned local enrollment record and managed bytes pass integrity checks.
Restarting the server does not require another upload. The playlist and guide
cards are derived status only; they never reveal paths, hashes, source IDs, or
credentials.

Use **Refresh now** to re-check saved bytes. **Up to date** means the saved
bytes are unchanged. **Changes found** means a review-only candidate was
created; no accepted lineup changed. Use **Replace sources** to return to
Guided Setup and explicitly review a new upload.

| Symptom                               | Meaning                                                   | What to do                                                                                                              |
| ------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Sources not saved**                 | No browser acceptance has enrolled sources                | Open Guided Setup, choose the playlist and optional guide, analyze, acknowledge, and accept                             |
| **Needs attention**                   | The enrollment record failed integrity validation         | Do not edit state files; use Replace sources to create a new server-owned enrollment                                    |
| **Source unavailable**                | A managed source is missing, unsafe, or unreadable        | Use Replace sources; the accepted lineup remains unchanged                                                              |
| **Changes found**                     | Managed source bytes differ from the enrolled fingerprint | Review the refresh result, then replace and accept sources explicitly if intended                                       |
| Refresh reports an unavailable result | Refresh could not safely read or analyze the saved bytes  | Preserve the report, confirm the server owns its state directory, and use Replace sources; do not delete accepted state |

Remote credential enrollment is not part of this slice. The browser flow
supports local uploaded M3U and optional XMLTV bytes only.

If the loopback server is stopped, restart it from the repository root and
reload the page. Do not paste playlist contents, stream URLs, credentials,
opaque proposal IDs, or private paths into bug reports.

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

**Is there a web UI yet?**
Yes. The built React/Vite landing dashboard is served by the local loopback
server and reads the safe `GET /api/status` contract. It shows whether
ChannelForge is running, whether an accepted lineup is available, and the next
Guided Setup direction without changing anything. A `503`, network failure, or
invalid response produces a safe unavailable message. Browser Guided Setup
proposal analysis is implemented through the bounded candidate-only endpoint
described above; browser acceptance and the Windows x64 portable bundle are
implemented. The bundle is loopback-only, does not install a Windows service,
and stores application state under `%LOCALAPPDATA%\ChannelForge`. Docker and
Windows server/service deployment remain future modes. Existing Tauri/React
work remains an optional reusable reference.

**Why does the build fail instead of just skipping a bad source?**
A malformed provider/EPG URL or an out-of-bounds path fails the whole build on purpose. ChannelForge prefers a loud, early failure over silently producing a partial or wrong lineup — see [ADR 0005](../adr/0005-evidence-over-assumptions.md).

**Can I run a build without a real provider playlist, just to see it work?**
Yes — running `Build-Lineup.ps1` against the repository's tracked example data (no `*.local.json`, no real playlist) validates your source-of-truth configuration and produces a report with `Status: SOURCE_OF_TRUTH_VALIDATED`, just without a `merged.m3u` (no source has a `local_playlist` configured). This is a safe way to confirm your environment works before bringing in real data.

## Reporting a bug safely

1. Reproduce the problem and gather `output/reports/build-summary.json` / `lineup-plan.md` if relevant — these are safe to share as-is (no secrets).
2. **Never paste a real provider URL, account ID, token, or playlist file contents into an issue, even to demonstrate the bug.** Redact it first, or describe its shape (e.g. "a malformed `https://` URL") instead of pasting it.
3. Open a [GitHub Issue](https://github.com/Jumpstile/ChannelForge/issues) describing what you ran, what you expected, and what happened.
4. If you're unsure whether something you're about to paste is sensitive, treat it as sensitive — see [SECURITY.md](../reference/SECURITY.md) for the full policy on what counts as a secret in this project.

## Where to go next

- Still stuck after a build issue? → re-check [Build Your First Lineup](Build-Your-First-Lineup.md) and [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md).
- Want to know if something is a limitation rather than a bug? → [Current Limitations](CURRENT_LIMITATIONS.md).
