# ADR-0016 amendment: server authentication boundary

## Status

Draft. This amendment does not change the accepted ADR-0016 architecture decision. The sign-in described here is built in the server (password store, start-up guard, sessions, first-run page, request checks, rate limit, change password and reset command). Docker and Windows server packaging are not built.

## Decision

For Docker and Windows server deployments, the first release uses one shared admin password, set during first-run setup with a one-time setup code shown on the server console. A session carries a user id, always `admin` at first. Named users with roles may follow in a separate ADR. A reverse-proxy-delegated sign-in is not built.

The password must be at least 12 characters and must not match a small built-in list of very common passwords. It is stored only as a salted slow hash in the config area of the data folder. The hash and session tokens never appear in logs, reports, Doctor output, errors, API responses, the repo or the image. After five failed sign-ins, delay doubles to a 15-minute cap. There is no permanent lock-out. The failure message is uniform.

Sessions exist in memory only. A server restart signs everyone out; session state is never written to disk.

In setup state a non-loopback server serves only the first-run page and a data-free health check. First-run requires a one-time setup code shown on the server console.

The session cookie is HttpOnly and SameSite=Strict, and Secure when HTTPS is used. Origin is checked on every state-changing route.

Plain HTTP on a network produces a warning on the first-run and sign-in screens; it does not block use. HTTPS through a reverse proxy is recommended.

A forgotten password is reset only on the server machine, with an administrator-only command on Windows. The reset removes the hash and does not touch lineups, accepted state or outputs. The portable Windows bundle stays loopback-only with no sign-in and is unchanged.

The browser never sends a local file path. File selection and access remain server-side; imports use the server's configured import folder.

## Relationship to ADR-0014

ADR-0014 is unchanged. It continues to govern outbound HTTPS acquisition transport and trust. This amendment concerns inbound browser-to-server access and does not weaken or replace that transport contract.

## Consequences

- Each person who knows the shared password has admin access; the session user id is `admin` in the first release.
- A server restart signs out all sessions. A Docker password reset must be performed on the host against the same data volume.
- Network HTTP remains usable but exposes credentials to network observers; HTTPS through a reverse proxy is recommended.
- Backups include the password hash. Protect backups like the data volume.
- The portable Windows bundle keeps its current loopback-only, no-password behavior.

## Not decided

- Future named-user and role model; sessions kept across a restart; exact common-password list; exact delay schedule between the threshold and the cap; concrete Docker reset command syntax.
- Final Docker image, import-folder path, and environment-setting names.

HTTPS inside ChannelForge, email recovery and Docker or Windows server packaging are not built.
