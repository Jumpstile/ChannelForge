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

## Build problems

| Symptom                                                    | Likely cause                                                                                                         | What to do                                                                                                                                                          |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Refusing to read from outside the approved location`      | A configured path (e.g. `local_playlist`, or a `-ProviderPath` override) resolves outside the folder it's allowed to | Fix the path — this guardrail exists to stop accidental or malicious path traversal, never work around it                                                           |
| `Multiple local provider files found`                      | More than one `data/providers/*.local.json` exists                                                                   | Keep exactly one, or use an explicit `-ProviderPath` override (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md#advanced-pointing-at-a-specific-file))    |
| `Provider source '...' has a malformed or unsupported URL` | A source's `url` field isn't a well-formed `https://` URL                                                            | Every source URL is validated before the local or bounded remote path uses it — use a real or `example.invalid`-style well-formed URL                               |
| No channels in `merged.m3u`, or fewer than expected        | A source is missing `enabled: true` or `local_playlist`                                                              | A source missing either is silently skipped, not an error — check `lineup-plan.md`'s "Provider M3U Sources" list, which states each source's enabled/playlist state |
| `Provider file not found`                                  | Neither an override, a local file, nor the tracked fallback resolved to a real file                                  | Confirm `data/providers/provider.local.json` exists, or that the tracked `data/providers/mybunny.json` example wasn't deleted                                       |

## "Where are the logs?"

There isn't a separate log file today. `output/reports/build-summary.json` (machine-readable) and `output/reports/lineup-plan.md` (human-readable) are the record of what a build did — check those first. Neither ever contains a provider URL, account ID, or token, so they're safe to share if you need help (see below).

## Validation failures

If you're working on the repository itself (not just running a build), schema and lint failures come from the gate scripts described in [DEVELOPER_GUIDE.md](../developer/DEVELOPER_GUIDE.md#ci-quality-gates) — that's engineering-facing detail this page won't repeat.

## FAQ

**Why does the build fail instead of just skipping a bad source?**
A malformed provider/EPG URL or an out-of-bounds path fails the whole build on purpose. ChannelForge prefers a loud, early failure over silently producing a partial or wrong lineup — see [ADR 0005](../adr/0005-evidence-over-assumptions.md).

**Can I run a build without a real provider playlist, just to see it work?**
Yes — running `Build-Lineup.ps1` against the repository's tracked example data (no `*.local.json`, no real playlist) validates your source-of-truth configuration and produces a report with `Status: SOURCE_OF_TRUTH_VALIDATED`, just without a `merged.m3u` (no source has a `local_playlist` configured). This is a safe way to confirm your environment works before bringing in real data.

**Is there a GUI I'm missing?**
No — see [Current Limitations](CURRENT_LIMITATIONS.md).

## Reporting a bug safely

1. Reproduce the problem and gather `output/reports/build-summary.json` / `lineup-plan.md` if relevant — these are safe to share as-is (no secrets).
2. **Never paste a real provider URL, account ID, token, or playlist file contents into an issue, even to demonstrate the bug.** Redact it first, or describe its shape (e.g. "a malformed `https://` URL") instead of pasting it.
3. Open a [GitHub Issue](https://github.com/Jumpstile/ChannelForge/issues) describing what you ran, what you expected, and what happened.
4. If you're unsure whether something you're about to paste is sensitive, treat it as sensitive — see [SECURITY.md](../reference/SECURITY.md) for the full policy on what counts as a secret in this project.

## Where to go next

- Still stuck after a build issue? → re-check [Build Your First Lineup](Build-Your-First-Lineup.md) and [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md).
- Want to know if something is a limitation rather than a bug? → [Current Limitations](CURRENT_LIMITATIONS.md).
