# Port note: visual identity (#41) and catch-up (#59)

Status: design plus one small report-only function. Based on the real old scripts in the owner's OneDrive (not in GitHub). Nothing was copied into this repo. Old code was read, not run.

## Old scripts, in plain words

| Script                                                     | What it does                                                                                                                                                                          | Main covers                                                                                                          | Port?                                                                                 |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `Compare-ChannelForgeChannelArtworkSources.ps1` (41 lines) | Compares each channel's playlist logo with its guide icon by SHA-256 of the link. States: agreement, conflict, playlist-only, guide-only, missing. Report has fingerprints, no links. | Main builds the guide icon from the playlist logo, so they agree by design. A given external guide can still differ. | Yes. Built as `Get-ChannelForgeLogoSourceComparison` (private, pure)                  |
| `Publish-ChannelForgeVisualIdentityAssets.ps1` (115 lines) | Copies approved local image files into `output\visual-identity` under hash names, with a rights check and a report.                                                                   | Main links public https logos only. No copies.                                                                       | No. This is hosting. Conflicts with the owner rule (link-only, no caching or hosting) |
| `Run-ChannelForgeRefresh.ps1` (795 lines)                  | Refresh loop. Has the event guide chain and a publish merge. Searched for catch-up: no catch-up handoff or routing lives in it.                                                       | Not applicable                                                                                                       | Event parts: see event note                                                           |
| `Resolve-ChannelForgeCatchupCapabilities.ps1` (139 lines)  | Reads catch-up facts per channel (mode, days, source template), classifies the template shape, bounds guide look-back days by target profile, writes a report.                        | Main has no catch-up facts at all (see below)                                                                        | Later, as a report, after a reader slice                                              |
| `Resolve-ChannelForgeCatchupRoute.ps1` (63 lines)          | Turns a content id plus device plus entitlement into a provider hand-off link from a catalog. Never launches.                                                                         | Nothing                                                                                                              | No. It is routing to a provider UI; out of scope                                      |

The 2026-08-15 checkpoint copies: Compare and Publish are identical to Repo-beta apart from line endings (checked with a diff that ignores them). Event guide and Refresh differ only in wording ("programme" vs "program") and one `-Unattended` switch in the Repo-beta Refresh. No logic differs.

## Visual identity (#41)

Keep: link-only public https logos, pins, the pre-accept logo report (already in main), and the source comparison report. Reject: asset publication (hosting), rights catalog of local files, web publication summary (UI). Remote lookup stays an explicit bounded step, off by default.

Built slice: `Get-ChannelForgeLogoSourceComparison`. Input: rows of id and logo, rows of id and icon. Output: one row per id with a state word and 12-character fingerprints. It never returns a link. It is not wired into the build and no output byte changes. One test with invented fixtures (passed, run alone).

Not done: a public command that reads a playlist and a guide and calls it. That needs the guide reader to expose channel icons; not checked.

## Catch-up (#59)

Facts from main (read in this tree):

- `ConvertTo-ChannelForgeM3UEntryBytes` writes only `tvg-id`, `tvg-name`, `tvg-logo`, `tvg-chno`, `group-title`.
- No `catchup`, `catchup-days` or `catchup-source` property was found in the Channel class or the M3U reader. Main drops them on read.

Can catch-up attributes be written without changing the frozen M3U entry byte format? **No.** Adding any attribute to an entry changes its bytes, and the byte format is frozen. An entry with no catch-up facts would stay byte-identical, but an entry with them would not, so the contract itself must be versioned. Safe options that change no entry bytes:

1. Report only: a catch-up evidence report next to the build (what each source declares, shape of template, no links). Recommended first step.
2. A sidecar file keyed by tvg-id for a client that wants it.
3. A new entry format version, decided by the owner, with a fixture proof that entries without catch-up stay identical.

Conflicts with owner decisions: the Xtream template classification touches provider links, so output must keep only the shape word and a hash, as the old script does. The route resolver is a launcher and is out. Playback, proxying and sessions stay out of scope. Guide look-back must not claim playback just because past programmes exist.

Slices: (1) reader keeps catch-up facts on the Channel object, no output change, prove with unchanged hashes; (2) evidence report; (3) owner decides on entry format version.

## Owner decisions

1. Catch-up in M3U entries: report and sidecar only, or version the entry format? Recommendation: report only.
2. Hosting of visual identity files: confirm rejected. Recommendation: reject.
3. Event guide merge into the normal guide: confirm rejected. Recommendation: reject, keep the separate file.
