# ADR-0016 amendment: server authentication boundary

## Status

Accepted. This amendment does not change the accepted ADR-0016 architecture decision. It was updated on Nov 27, 2026 for named users and roles (issue 150, slices 1 to 4b and 6 to 10). The first version of this amendment described one shared admin password; this text replaces that description. The sign-in is built in the server. Docker and Windows server packaging are not built.

## Decision

For Docker and Windows server deployments, access is by named users. Each user has one role: Admin, Editor or Viewer. The first user is created in one of two ways. On a new server, the person who types the one-time setup code from the server console on the first-run page becomes the first Admin, named `admin`. On a server that used the earlier shared password, the program upgrades by itself (see Users file). A reverse-proxy-delegated sign-in is not built.

### Roles

Every route has one row in a single role table in the server (`Get-ChannelForgeWebRouteRoleTable`). A route with no row is refused for everyone. The role and the disabled flag are read from the users file on every request, so a change takes effect on the next request.

| Role   | Can do                                                                                                                      |
| ------ | --------------------------------------------------------------------------------------------------------------------------- |
| Viewer | Look at status, the saved lineup and the guide views. Read server settings. Read and change their own settings.             |
| Editor | Everything a Viewer can, plus Guided Setup (proposal and accept) and source refresh and remove.                             |
| Admin  | Everything an Editor can, plus change server settings, manage users (`/api/users`) and read the audit trail (`/api/audit`). |

Each user has exactly one role. There are no custom roles or groups.

### Users file

Users are kept in `users.json` in the config area of the data folder. It is written with the engine's temp-file-then-replace writer and locked to the current account and administrators. Per user it holds an id (random, never reused), a name (3 to 32 letters, digits, dot, dash or underscore, unique without regard to case), a role, a disabled flag, a must-change flag, the password record (algorithm, iterations, salt, hash) and creation and password-change times. It never holds a password. Hashes and session tokens never appear in logs, reports, Doctor output, errors, API responses, the repo or the image. The Users API never returns the password record.

A damaged `users.json` makes the server refuse to start and the file is not touched.

Upgrade from the shared password: on start, when `users.json` does not exist and `admin-password.json` is valid, the program writes `users.json` with one Admin named `admin` that carries the same salt, hash and iterations, so the same password keeps working. After it reads the new file back, it renames the old file to `admin-password.json.migrated`. If anything fails, the old file stays. When both files exist, `users.json` is used.

The password must be at least 12 characters and must not match a small built-in list of very common passwords.

### Sessions

Sessions exist in memory only. A server restart signs everyone out; session state is never written to disk. The session carries the user's id, not the name. A disabled or deleted user, or a session older than that user's last password change, is signed out on the next request. Changing your own password, or an Admin reset of your password, ends your other sessions.

### Managing users

Only an Admin can add, change, disable or delete users, reset a password, or read the audit trail. The Users API is `GET` and `POST /api/users`, `PUT` and `DELETE /api/users/{id}` and `POST /api/users/{id}/reset-password`. For add, delete and reset, the Admin types their own password again in the request. A wrong try counts as a wrong sign-in try. The server refuses to delete, disable or demote the last enabled Admin.

An Admin chooses the starting or temporary password and gives it to the person by hand. The account is marked "must change". The server enforces it: a person with that mark may only choose a new password, read the session state, or sign out. Every other `/api/` request is refused with a plain message and the code `must-change-password`. The page shell and its program files still load, so the Change password form can show. The sign-in and session answers carry `MustChange` so the page can show that step first. Choosing a new password clears the mark; the new password must differ from the temporary one. The server reads the current record on every request, so an Admin reset takes effect on a live session at once. These refusals are not written to the audit log one by one. The browser sign-in page sends no user name yet, so this path works in the browser only while the server has one enabled user.

### Wrong tries

After five wrong sign-ins from one address, that address waits, and the wait doubles to a 15-minute cap. After 50 wrong tries from all addresses together, everyone waits up to 30 seconds. Each user name also has its own count: after five wrong tries for one name, that name waits 60 seconds from any address, and even the right password is refused until the wait ends. A name that does not exist is counted the same way. The counts live in memory only and a quiet 15 minutes clears them. There is no permanent lock-out. The failure message is uniform, and an unknown name still gets one password check so timing does not show which names exist. The address is the peer address, never a header.

### Audit trail

When sign-in is on, the server appends one line per event to `audit.jsonl` in the config area. It records the time (UTC), who, what, to whom, from which address, and whether it worked: sign-in (right and wrong), sign-out, password changes, user add, change, delete and reset, refused role checks, wrong Admin password on a user change, last-Admin refusals, settings changes, first-run Admin creation, the upgrade from the shared password and the console reset. It never stores a password, setup code, token, cookie or request body, and a name that matches no user is stored as `unknown`. The file keeps events from the last 12 months and at most the newest 5,000 lines. It is trimmed after every 100 appended events in one server run. A failed write gives one warning and the server carries on. Only an Admin can read it, through `GET /api/audit`, newest first.

### Per-user settings

Each user can have their own appearance (`light`, `dark` or `system`). It is stored in `user-settings.json`, a separate file, so a settings problem can never touch the file that holds the hashes. The order of use is the user's value, then the server-wide value, then `system`. A user changes only their own through `/api/settings/me`; the user comes from the session, never from the request. An unreadable file means defaults and is moved aside, never deleted, at the next save.

### Recovery

A forgotten password is recovered in one of two ways. Another Admin resets it through the Users API. Or, on the server machine only, `Reset-ChannelForgeAdminPassword` in an administrator window:

- With `-Name` (or with the only Admin), it sets one Admin to a new random temporary password, shown once on the console and stored nowhere. That Admin is enabled again if disabled, is marked "must change", and loses all older sessions. Every other user is kept.
- With `-RemoveAllSignInData`, it removes `users.json`, `admin-password.json` and `admin-password.json.migrated`, so the next start is in setup state with a new setup code. It touches no other file.

Neither way touches lineups, accepted state, settings or outputs. There is no email recovery.

### Unchanged rules

In setup state a non-loopback server serves only the first-run page and a data-free health check. First-run requires a one-time setup code shown on the server console.

The session cookie is HttpOnly and SameSite=Strict, and Secure when HTTPS is used. Origin is checked on every state-changing route.

Plain HTTP on a network produces a warning on the first-run and sign-in screens; it does not block use. HTTPS through a reverse proxy is recommended.

The portable Windows bundle stays loopback-only with no sign-in.

The browser never sends a local file path. File selection and access remain server-side; imports use the server's configured import folder.

## Relationship to ADR-0014

ADR-0014 is unchanged. It continues to govern outbound HTTPS acquisition transport and trust. This amendment concerns inbound browser-to-server access and does not weaken or replace that transport contract.

## Relationship to other contracts

Sign-in and roles never change guide, M3U or XMLTV bytes. Guide-id contract v1.0, the `guide: null` marker and the rule that no channel is dropped are not touched.

## Consequences

- Each person has their own name and password. What they can do depends on their role.
- A server restart signs out all sessions. A Docker password reset must be performed on the host against the same data volume.
- Network HTTP remains usable but exposes credentials to network observers; HTTPS through a reverse proxy is recommended.
- Backups include every user's hash and the audit trail. Protect backups like the data volume.
- The portable Windows bundle keeps its current loopback-only, no-password behavior.

## Not built

- The Users and Audit screens in the browser. Today users are managed through the API.
- A trusted-proxy setting. Behind an HTTPS reverse proxy the Origin check, the cookie `Secure` flag and the per-address count are by code reading likely to misbehave; this was not tested.
- The Requester role (waits for request tracking, issue 51).
- Forcing a user to change a temporary password at first sign-in.
- Choosing the first user name on the first-run page. It is always `admin`; an Admin can rename it through the Users API.
- HTTPS inside ChannelForge, email recovery, and Docker or Windows server packaging.

## Not decided

- Sessions kept across a restart; the exact common-password list.
- Final Docker image, import-folder path, and environment-setting names.
