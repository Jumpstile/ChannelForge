# Design note: client/server shape, Docker, Windows server, login (150-A)

This is a design note. It adds no code and no tests. It comes from reading ADR-0016, ADR-0009, ADR-0014 and the M3 workflow map. Nothing was run. No frozen contract changes (guide-id contract v1.0, the `guide: null` marker, no dropped channels).

## Owner decisions in force (Nov 23, 2026)

- ChannelForge is a client/server product. The engine is the server. The browser is the client.
- Docker and a Windows server install are both wanted. The portable Windows bundle stays.
- The set-top-box parts (guide, browse, search, start playback) are OPTIONAL. ChannelForge must keep working alone as a builder of guides and playlists for Plex and other IPTV viewers. Set-top-box parts sit on top of the guide builder. The guide builder never depends on them.
- More than one user is possible.
- Settings such as appearance are stored on the server.
- Today the server binds loopback only and has no login.

## What runs where

| Part                       | Runs on                     | Owns                                                                                 |
| -------------------------- | --------------------------- | ------------------------------------------------------------------------------------ |
| Engine (PowerShell 7.6)    | Server                      | Config, source fetch, build, validation, accepted state, reports, M3U/XMLTV output   |
| Web UI files               | Server serves, browser runs | Screens only. No state authority.                                                    |
| Browser                    | User device                 | Display and input. Never a file path, secret or accepted state.                      |
| Optional set-top-box layer | Server, later               | Browse, search, start playback. Reads the guide builder output. Is never read by it. |

One engine, one API, one accepted-generation authority in every mode (ADR-0016).

## Docker contract

- Image: one image with the pinned PowerShell runtime, the module and `gui\dist`. No secrets in the image. Built: `docker/Dockerfile` and `docker/entrypoint.ps1` exist. Not published, and not yet verified by a real container run.
- Port: one TCP port, 47850 inside the container. The host maps it.
- Data volume: one mount at `/data`. It holds config, source cache, immutable generations, accepted pointers, reports, logs and outputs, using the same boundaries as ADR-0009. Nothing durable lives outside `/data`.
- First start: empty `/data` creates the folders and starts in setup state. No lineup is accepted automatically.
- First start (sign-in): with no admin password, the container starts in setup state, serves only the first-run page and health, and prints a one-time setup code to the container log.
- No password, setup code or hash is in the image or in an environment variable. The hash lives in `/data` config.
- Password reset: stop the container, run the reset command against the same volume, start again.
- Bind: inside the container the server binds all interfaces (`scripts\Start-ChannelForgeServer.ps1 -BindAddress 0.0.0.0`), so login is required (see below). Without sign-in and a config folder the server refuses to start in that mode. The launcher always turns sign-in on.
- Upgrade: stop, pull the new image, start with the same volume. The engine migrates state on start (ADR-0009). It keeps a copy of the pre-migration state and refuses to start if migration fails, leaving `/data` untouched.
- Backup: stop the container or use the engine's quiesce command, copy `/data`. Restore is copy back. Cache may be left out. The `/data` backup contains the password hash. Protect backups like the volume.

## Windows server install contract

- Run as a scheduled task at start-up, as `NT AUTHORITY\LOCAL SERVICE`, not as a service wrapper. The install and uninstall scripts (`scripts\Install-ChannelForgeServerTask.ps1`, `scripts\Uninstall-ChannelForgeServerTask.ps1`) are written, with tests that mock every system call. They have not been hand-tested on a real machine. See `docs/user/Server-At-Startup.md`.
- Port: one TCP port, default 47850, configurable (`-Port` on `scripts\Start-ChannelForgeServer.ps1`). The default bind is loopback. Network access is `-BindAddress`, allowed only with sign-in and a config folder. Firewall rule is opt-in and only added when the user turns on network access.
- Data folder: `%ProgramData%\ChannelForge` for the server install, same layout as the Docker `/data`. The portable bundle keeps `%LOCALAPPDATA%`.
- Service account: least privilege, read/write only to the data folder.
- First start, storage and reset: with no admin password, the server starts in setup state, serves only the first-run page and health, and prints a one-time setup code on the console. The hash lives in `%ProgramData%\ChannelForge` config, readable only by the service account and administrators. No password, setup code or hash is in the install files or an environment variable. A forgotten password is reset with the administrator-only reset command, then the server is restarted for a new code.
- Upgrade and backup: same rules as Docker.

## Login design options

| Option                      | What it is                                | Good                                  | Bad                                               |
| --------------------------- | ----------------------------------------- | ------------------------------------- | ------------------------------------------------- |
| A. Single owner password    | One password for the whole server         | Small, easy, enough for one household | No per-person settings. No audit of who did what. |
| B. User accounts with roles | Named users. Roles: owner, editor, viewer | Multi-user, per-user settings         | More code, password reset, account storage        |

Recommended minimum: option A first, built so the session carries a user id (always "owner" at first). Option B can then be added without changing the API shape. Viewer-only access is added with B.

Owner decision recorded (Nov 24, 2026, issue 150): option A, one shared admin password, with the session carrying a user id (always `admin` at first) so B can follow.

Rules for either option:

- Store only a salted slow password hash (for example PBKDF2 or Argon2) in the data folder. Never the password.
- Never store or log: passwords, session tokens, password hashes in logs, provider credentials, full request headers or cookies.
- Never put a password or secret in the repo, the image, an environment variable that gets logged, or a report.
- Sessions: random token, HttpOnly, SameSite=Strict cookie, expiry, server-side revoke.
- Failed logins are rate limited. Logs say "login failed" and a time, nothing more.
- First start on a network bind: the password is set through a one-time setup code printed to the local console. Owner decision recorded: one-time code, not a password file.

## What changes for a non-loopback bind

- Login required for every route except a bare health check that returns no data.
- Browser-sent Host and Origin checks must name the configured address, to block rebinding and cross-site requests.
- State-changing routes need a CSRF defense (SameSite plus an Origin check).
- Plain HTTP on a network is a risk. Recommend HTTPS through a reverse proxy, or a built-in certificate option. Owner decision needed: options are built-in TLS, reverse proxy documented only, or both. Recommendation: reverse proxy documented first.
- Redaction rules do not relax. Secrets and private paths stay out of responses.
- Default stays loopback. Network access is an explicit setting.
- See ADR-0016-AMENDMENT-DRAFT.md for the safety checks.

## Not verified

Current server code, the real default port and the existing health route were not read for this note.
