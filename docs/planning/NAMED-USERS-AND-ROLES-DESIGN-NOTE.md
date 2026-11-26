# Design note: named users and roles (issue 150, next step)

Status: design note only. No code, no tests, no schema change. Nothing was run.

This note follows the first sign-in release (one shared admin password). It proposes named users and roles. The owner decides first; code comes later, in the slices in section 11. The frozen contracts (guide-id contract v1.0, the `guide: null` marker, no dropped channels) are not touched. Sign-in never changes guide, M3U or XMLTV bytes.

"Exists" below means I read it in the code. "Proposal" means it is not built.

## What exists today (read in the code)

- One file, `admin-password.json`, in the config folder. It holds `Schema`, `Algorithm` (PBKDF2-SHA256), `Iterations` (600000), `Salt`, `Hash`. It is written with the engine's temp-file-then-replace writer, then locked to the current account and administrators (Windows) or owner read/write (other systems).
- Sessions are in memory only. The session record already has a `UserId`, always `admin`. Idle limit 30 minutes, maximum 12 hours. The store keeps only a hash of the token.
- First run: a one-time setup code printed on the console, valid 15 minutes, works once. The start guard refuses a non-loopback address with no password file, and always refuses a damaged one.
- Slow-down: 5 wrong tries in a row from one address start a doubling wait up to 15 minutes. A global counter (50 wrong tries) adds a short wait (up to 30 seconds) for everyone. Quiet for 15 minutes resets the counts. Memory only. The address is the peer address, never a header.
- Change password: the signed-in person types the current and new password. Other sessions end.
- Reset: `Reset-ChannelForgeAdminPassword -ConfigRoot <folder>`, administrator window, removes only `admin-password.json`. The next start prints a new setup code.
- Browser checks: the Host header must be in the allowed list; Origin (or Referer) must match; state-changing requests must be `application/json`; no preflight.
- There is no audit trail for sign-in. The reset returns a text line with a time but does not store it. The only audit store I found is the guided-setup acceptance audit.
- There is no `/api/settings` route yet (the appearance note is still a note).

## 1. Who the users are and the smallest role set

A home setup: the owner, family, friends, and sometimes a helper who fixes a lineup. Most people only want to look. Few should change things. One or two should manage people.

| Role      | Can do                                                                               | Built when |
| --------- | ------------------------------------------------------------------------------------ | ---------- |
| Admin     | Everything. Add, disable, delete users. Reset passwords. Server settings.            | First      |
| Editor    | Change lineup and sources. Cannot manage users or server settings.                   | First      |
| Viewer    | Look at lineup, guide, status, timeline. Cannot change anything.                     | First      |
| Requester | Viewer plus ask for a channel (issue 51). Cannot approve. Needs the request feature. | Later      |

Each user has exactly one role. No custom roles, no groups. A new role later is a new word in a list, not a new system.

The request-tracking note calls the top role "Owner". This note calls it "Admin" because the code and the user guide already say admin. When request tracking is built, "Owner" there means Admin here.

### What each route needs (every route I found)

A route that changes nothing is "read". Anything with POST is checked against the role. Routes not listed are unknown and are refused for everyone (fail closed).

| Route                                                                        | Method    | What it does                             | Role needed               |
| ---------------------------------------------------------------------------- | --------- | ---------------------------------------- | ------------------------- |
| `/health` (no session)                                                       | GET       | Data-free "ok"                           | None                      |
| `/`, `/index.html`, `/assets/...`                                            | GET       | Page shell and program files             | None (shows sign-in form) |
| `/first-run`, `/first-run/submit`                                            | GET, POST | First-time setup, setup state only       | None, needs setup code    |
| `/api/auth/sign-in`                                                          | POST      | Sign in                                  | None                      |
| `/api/auth/sign-out`, `/api/auth/session`                                    | POST, GET | Sign out, who am I                       | Any signed-in             |
| `/api/auth/change-password`                                                  | POST      | Change own password                      | Any signed-in (own only)  |
| `/health` (signed in), `/api/status`                                         | GET       | Status                                   | Viewer                    |
| `/api/lineup/channels`                                                       | GET       | Saved channel lineup                     | Viewer                    |
| `/api/one-guide/live-now`, `/starting-soon`, `/category/{id}`, `/items/{id}` | GET       | Guide views                              | Viewer                    |
| `/api/guided-setup/proposal`                                                 | POST      | Builds a proposal from the import folder | Editor                    |
| `/api/guided-setup/accept`                                                   | POST      | Saves the lineup                         | Editor                    |
| `/api/sources/refresh`                                                       | POST      | Fetches sources                          | Editor                    |
| `/api/sources/remove`                                                        | POST      | Removes a source                         | Editor                    |
| Planned: `/api/settings` (server)                                            | GET, PUT  | Server settings                          | GET Viewer, PUT Admin     |
| Planned: `/api/users/...`, `/api/audit`                                      | various   | Manage users, read audit                 | Admin                     |

Proposal is POST but saves nothing. I put it with Editor because it reads the server import folder. A Viewer has no reason to run it.

### What each page needs

The pages are the entries in the navigation (`gui/src/app/navigation.ts`) plus the change-password page. I did not trace which route each page calls, so the page list is by name and the route table above is the authority.

| Page                                                                                                                  | Role          |
| --------------------------------------------------------------------------------------------------------------------- | ------------- |
| Workbench, Live Now, Wrestling, Channel lineup, Timeline, Learn, State gallery                                        | Viewer        |
| Guided Setup (and the Playlist, Guide, Lineup, Saved lineup, Automatic updates entries, listed but not yet available) | Editor        |
| Account (change own password)                                                                                         | Any signed-in |
| Planned: Users, Audit, Server settings                                                                                | Admin         |

The page hides what a role cannot use. Hiding is only a courtesy. The server check on every route is the real wall.

Owner decision 1: which roles in the first build, and may a Viewer run the proposal? Options: (a) Admin, Editor, Viewer now; Requester later. (b) Admin and Viewer only. (c) Admin only (named users, one power level). Recommendation: (a). Editors are the "helper" case, and Viewer protects the lineup from family members. Requester waits for issue 51.

## 2. The shared password becomes the first named user

Upgrade, no re-setup:

1. On start, if `users.json` does not exist and `admin-password.json` is valid, write `users.json` with one user: name `admin`, role Admin, and the same `Salt`, `Hash`, `Iterations` (copied, never re-asked, never recomputed). The password does not change.
2. Check the new file reads back. Only then rename the old file to `admin-password.json.migrated`. If anything fails, leave the old file and keep running as today. The old file is never deleted by the upgrade, so a downgrade or a rollback just renames it back.
3. A damaged `admin-password.json` still refuses to start, as today. A damaged `users.json` also refuses to start and is never touched.
4. A brand-new server (neither file) works as today: console setup code, first-run page. The person who types the code becomes the first Admin. They choose their user name on that page and the password, as today.

The username `admin` is a plain default. The owner may rename it later. The session `UserId` becomes the user's id (see section 3), so nothing in the session shape changes.

Owner decision 2: keep `admin` as the first user name? Options: (a) yes, rename later in the Users page. (b) ask for a name during the upgrade. Recommendation: (a). The upgrade must not need anyone to type anything.

## 3. The user record and where it is stored

One file, `users.json`, in the same config folder as `admin-password.json`. Same writer (temp file then replace, ADR-0009), same file protection, same backup rules.

Per user:

| Field                              | Meaning                                                                                             |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- |
| `Id`                               | Random id, never reused. The session and audit trail use it, not the name.                          |
| `Name`                             | Sign-in name. Unique, case-insensitive, letters, digits, dot, dash, underscore. 3 to 32 characters. |
| `Role`                             | `Admin`, `Editor`, `Viewer`.                                                                        |
| `Disabled`                         | true or false.                                                                                      |
| `MustChange`                       | true after an admin reset. The person must pick a new password first.                               |
| password record                    | The same `Schema`, `Algorithm`, `Iterations`, `Salt`, `Hash` as today. No password is stored, ever. |
| `CreatedUtc`, `PasswordChangedUtc` | Times, UTC.                                                                                         |

Reuse: `New-ChannelForgeAdminPasswordRecord`, `Test-ChannelForgeAdminPassword`, `Test-ChannelForgeAdminPasswordRule`, `Write-ChannelForgeSourceEnrollmentAtomicBytes`, the file-protection code in `Write-ChannelForgeAdminPasswordFile`. The slice that writes this must search `src\ChannelForge` first and extend those, not copy them.

A backup of the config folder holds every user's hash. The guide must say so (it already says so for one hash).

Sign-in changes from "password only" to "name and password". The failure message stays the same for a wrong name and a wrong password. To keep the time the same, an unknown name still runs one hash check against a dummy record.

Owner decision 3: one file for all users, or one file per user? Options: (a) one `users.json`. (b) one file per user. Recommendation: (a). A home has a handful of people. One file is one atomic write and one thing to back up. If two admins save at once, the server serializes writes (it is a single process).

## 4. Add, disable, delete, reset

All by an Admin, in a Users page. All need the Admin's own current password typed again for add, delete and reset (a stolen open browser must not be enough).

- Add: Admin types name, role, and a starting password (or presses "make one"). The server shows a made password once. The user is created with `MustChange` true. The Admin gives the password to the person by hand (spoken, written, message).
- Disable: user cannot sign in. Their sessions are cut on their next request. Their record, name and audit history stay. Reversible.
- Delete: removes the record. Audit entries keep the old `Id` and name text, so history stays readable. Not reversible. Needs a typed confirmation.
- Reset someone else's password (no email): the Admin presses "Reset password". The server makes a one-time temporary password, shows it once to the Admin, stores only its hash, and sets `MustChange`. On the person's next sign-in the only thing they can do is choose a new password (everything else answers "change your password first"). The old password stops working at the reset, not at the next sign-in.
- Last admin: the server refuses to delete, disable or demote the last enabled Admin. The message says why. Changing your own role is allowed only if another enabled Admin remains.
- Recovery path stays: the console `Reset-ChannelForgeAdminPassword` command. It must be rebuilt in its slice to match `users.json`. Proposal: it removes `users.json` entirely and returns the server to setup state (same promise as today: only the sign-in data goes; lineups, accepted state, settings and outputs are not touched). Setup then creates the first Admin again. Users are lost, but the lineup is safe. A softer option is in question 4.

Owner decision 4: what does the console recovery command do once there are many users? Options: (a) remove all sign-in data, go back to setup (simple, same as today, users must be re-added). (b) reset only one named Admin to a temporary password and keep everyone else. (c) both, with (b) the default and (a) behind a switch. Recommendation: (b) as the default and (a) available. Reason: a forgotten Admin password should not cost the family their accounts. It is also a small step on top of the Admin reset. If this proves too big, ship (a) first, as it equals today.

## 5. Sessions

Still memory only (owner decision). Idle 30 minutes, maximum 12 hours, as today.

- The session keeps `UserId`. The role and disabled flag are read from `users.json` on every request, not copied into the session. A role change or disable therefore takes effect on the next request. A delete also does. A restart signs everyone out, as today.
- A user changing their own password ends their other sessions (exists today for one user; extends to "that user's other sessions").
- An admin password reset or a disable ends all of that user's sessions at once.
- Cost: reading a small file per request. The server can keep the parsed file in memory and re-read it only after its own writes. Proposal.

No decision needed beyond the standing one.

## 6. Email recovery

Not built. Recommendation: defer, probably forever for a home server.

Real costs:

- A mail server setting (host, port, account) the owner must find and type. Many home internet lines block outgoing mail on port 25. Many mail providers need an app password.
- A secret to store: the mail account password. It would need its own protected store (the existing one is hash-only; a mail password must be recoverable, so it needs the Windows protected-file approach in REMOTE-CREDENTIAL-ENROLLMENT-DESIGN.md, which does not work in Docker).
- Abuse: a "forgot password" page that sends mail lets a stranger spam people and probe which addresses exist. It needs its own rate limits and uniform answers.
- Email addresses are personal data the product does not hold today.
- A home server may be offline, or its mail may land in spam, so the person is locked out exactly when it matters.

No-email alternatives (all built from this note):

1. Another Admin resets it (section 4). This covers a family of two admins.
2. The console command on the server machine.
3. Later, only if asked: a one-time reset link the Admin copies and sends by hand.

Owner decision 5: build email recovery? Options: (a) no, defer. (b) yes. Recommendation: (a). Two admins plus the console command cover a home. Revisit only if someone runs this for many people.

## 7. Wrong-password slow-down with many users

Already decided and built for one address: 5 wrong tries, doubling to a cap of 15 minutes, no permanent lock, same message. How it extends:

- The count is kept per (address) and per (user name). A wait applies when either the address or the name has too many wrong tries.
- To keep one person from locking out another, the per-name wait is short and capped much lower than 15 minutes (proposal: 60 seconds), and a correct password from a different address is not blocked while only the per-name counter is high and the address is clean. Rule in plain words: a stranger can slow down guesses against Alice, but Alice, typing the right password, still gets in after at most one minute. If a stranger instead hammers from one address, that address is slowed up to 15 minutes, and Alice (another address) is not affected.
- The global counter stays (50 tries, up to 30 seconds), so many addresses together cannot guess forever.
- Wrong tries against names that do not exist count against the address, not against a stored name. This keeps the table from growing and leaks nothing.
- Memory only, forgotten after 15 quiet minutes, bounded size (as today).
- Behind a reverse proxy every request seems to come from the proxy address (section 10). Then the per-address count is shared by everyone, so one person's typos could slow everyone. This is the one real weakness. Proposal: a setting naming the proxy address that may report the real address in `X-Forwarded-For`; until it is set, the per-name rule above is what protects people from each other.

Owner decision 6: confirm the per-name cap. Options: (a) 60 seconds. (b) 15 minutes, same as address. (c) none. Recommendation: (a). A long per-name lock is a lock-out tool for a stranger.

## 8. Per-user settings

Per the appearance note (SERVER-SETTINGS-NOTE.md): a server-wide value exists, and a user value may override it.

- The `users.json` record has an optional `Settings` object: today only `appearance` (`light`, `dark`, `system`). Unknown names are refused. No `Settings` means "use the server value".
- A user changes only their own. `GET`/`PUT /api/settings/me`, role Viewer or higher. The server-wide `/api/settings` PUT stays Admin only.
- Order of use: user value, else server value, else `system`.
- Written with the same durable writer. A user with no saved setting costs no space.
- Browser migration follows the appearance note (server wins, local value stays as cache).

Owner decision 7: should a per-user setting be stored in `users.json` or in its own file? Options: (a) inside `users.json`. (b) separate `user-settings.json`. Recommendation: (b). Appearance has nothing to do with sign-in data. A bad settings write must never risk the file that holds every hash. Corrupt settings fall back to defaults and are kept aside, as the settings note already says.

## 9. Audit trail

Today there is none for sign-in. Proposal: an append-only file, `audit.jsonl`, in the state area (ADR-0009 "audit history"), one line per event.

Recorded (who, what, when): time (UTC); actor user id and name; event; target user id and name where there is one; source address; result (ok or refused).

Events: sign-in ok; sign-in failed (name text if it matches a real user, else "unknown"); sign-out; password changed (own); user added, disabled, enabled, deleted, role changed; password reset by an admin; wait started (too many tries); first-run setup done; console reset (written when the server next starts, because the command runs while the server may be off).

Never recorded: passwords (typed, temporary or hashed), setup codes, tokens, cookies, request bodies or headers, or the name text a stranger typed that is not a real user.

Shown: an Admin-only Audit page, newest first, with the last 200 events and a filter by user. No export in the first build.

Kept: 12 months, or at most 5,000 lines, whichever is smaller. Older lines are dropped when the file is next written. The file is included in backups. This is a proposal, not an existing retention rule.

Owner decision 8: keep length. Options: (a) 12 months or 5,000 lines. (b) forever. (c) 30 days. Recommendation: (a). A home needs recent history, not a growing file. The audit file must be small enough that it never slows startup.

## 10. HTTPS

The standing decision: ChannelForge does not do HTTPS itself. The owner runs a reverse proxy with HTTPS in front and keeps ChannelForge sign-in on behind it. A warning (not a block) appears on plain HTTP. This note confirms that and builds nothing for it.

What a reverse proxy changes, by reading the code (not run):

- Host check: the proxy must forward the name people type in the browser as the Host header, and that name must be in `-AllowedHost`. Many proxies rewrite Host to an inner address by default; then every request is refused with a uniform "not allowed" message. Needs one line in the guide.
- Origin check: the server compares the browser's Origin to `http://<host>`, using the scheme the listener sees. Behind an HTTPS proxy the browser's Origin is `https://<host>`. By my reading every sign-in and change would be refused. This is likely the first thing that breaks. A fix needs a "trusted proxy" setting, not a header trusted blindly. I could not test this.
- Cookie: the `Secure` flag is set when the server's own listener is HTTPS. Behind a proxy the listener is HTTP, so the cookie has no `Secure` flag. It works, but a plain-HTTP visit would send it. Same trusted-proxy setting would fix it.
- Source address: the proxy address, not the person (see section 7).
- The HTTP warning on the first-run page uses the Host name and the scheme the server sees. It may warn when the person really is on HTTPS.

All four need one setting: "the address of the proxy I trust, and what scheme it speaks". No setting, no trust (as today).

Owner decision 9: build the trusted-proxy setting? Options: (a) yes, as a later slice, off by default. (b) no, tell people to use Docker/Windows ports directly on a trusted network. (c) first test the proxy case and then decide. Recommendation: (c) then (a). First reproduce the Origin failure behind a real proxy so that the fix is small and proven. Named users do not need it to start.

## 11. Slice plan

Each slice is small, ships alone, and leaves the one-password behavior working. Sizes are changed lines for code plus tests; all are guesses.

| Slice | What                                                                                                          | Size | What it protects                                                          | Tests a user would notice                                                                                                      | Owner's hands needed       |
| ----- | ------------------------------------------------------------------------------------------------------------- | ---- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------- |
| 1     | `users.json` store: read, write, one user, upgrade from `admin-password.json`, start guard and reset read it. | ~250 | The existing password keeps working. Nobody is locked out by the upgrade. | Upgrade keeps the same password. A damaged file refuses to start and is untouched. Old file kept as `.migrated`.               | Yes: upgrade a real config |
| 2     | Sign-in by name, uniform failure, dummy hash for unknown name. Session `UserId` is the user id.               | ~150 | No user-name guessing by message or timing.                               | Wrong name and wrong password give the same message. Right name and password sign in.                                          | No                         |
| 3     | Role check on every route, fail closed for unknown routes. Server table from section 1.                       | ~250 | A Viewer cannot change anything.                                          | Per route and role: Viewer refused on each POST, Editor allowed. An unknown route is refused.                                  | No                         |
| 4     | Last-admin rule and the Users API: add, disable, delete, reset to temporary password, `MustChange`.           | ~300 | Nobody loses the last admin. A reset password is one-time.                | Last admin cannot be removed or demoted. Reset password works once and forces a change. Disable ends the session next request. | No                         |
| 5     | Users and Audit pages in the browser, role-aware navigation.                                                  | ~250 | A beginner can manage people without files.                               | A Viewer sees no Users page. An Admin can add and disable.                                                                     | Yes: look at it            |
| 6     | Audit trail: record, show, trim.                                                                              | ~200 | Who did what, with no secrets.                                            | An event shows. A password, code or token never appears in the file after a full run.                                          | No                         |
| 7     | Per-user wrong-try wait.                                                                                      | ~120 | One person cannot lock out another.                                       | Stranger hammering Alice's name: Alice gets in within the cap. One address hammering is slowed.                                | No                         |
| 8     | Per-user settings (appearance override).                                                                      | ~150 | Appearance without touching sign-in data.                                 | A user override wins. No override uses the server value.                                                                       | Yes: look at it            |
| 9     | Console reset updated for named users (per question 4).                                                       | ~100 | Recovery stays on the machine.                                            | Reset leaves lineups and accepted state alone. Chosen admin gets a temporary password.                                         | Yes: run on a real server  |
| 10    | Guide and docs: Server-Sign-In.md and the ADR amendment updated for named users.                              | docs | The guide stays true.                                                     | Docs checks pass.                                                                                                              | No                         |
| Later | Trusted proxy setting; Requester role (with issue 51).                                                        | -    | -                                                                         | -                                                                                                                              | Yes                        |

Slices 1 to 4 are the safe core: usable from a script or the existing page before any new screen exists. Total is above 300 lines, which is why it is ten slices. Each slice is its own change.

Standing checks for every slice: the portable bundle stays loopback-only with no sign-in; guide bytes and guide-id contract v1.0 are unchanged; no password, code, hash or token in any log, report or error; a wrong route fails closed.

## 12. Owner questions

Answer with a number and a letter. My recommendation is first in each list.

1. Which roles in the first build?
   - a. Admin, Editor, Viewer; Requester later. A Viewer cannot run the proposal. (Recommended: covers a family and a helper.)
   - b. Admin and Viewer only.
   - c. Admin only.
2. The first user name after the upgrade?
   - a. `admin`, can be renamed later. (Recommended: no typing needed at upgrade.)
   - b. Ask for a name during the upgrade.
3. Where do user records live?
   - a. One `users.json`. (Recommended: one atomic write and one backup.)
   - b. One file per user.
4. What does the console recovery command do with many users?
   - a. Remove all sign-in data, return to setup, users must be re-added. (Same as today.)
   - b. Reset only one named Admin to a temporary password, keep everyone. (Recommended as the default, with a)
   - c. Both, b by default, a behind a switch.
5. Build email recovery?
   - a. No, defer. (Recommended: costs and abuse; two admins plus the console cover a home.)
   - b. Yes.
6. Per-name wrong-try cap?
   - a. 60 seconds. (Recommended: a stranger cannot lock someone out for long.)
   - b. 15 minutes.
   - c. None.
7. Where do per-user settings live?
   - a. Inside `users.json`.
   - b. Their own `user-settings.json`. (Recommended: a bad settings write never risks the password data.)
8. How long is the audit trail kept?
   - a. 12 months or 5,000 lines, whichever is smaller. (Recommended.)
   - b. Forever.
   - c. 30 days.
9. Trusted-proxy setting for HTTPS in front?
   - a. Build later, off by default.
   - b. Do not build; use a trusted network.
   - c. First reproduce the Origin failure behind a real proxy, then build a. (Recommended: the fix is small once proven.)
10. Should an Admin need to retype their own password to add, delete or reset a user?
    - a. Yes. (Recommended: an open browser left on a desk should not be enough.)
    - b. No.
11. Start with slices 1 to 4 (store, sign-in by name, role checks, last-admin and Users API) before any screen?
    - a. Yes. (Recommended: the safety work comes before the screens.)
    - b. Build the screens in the same slices.

## Not verified

- Nothing was run. No browser, no server, no proxy.
- I did not trace which route each browser page calls; the route table comes from the server code.
- The Origin and cookie behavior behind a reverse proxy is by reading code only.
- The audit retention, the per-name cap, the user-name rules and every size in section 11 are proposals.
- I did not check whether Docker's volume permissions handle `users.json` protection the way they handle `admin-password.json`.
- I did not read the Docker or Windows start-up scripts beyond the server start script's sign-in flag.
