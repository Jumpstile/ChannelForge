# Configuration Reference

A summary of the config files a build reads. Each one has an exact structural contract in `schemas/` — this page gives you the shape at a glance; the schema file is canonical if anything here is unclear or out of date.

For _how_ to set these up safely, see [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md) — this page is the field reference, not the walkthrough.

## Provider configuration

`data/providers/mybunny.json` (tracked example) or `data/providers/*.local.json` (your real config — see [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md)).

| Field                      | Required | Notes                                                                                                                                                                                                                     |
| -------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `provider`                 | Yes      | Display label. Appears in build reports — not secret-safe, see below.                                                                                                                                                     |
| `sources`                  | Yes      | Array of source entries, at least one.                                                                                                                                                                                    |
| `sources[].name`           | Yes      | Display label, must be unique in the file. Appears in build reports.                                                                                                                                                      |
| `sources[].group`          | No       | Optional grouping label.                                                                                                                                                                                                  |
| `sources[].url`            | Yes      | Provider source URL. Treated as a secret; validated for shape (scheme, host, no embedded credentials).                                                                                                                    |
| `sources[].enabled`        | Yes      | Whether this source is included in a build.                                                                                                                                                                               |
| `sources[].local_playlist` | No       | Path to a local `.m3u` file, relative to the repository root, confined to `data/playlists/`. Required (along with `enabled: true`) for a source to actually produce output today — see [Sources](../Concepts/Sources.md). |

Full schema: [`schemas/provider.schema.json`](../../../schemas/provider.schema.json).

## EPG source configuration

`data/epg/epg_sources.json` (tracked example) or `data/epg/*.local.json`.

| Field                    | Required            | Notes                                                                                                                                             |
| ------------------------ | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `epg_sources`            | Yes                 | Array of source entries, at least one.                                                                                                            |
| `epg_sources[].name`     | Yes                 | Must be unique in the file.                                                                                                                       |
| `epg_sources[].priority` | Yes                 | Integer; lower runs first.                                                                                                                        |
| `epg_sources[].url`      | One of `path`/`url` | Remote HTTPS XMLTV URL; acquired through the pinned port-443 transport with strict XML content types and no redirect/proxy/credential/retry path. |
| `epg_sources[].path`     | One of `path`/`url` | Local XMLTV path, resolved relative to the `epg_sources.json` directory; plain `.xml`, gzip `.gz`, and single-entry `.zip` are accepted.          |
| `epg_sources[].format`   | No                  | Optional; defaults to `xmltv`; only `xmltv` is supported.                                                                                         |
| `epg_sources[].enabled`  | Yes                 |                                                                                                                                                   |
| `epg_sources[].role`     | Yes                 | Free-text role label, e.g. `primary`, `fallback`.                                                                                                 |

Local EPG paths retain `.xml`, `.gz`, and single-entry `.zip` support. Remote URLs support plain XML plus HTTP identity/gzip/x-gzip codings only; cache, autonomous scheduling, ZIP-over-HTTP, and degraded publication remain out of scope. Full schema: [`schemas/epg_sources.schema.json`](../../../schemas/epg_sources.schema.json).

## Scheduled refresh policy

The report-only scheduled refresh planner reads `config/scheduled-refresh.local.json` when it exists and otherwise uses the tracked `config/scheduled-refresh.example.json`. The local file is ignored by Git; it must contain policy only, never provider URLs, credentials, tokens, or source payloads.

| Field                                       | Required | Notes                                                                                                 |
| ------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------- |
| `SchemaVersion`                             | Yes      | Must be `scheduled-refresh-policy/v1`.                                                                |
| `Enabled`                                   | Yes      | Autonomous scheduling switch. The safe example default is `false`; manual planning remains available. |
| `TimeZoneId`                                | Yes      | `UTC` in v1.                                                                                          |
| `Cadence.Mode` / `Cadence.At`               | Yes      | Daily cadence at `HH:mm`.                                                                             |
| `AllowedWindow.Start` / `AllowedWindow.End` | Yes      | Start-inclusive/end-exclusive UTC window. Overnight windows are rejected.                             |
| `JitterMinutes`                             | Yes      | Deterministic bounded jitter; it never uses process randomness.                                       |
| `MaxRunDurationMinutes`                     | Yes      | Future execution deadline; this report-only slice never starts a run.                                 |
| `StaleRunThresholdMinutes`                  | Yes      | Future heartbeat inactivity threshold.                                                                |
| `ManualOverride`                            | Yes      | Controls explicit manual planning while disabled or outside the window.                               |
| `Notification`                              | Yes      | Consecutive scheduled-run thresholds for Degraded and ReviewNeeded items.                             |

Validate the example policy with:

```powershell
Test-Json -Path config/scheduled-refresh.example.json `
  -SchemaFile schemas/scheduled-refresh-policy.schema.json
```

The policy is planning input only. It does not start a scheduler, acquire a lock, fetch a source, mutate a cache, create accepted state, create a generation, replace a pointer, or publish M3U/XMLTV output.

## Aliases

`data/rules/aliases.json` — optional. Maps known alternate provider names to one canonical name (exact match only — see [Channel IDs](../Concepts/Channel-IDs.md)).

| Field                 | Required | Notes                                         |
| --------------------- | -------- | --------------------------------------------- |
| `aliases`             | Yes      | Array, can be empty.                          |
| `aliases[].canonical` | Yes      | The preferred name this entry resolves to.    |
| `aliases[].aliases`   | Yes      | Array of known alternate names, at least one. |

Full schema: [`schemas/aliases.schema.json`](../../../schemas/aliases.schema.json).

## Numbering blocks

`data/lineup/numbering_blocks.json` — optional. A channel is numbered only if its source `group` exactly (case-insensitively) matches a block's `category`.

| Field                             | Required | Notes                                           |
| --------------------------------- | -------- | ----------------------------------------------- |
| `blocks`                          | Yes      | Array, can be empty.                            |
| `blocks[].start` / `blocks[].end` | Yes      | Inclusive channel number range.                 |
| `blocks[].category`               | Yes      | Must exactly match a source's `group` to apply. |

Full schema: [`schemas/numbering_blocks.schema.json`](../../../schemas/numbering_blocks.schema.json).

## Local channels

`data/lineup/locals.json` — optional, informational local-station data referenced in build reports.

| Field                                                            | Required | Notes                   |
| ---------------------------------------------------------------- | -------- | ----------------------- |
| `locals`                                                         | Yes      | Array, can be empty.    |
| `locals[].number`, `.station`, `.network`, `.market`, `.display` | Yes      | All required per entry. |

Full schema: [`schemas/locals.schema.json`](../../../schemas/locals.schema.json).

## A note on secrets in display fields

`provider`, `sources[].name`, and similar display-only fields are **not** redacted from build reports — only `url` fields are. Never put a token, account ID, or other secret-shaped value in a display field. See [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#how-to-avoid-exposing-credentials).
