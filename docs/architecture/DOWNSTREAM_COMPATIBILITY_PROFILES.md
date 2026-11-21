# Downstream compatibility profiles

Status: design note plus one first profile. Most of the idea is not built yet. See "Not built yet" below.

## In plain words

ChannelForge builds one lineup and one guide. Different apps that read them (Plex, Jellyfin, Emby, Threadfin, xTeVe, Dispatcharr, IPTV Boss and others) can accept different things. A _compatibility profile_ is a small file that says what one target accepts, and how we know.

The rules:

- There is one canonical lineup. We never keep a second copy of channel data for a target.
- A target gets its own _target output_ (its own M3U and XMLTV files). The target output is written from the canonical data at the very end, when files are produced.
- Canonical names, IDs and numbers are never rewritten for a target. If a target cannot hold a fact, the fact stays in the canonical data and is left out of that target output only.
- We say how we know each fact. Five evidence states:

| State        | Meaning                                                    |
| ------------ | ---------------------------------------------------------- |
| `documented` | The target's own documentation says so.                    |
| `tested`     | A repeatable test in this repository shows it.             |
| `observed`   | Someone watched it happen once. Say when and how.          |
| `reported`   | Someone else says so. Not checked.                         |
| `unknown`    | No evidence. This is never "false" and never "compatible". |

A file that merely parses is not proof that a channel plays, binds to a guide, or shows artwork.

## Capability areas

A profile has one entry for each area:

- M3U header and `#EXTINF` attributes: `tvg-id`, `tvg-name`, `tvg-logo`, `tvg-chno`, `group-title`
- extended directives and stream request headers
- duplicate channel IDs and multiple stream variants
- channel-number formats and limits
- XMLTV ID binding and display-name behavior
- programme categories, icons, episode numbering, timezones
- catch-up and timeshift metadata
- local versus remotely served artifacts
- URL encoding, character set, line endings, file-size and channel-count limits
- refresh and poll behavior, atomic publication
- authentication and secret handling

Each entry has a `value` (plain words) and an `evidence` object (`state` and `source`). If the state is `unknown`, the value must be exactly `unknown`.

The generic target ignores catch-up. ChannelForge writes no catch-up or timeshift attributes, so a downstream app gets none from this output. If a source playlist declares catch-up, ChannelForge only reports it (shape and declared archive days) and never writes it. Fallback wording for users: "Catch-up is not provided by this output. Watch live, or use your provider's own app for past programmes."

## Not touched

- Guide-id contract v1.0 is not touched.
- Accepted state, source enrollment, scorecards and evidence records are not touched.
- No existing output byte changes. The current M3U and XMLTV exporters are unchanged.
- The word "projection" stays with the one-guide projection schema. This note uses "target output".

## Technical section

- Schema: `schemas/compatibility-profile.schema.json`. Required: `id`, `version` (`x.y.z`), `capabilities`. Every capability name is required, so a missing area is an error rather than a silent gap.
- First profile: `data/compatibility/generic-m3u-xmltv.profile.json`. It describes today's generic output, not a downstream app. Here `documented` means documented in ChannelForge's own code, and `tested` means a test in this repository. Everything else is `unknown`.
- Loader: `Get-ChannelForgeCompatibilityProfile -Path <file>` reads one file, validates it with `Test-Json` against the schema, and returns the object. It fails with a plain message on a missing or invalid file. It writes nothing.
- `scripts/Validate-ConfigSchemas.ps1` validates the example profile.

## Not built yet

- Profiles for any real target (Plex, Jellyfin, Emby, Threadfin, xTeVe, Dispatcharr, IPTV Boss, HDHomeRun-style).
- Target selection, and writing target outputs.
- Preview of omissions and transformations, and guide-binding risk reports.
- Golden fixtures per target, and import tests against real applications.
- Profile version change diffs and migration.
- A capability matrix in the GUI.
- Per-target user overrides.
