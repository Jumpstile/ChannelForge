# ADR-0016 amendment: server authentication boundary

## Status

Draft. This amendment does not change the accepted ADR-0016 architecture decision.

## Decision

For Docker and Windows server deployments, the first release uses one shared admin password, set during first-run setup with a one-time setup code shown on the server console. A session carries a user id, initially `admin`. There is no reverse-proxy sign-in.

The password must be at least 12 characters and must not match a small built-in list of very common passwords. After five failed sign-ins, delay doubles to a 15-minute cap. There is no permanent lock-out.

Sessions exist in memory only. A server restart signs everyone out; session state is never written to disk.

Plain HTTP on a network produces a warning on the first-run and sign-in screens; it does not block use. HTTPS through a reverse proxy is recommended.

The Windows server password reset is an administrator-only command. The portable Windows bundle remains loopback-only and unchanged, with no password.

The browser never sends a local file path. File selection and access remain server-side; imports use the server's configured import folder.

## Relationship to ADR-0014

ADR-0014 is unchanged. It continues to govern outbound HTTPS acquisition transport and trust. This amendment concerns inbound browser-to-server access and does not weaken or replace that transport contract.

## Consequences

- Each person who knows the shared password has admin access; the session user id is `admin` in the first release.
- A server restart signs out all sessions. A Docker password reset must be performed on the host against the same data volume.
- Network HTTP remains usable but exposes credentials to network observers; HTTPS through a reverse proxy is recommended.
- The portable Windows bundle keeps its current loopback-only, no-password behavior.

## Not decided

- Future named-user and role model; session expiry and revocation details beyond restart behavior; password-change behavior; exact common-password list; exact delay schedule; concrete Docker reset command syntax.
- Setup-code lifetime and generation details; final Docker image, import-folder path, and environment-setting names.

This is a documentation amendment only. Authentication and Docker packaging are not implemented here.
