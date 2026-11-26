# Design note: server-side appearance setting (149 follow-up)

This note started as a design. The appearance setting now exists (see Status). The browser code stores `light`, `dark` or `system` in `localStorage` under the key `channelforge.appearance`, and falls back to `system`; that value is now a cache.

## Problem

The owner wants the appearance setting kept where the program runs. A browser-local value is lost when the user changes browser or device, and is not shared across devices.

## Where it lives

- The engine owns one small settings file in the config area of the data folder (ADR-0009: declarative configuration, one authority). It is not generated output and not accepted state.
- First field: `appearance`, one of `light`, `dark`, `system`. Default `system`. Unknown values are rejected.
- Appearance changes never touch accepted lineups, M3U or XMLTV bytes.

## API

- `GET /api/settings` returns the settings.
- `PUT /api/settings` sets one or more known fields. Unknown names get `invalid-settings`. Body size is small and bounded.
- Authentication rules follow the amendment draft once a non-loopback bind exists.

## How it is saved durably (ADR-0009)

- Write to a temp file in the same folder, flush, then replace the old file in one step. A crash leaves the old file or the new one, never a half file.
- The file carries a schema version so later settings can migrate.
- If the file is unreadable, the engine uses defaults, tells the user, and keeps the bad file aside. It never deletes it.
- The file is included in the backup described in CLIENT-SERVER-DESIGN-NOTE.md.

## Multi-user

Owner decision needed: one shared setting or one per user. Options: shared server-wide; per user once accounts exist. Recommendation: shared now, per-user field later, with a server default that a user value can override.

## Browser-local migration

1. On load the browser asks the server for settings.
2. If the server has no saved appearance and the browser has a valid local value, the browser sends it once to the server.
3. After a successful save, the browser uses the server value. The local value is kept only as a cache to avoid a flash of the wrong theme on load.
4. If the server value and the local value differ, the server wins.
5. If the server is unreachable, the browser uses the local value or `system` and does not block the page.

Owner decision needed: whether the browser should ever delete the local value. Options: keep as cache; delete after migration. Recommendation: keep as cache.

## Not done here

No code, no route, no file format beyond the fields above.

## Status (149 follow-up)

Built:

- Engine: `settings.json` in the server config folder (`-ConfigRoot`), or `state\config` under the install when none is given. Fields: `schema` (1) and `appearance`. Written with the temp-file-then-replace helper. An unreadable file means defaults, a plain message, and the file is renamed aside (`settings.json.bad-<time>`), never deleted.
- API: `GET /api/settings` and `PUT /api/settings`. Only `appearance` is accepted; anything else returns `invalid-settings`. The body is limited to 1 KB. With sign-in on, the same host, origin and session checks as other routes apply.
- Browser: owner choices applied. One shared server-wide setting for now (per-user comes with named users). The browser keeps its value as a cache only and the server value wins. If the server has nothing saved, the browser sends its valid local value once.

Still open: per-user override; including `settings.json` in the backup described in CLIENT-SERVER-DESIGN-NOTE.md.
