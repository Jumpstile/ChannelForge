# ADR-0016 amendment (draft): non-loopback bind and authentication

## Status

Proposed. Not accepted. Needs the owner.

## Context

ADR-0016 serves the web UI and API from the engine. The server today binds loopback only and has no login. The owner now wants Docker and a Windows server install, more than one possible user, and settings stored on the server. A Docker container must listen on a non-loopback address to be reachable. See CLIENT-SERVER-DESIGN-NOTE.md.

## Proposed decision

1. Loopback stays the default bind and needs no login.
2. A non-loopback bind is allowed only when authentication is configured. If not, the server refuses to start and says why in plain words.
3. Authentication model: owner decision needed. Options: single owner password; user accounts with roles; password first, accounts later. Recommendation: password first, session carries a user id so accounts can follow.
4. The accepted-generation authority, redaction rules and mutation boundaries from ADR-0016 do not change.
5. The set-top-box layer is optional and never a dependency of the guide builder.

## Safety checks that must exist before any non-loopback bind

- Startup check: refuse non-loopback bind without a configured login.
- Every route except a data-free health check requires a valid session.
- Host header and Origin checks against the configured address.
- CSRF defense on every state-changing route.
- Passwords stored only as salted slow hashes. No secrets in logs, reports, errors or the repo.
- Login rate limit and a uniform failure message.
- Secure session cookies. Server-side expiry and revoke.
- Same response size and time limits as loopback.
- Test with a second device on the network: unauthenticated request is refused for each route.
- Plain HTTP warning shown when the bind is not loopback and no TLS is in front. Owner decision needed: warn only, or block. Recommendation: warn, and document a reverse proxy.

## Consequences

- Docker and Windows server installs become possible.
- A forgotten password needs a documented reset path done on the server machine.
- More surface to test and keep secure. Loopback users see no change.
- Multi-user roles, if chosen later, need a separate ADR for permissions.

## Not verified

Current server code was not read. This amendment does not implement anything.
