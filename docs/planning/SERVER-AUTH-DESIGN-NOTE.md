# Design note: sign-in for the server versions (issue 150)

This is a design note. It adds no code, no tests, no schema and no contract change. It comes from reading the files listed in section 8. Nothing was run. Anything not read is marked as a proposal or listed under "Not verified". The frozen contracts (guide-id contract v1.0, the `guide: null` marker, no dropped channels) are not touched.

## 1. What problem this solves and who it protects

Today the ChannelForge server listens on loopback (127.0.0.1) only and has no sign-in (ADR-0016, CLIENT-SERVER-DESIGN-NOTE.md). Only programs on the same computer can reach it. That is safe without a password.

The owner wants a Docker install and a Windows server install. Those must listen on a network address so other devices can use them. Once that happens, anyone who can reach the port can reach ChannelForge. ChannelForge can accept lineups, change sources and hold references to provider logins. Sign-in stops the wrong person from doing that.

Who it protects, and from whom:

- A family member on the home network. They can reach the port, but they must not change the lineup by accident or on purpose.
- A visitor on the Wi-Fi. They are on the network but are not a user. They must see a sign-in page and nothing else.
- A port forwarded by mistake. The router exposes the server to the internet. Sign-in is then the last wall. This is the worst case, so the design must hold up here.

What sign-in protects: the lineup and accepted state, the settings, and anything that points to a provider account (ADR-0002: provider credentials stay out of Git and out of readable places).

The portable Windows bundle stays loopback-only with no sign-in. It does not change.

## 2. Options

### (a) One shared admin password, set at first start

One password for the whole server. Whoever knows it is the admin.

- Cost: small. One hash file, one login route, one session store.
- Risk: no record of who did what. Everyone who knows the password has full power. Sharing it with a family member means sharing admin.
- Suits: one household, one person who manages the lineup.

### (b) Named users with one role each (admin, viewer)

Each person has a name and a password. Each has one role.

- Cost: medium. Account storage, add and remove user, change and reset password per user, a permission check on every route, more screens and tests.
- Risk: more code is more bugs. A bad permission check gives a viewer admin power. Password reset for many users is a support burden.
- Suits: a household where some people only look, or where request tracking (REQUEST-TRACKING-MULTI-USER-NOTE.md) needs to know who asked.

### (c) Sign-in delegated to a reverse proxy the user already runs

ChannelForge trusts a proxy (for example one that already does sign-in for other apps) and does no sign-in itself.

- Cost: small in code, but needs a trust setting ("which proxy address may tell me who the user is").
- Risk: if the port is reachable around the proxy, there is no protection at all. A wrong trust setting lets anyone fake the "who" header. A beginner is unlikely to set this up right.
- Suits: users who already run a proxy and know how.

### Recommendation for the first server release: (a)

Use one shared admin password, built so the session already carries a user id (always `admin` at first). Reasons:

- It is the smallest model that is safe. It closes the three cases in section 1.
- It matches the recommendation already in CLIENT-SERVER-DESIGN-NOTE.md ("A then B").
- The session carrying a user id means (b) can be added later without changing the API shape. Viewer role and request tracking follow then.
- It does not become an identity system. No email, no password recovery by mail, no external provider, no single sign-on.

Option (c) is NOT built. A user who runs a proxy can still put it in front of ChannelForge for HTTPS. ChannelForge keeps its own sign-in behind it. That is two locks on one door, and it is safe.

## 3. How the secret is created, stored, changed and reset

The secret is the admin password. (This is separate from provider credentials, which REMOTE-CREDENTIAL-ENROLLMENT-DESIGN.md handles with a Windows-only protected file. That method is tied to a Windows user and does not fit a password check or a Docker host, so it is not reused here. This is a proposal, not a verified fact about code.)

### Created

- First start in server mode has no admin password, so the server starts in "setup" state and refuses all routes except the first-run page and a data-free health check.
- The server prints a one-time setup code on its local console and log channel the admin can reach (Docker: container logs; Windows server: the console or a file only the service account and admins can read). The code is random, long enough to resist guessing, valid for a short time, and works once.
- The admin opens the first-run page, types the setup code, then chooses a password. The server checks length (proposal: at least 12 characters) and refuses a blank or very common one.
- The setup code is never stored in readable form after use. It is not written to reports or Doctor output. Because it is printed once on the console by design, the note says so plainly in the first-run screen.

### Stored

- Only a salted, slow hash is stored, never the password. Proposal: PBKDF2 with SHA-256 and a high iteration count, because it is built into .NET and needs no new dependency. Argon2 would add a dependency, so it is not chosen.
- The hash file lives in the config area of the data folder (Docker `/data`; Windows server `%ProgramData%\ChannelForge`) with tight permissions (service account and admins only). It is written with the same temp-file-then-replace method used for settings (SERVER-SETTINGS-NOTE.md, ADR-0009).
- The hash file is included in a backup. A restored backup keeps the same password. The note must say so, because a backup then holds a hash.
- Session tokens are random and stored only as hashes on the server. Sessions may live in memory (sign-in is lost on restart) in the first release. That is simpler and safe. Proposal.

### Never shown

The password, the setup code, the hash, session tokens, cookies and request headers never appear in:

- reports, logs, Doctor output, error messages or API responses;
- the repo, the Docker image, or an environment variable (environment variables leak into process lists and logs).

Logs may say "sign-in failed" with a time. Nothing else.

### Changed

- Signed-in admin opens Settings, types the current password and the new one. The server checks the current one, writes the new hash, and ends all other sessions.

### Reset (forgotten password)

Reset needs control of the server machine. It is never a web page that works from another device.

- Docker host: stop the container and run a one-shot reset command against the same volume (for example `docker run ... reset-admin-password`). It removes the hash file. The next start returns to setup state and prints a new setup code. The exact command is a proposal.
- Windows server install: run an elevated reset command (administrator only) that does the same. Proposal.
- The reset never touches lineups, accepted state, config or outputs. It only removes the sign-in hash.
- Reset is logged as "admin password reset" with a time, no secret.

## 4. Safe defaults

- Loopback only until the user turns on server mode on purpose. Docker is the one exception by nature (the container must bind all interfaces inside), so there the sign-in rule below is what protects it.
- Refuse to start on a non-loopback address unless sign-in is configured. Setup state counts as configured only in the sense that every route except first-run and health is closed. Proposal: in setup state a non-loopback server serves only the first-run page, and first-run needs the setup code from the console.
- The server says why in plain words when it refuses to start. Example: "ChannelForge will not listen on the network without a password. Run first-time setup or turn off network access."
- Health route returns no data (CLIENT-SERVER-DESIGN-NOTE.md).

### What the first-run screen must say

- Plain words that this is a server others on the network can reach, and what a password protects.
- The setup code came from the server console, and why.
- Pick a strong password. There is no email reset. A reset needs access to the server machine.
- The connection is plain HTTP unless the user puts HTTPS in front. Passwords can be read on the network. Recommend a reverse proxy with HTTPS.
- A warning if the page is being opened from a non-loopback address over HTTP.

### Rate limiting and lock-out, simplest form

- Count failed sign-ins per source address and one global counter.
- After 5 failures in a row, wait before the next try, doubling each time up to a cap (proposal: 15 minutes). A correct password resets the count.
- The global counter stops one attacker using many addresses. Proposal: slow the whole sign-in route, never lock the real admin out for good.
- The failure message is the same for every wrong try. It does not say whether a name or a password was wrong.
- No permanent lock-out. A permanent lock-out lets a visitor lock the admin out.

### Browser session and CSRF, in plain words

- After sign-in the server gives the browser a random token in a cookie. The cookie is `HttpOnly` (page scripts cannot read it), `SameSite=Strict` (other sites cannot send it), and `Secure` when HTTPS is in use.
- The session ends after a fixed time idle and after a longer maximum time. Sign-out ends it on the server. Changing the password ends all others.
- CSRF means another web page tricking the signed-in browser into sending a change. Defense: `SameSite=Strict`, plus the server checks the `Origin` header on every route that changes anything and refuses a mismatch.
- The server also checks the `Host` header against the configured address. This blocks DNS rebinding, where a hostile page points its own name at the server address.
- Same response size and time limits as loopback.

## 5. What changes in the ADR-0016 amendment and the Docker contract note

I did not edit those files. These are the exact statements to add.

### ADR-0016-AMENDMENT-DRAFT.md

- Replace "Authentication model: owner decision needed" in Proposed decision item 3 with: "First server release: one shared admin password. The session carries a user id, always `admin` at first. Named users with roles may follow in a separate ADR. A reverse-proxy-delegated sign-in is not built."
- Add: "The password is stored only as a salted slow hash in the config area of the data folder. The hash and session tokens never appear in logs, reports, Doctor output, errors, API responses, the repo or the image."
- Add: "In setup state a non-loopback server serves only the first-run page and a data-free health check. First-run requires a one-time setup code shown on the server console."
- Add: "A forgotten password is reset only on the server machine. The reset removes the hash and does not touch lineups, accepted state or outputs."
- Add: "Sign-in failures are rate limited with growing delay and no permanent lock-out. The failure message is uniform."
- Add to the safety checks: "Session cookie is HttpOnly and SameSite=Strict, and Secure when HTTPS is used. Origin is checked on every state-changing route."
- Add to Consequences: "Backups include the password hash."
- Add under Context or Decision: "The portable Windows bundle stays loopback-only with no sign-in."

### CLIENT-SERVER-DESIGN-NOTE.md (Docker contract)

- Under "Login design options": record the owner decision once taken (see section 7) and replace "Owner decision needed: login model" accordingly.
- Docker contract, First start: add "With no admin password, the container starts in setup state, serves only the first-run page and health, and prints a one-time setup code to the container log."
- Docker contract: add "No password, setup code or hash is in the image or in an environment variable. The hash lives in `/data` config."
- Docker contract: add "Password reset: stop the container, run the reset command against the same volume, start again."
- Docker contract, Backup: add "`/data` backup contains the password hash. Protect backups like the volume."
- Windows server contract: add the same first-start, storage and reset statements with `%ProgramData%\ChannelForge`, with the hash file readable only by the service account and administrators.
- First-run flow: resolve "Owner decision needed: one-time code or password in a file". Recommendation stays: one-time code.

## 6. What must be built, in slices, smallest first

All of this is proposal. Nothing is built.

| Slice | What                                                                                                  | Tests a user would notice                                                                                                                                |
| ----- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Password hash store: create, verify, remove. One function each. Temp-file-then-replace write.         | A right password is accepted. A wrong password is refused. The file text does not contain the password.                                                  |
| 2     | Start-up guard: non-loopback bind refuses to start without sign-in set up, with a plain message.      | Non-loopback with no password refuses to start and says why. Loopback starts as before.                                                                  |
| 3     | Sign-in route, session cookie, sign-out, and a check on every route except health and first-run.      | No sign-in means no access from another device, route by route. A wrong password is refused with the same message each time.                             |
| 4     | First-run page and setup code.                                                                        | The setup code works once and then not again. A wrong code is refused. The page shows the plain-words text from section 4.                               |
| 5     | Host and Origin checks, `SameSite=Strict`, CSRF on state-changing routes.                             | A change request with a foreign Origin is refused. A request with a wrong Host is refused.                                                               |
| 6     | Rate limit with growing delay.                                                                        | Five wrong tries cause a delay. The right password after the delay works. The admin is not locked out forever.                                           |
| 7     | Change password and reset-on-the-server command.                                                      | After a reset the old password is refused and setup state returns. Lineups and accepted state are unchanged. Other sessions end after a password change. |
| 8     | Docker and Windows server docs and packaging use the above. Doctor output and logs checked for leaks. | No password, code, hash or token appears in logs, reports, Doctor output or errors after a sign-in and a failed sign-in.                                 |

Standing check for every slice: the loopback portable mode is unchanged. It starts with no sign-in and the same behavior as today. Guide output bytes and guide-id contract v1.0 are unchanged.

## 7. Open owner decisions

1. Which option for the first server release?
   - Options: (a) one shared admin password; (b) named users with roles now; (c) reverse proxy sign-in.
   - Full details: sections 2 and 5.
   - Recommendation: (a), with the session carrying a user id so (b) can follow.
2. How is the first password set?
   - Options: one-time setup code on the server console; or a password in a file the admin creates before first start.
   - Details: a code needs console or log access, and Docker logs make that easy. A file avoids printing a secret, but a beginner must create it by hand and may leave it lying around.
   - Recommendation: one-time code (same as CLIENT-SERVER-DESIGN-NOTE.md).
3. Are sessions kept across a server restart?
   - Options: in memory only (sign-in lost on restart); or stored (hashed) on disk.
   - Details: memory is simpler and leaves nothing to leak. Disk means users stay signed in after an update.
   - Recommendation: memory for the first release.
4. Plain HTTP on a network: warn only, or block?
   - Details: blocking is safer but stops home users with no proxy from using the server at all. Warning keeps it usable but passwords cross the network readable.
   - Recommendation: warn on the first-run screen and in the sign-in page, and document a reverse proxy with HTTPS. This is the same as the amendment draft.
5. Minimum password length and strength rule.
   - Options: 8, 12 or 16 characters; with or without a common-password list.
   - Recommendation: 12 characters minimum and a small built-in list of very common passwords refused.
6. Rate limit numbers.
   - Proposal: 5 failures, doubling delay, cap 15 minutes, no permanent lock-out. Needs the owner to confirm the cap.
7. Windows server reset: administrator-only command, or any local user on the machine?
   - Recommendation: administrator-only, because the data folder is protected for the service account and administrators.
8. Does the portable bundle ever get an optional password?
   - Recommendation: no. It stays loopback-only and unchanged.

## 8. Not verified

Read for this note: docs/planning/CLIENT-SERVER-DESIGN-NOTE.md, ADR-0016-AMENDMENT-DRAFT.md, SERVER-SETTINGS-NOTE.md, REQUEST-TRACKING-MULTI-USER-NOTE.md, and the DPAPI part of REMOTE-CREDENTIAL-ENROLLMENT-DESIGN.md; docs/adr/0002-secrets-policy.md, 0014 (first part only) and 0016-web-first-local-ui.md.

Note: the task named docs/decisions for ADR-0002 and ADR-0014. That folder does not exist in this tree. The ADRs are in docs/adr.

Not checked:

- Current server code. Whether the server code exists, its real port, its health route, its host and origin handling, and how it binds today were not read.
- That PBKDF2 (or any hash method) is available and fast enough on the supported PowerShell 7.6 runtime. Slice 1 must prove it.
- That a built-in .NET call can make the one-time code, tokens and salts with a secure random source on the supported runtime.
- How the Windows service and the scheduled task fallback read the data folder permissions.
- Docker behavior: logs, volume permissions and the reset command shape were not tried.
- Whether Doctor output or any existing report could include a header, cookie or secret. No Doctor code was read.
- The second half of ADR-0014 and the other planning notes.
- Whether any existing redaction helper can be reused for sign-in logs. Slice 1 must search `src\ChannelForge` before writing a new one.
- Rate-limit numbers and password rules are proposals, not tested values.
- No browser was run. Cookie and CSRF behavior is described, not observed.
