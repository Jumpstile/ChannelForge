# Clean-machine smoke for the Windows package

This page shows how to test a candidate Windows package on a fresh, throwaway Windows. It uses Windows Sandbox, so nothing touches your real PC. It never creates a release or a tag.

The smoke installs the package, starts it, adds fixture sources, restarts, refreshes, checks for updates, and uninstalls. It writes a record with one PASS, FAIL, or NOT RUN line per step.

## What you need

- Windows 10 or 11 Pro, Enterprise, or Education with the **Windows Sandbox** optional feature turned on.
- PowerShell 7 and git on the host.
- A candidate ZIP and its `.evidence.json` file side by side.

## Run it

1. Build the candidate from one exact commit. Follow [BUILD_FROM_EXACT_SHA.md](BUILD_FROM_EXACT_SHA.md). Keep the ZIP and the `<zip>.evidence.json` file together.
2. Check out that same commit in a clean working folder. `git status --porcelain` must print nothing.
3. In PowerShell 7, from the repo root, run:

   ```powershell
   ./scripts/smoke/New-ChannelForgeSmokeLaunch.ps1 -PackagePath <path-to-the-ZIP>
   ```

4. The launcher checks the ZIP and the checkout. It stops with a plain message if the ZIP is missing, its SHA-256 differs from the evidence file, or the checkout is dirty or at a different commit.
5. A Windows Sandbox window opens and runs the smoke by itself. Do not click inside it. While it runs, the launcher prints the latest `progress.txt` line every 15 seconds. A run is normally a few minutes and never longer than the overall limit (20 minutes).
6. When the run ends, the launcher prints the evidence path. It exits with 0 only when the overall result is PASS.
7. Close the sandbox window. Everything inside it is deleted.

## Where the evidence goes

Under `%TEMP%\ChannelForgeSmokeResults\run-<time>\results` (change the root with `-ResultsRoot`):

- `ChannelForge-smoke-evidence.txt` for people.
- `ChannelForge-smoke-evidence.json` for tools.
- `progress.txt`, one line per event: time, step number, step name, then `STARTED` or the result. It is written during the run, so you can open it while the sandbox is still working. The last line tells you which step is running or stuck.

Both hold the ZIP SHA-256, the source commit from the package manifest, and every step. The overall result is PASS only when every step is PASS. Any FAIL makes it FAIL. A run with a NOT RUN step is INCOMPLETE, never PASS.

## What each step proves

| Step                  | What it proves                                                                            |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `package-hash`        | The ZIP inside the sandbox is the ZIP the build recorded.                                 |
| `unzip`               | The ZIP unpacks and carries `package-manifest.json`.                                      |
| `commit-match`        | The package manifest names the same source commit as the evidence file.                   |
| `install`             | `Install ChannelForge.cmd -SkipStart` copies the app to `%LOCALAPPDATA%\ChannelForge`.    |
| `start`               | The bundled PowerShell starts the server and `/health` answers.                           |
| `web-page`            | The local page at `http://127.0.0.1:8765/` answers with HTML.                             |
| `status-empty`        | A fresh install says no lineup is accepted yet.                                           |
| `proposal`            | Fixture M3U and XMLTV files analyze to a reviewable proposal.                             |
| `accept`              | Accepting the proposal saves a lineup and the sources.                                    |
| `status-accepted`     | The status API reports the accepted lineup and saved sources.                             |
| `restart-state`       | After stop and start, the accepted lineup and sources are still there.                    |
| `refresh`             | Refresh of the saved fixture sources answers with a normal result.                        |
| `update-check-local`  | `Update ChannelForge.cmd` reads the local package, reports it valid, and changes nothing. |
| `update-same-version` | `Update ChannelForge.cmd` refuses the same version and no file changes.                   |
| `update-check-github` | Always NOT RUN. The sandbox has no network on purpose.                                    |
| `uninstall-cancel`    | A wrong confirmation word shows "Cancelled" and removes nothing.                          |
| `uninstall-keep`      | `-Verbose` (no menu) removes the app and keeps the lineup and sources.                    |
| `uninstall-delete`    | `-PurgeData -ConfirmPurge` removes the install folder (waits up to 30s).                  |

The proposal, accept, and refresh steps call the product's own local API with the files in `tests/fixtures/smoke`. They use `example.invalid` addresses and no credentials.

## What is NOT covered

- Code signing. The package is not signed, so SmartScreen and Defender prompts are not tested.
- A real provider. No real playlist, guide, token, or account is used.
- GUI screenshots. The smoke calls the local API and checks that the page answers. It does not click through the browser.
- The GitHub release update check. It needs a network and a published release.
- Anything that needs a real Plex, Dispatcharr, or IPTV Boss setup.
- The typed uninstall menu itself (choosing 1 or 2, typing DELETE). The sandbox does not deliver typed answers to the `.cmd`, so this smoke cannot verify it. A person must check it at a real console. The cancel step passes only if the output shows "Cancelled" and nothing was removed; if the menu was not reached, it fails with the output head.

## If a step fails

Read the detail in brackets on the failing line. Later steps that depend on it show NOT RUN with "Not reached". Server logs are inside the sandbox only. To keep them, copy the failing step's command into a normal test folder on a spare machine and rerun it by hand.

## Time limits

- Every step that starts a program has a hard limit of 120 seconds (`-StepTimeoutSeconds` on `Invoke-ChannelForgeSmoke.ps1`). A step that reaches it is FAIL with the detail "timed out", never PASS. Its programs are stopped, and the run goes on. Steps that need the failed one show FAIL or NOT RUN, never PASS.
- The whole run has a limit of 20 minutes (`-OverallTimeoutMinutes`). When it is reached, the evidence so far is written. A `run` line is FAIL with "timed out", and steps not reached are NOT RUN.
- Programs run with their input closed, so none can wait for a key press. The smoke runs the real `Install ChannelForge.cmd`, `Update ChannelForge.cmd`, and `Uninstall ChannelForge.cmd`. Install runs with `-SkipStart`, and two uninstall steps run with command-line options, which skip the menu. The cancel step feeds the menu typed answers from a file; its closing `pause` returns when the file ends. `Update ChannelForge.cmd` always applies, so the update steps expect a refusal (the bundle is the installed version).

## Run the tests for the smoke files

These tests run without a sandbox. They cover the launcher checks, the template fill, and the evidence writer.

```powershell
Invoke-Pester -Path tests/unit/ChannelForgeSmoke.Tests.ps1
```

They do not run Windows Sandbox, so they do not prove the steps above pass.
