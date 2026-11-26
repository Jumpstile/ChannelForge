# Docker contract note (draft)

This is a proposed deployment contract. The image files now exist (`docker/Dockerfile`, `docker/entrypoint.ps1`, `docs/user/Server-Docker.md`); the image is not published and has not been verified by a real container run. Verified inputs: `docs/planning/CLIENT-SERVER-DESIGN-NOTE.md` specifies one container, TCP port 47850, `/data`, and server-mode setup; the owner decisions in `docs/planning/SERVER-AUTH-DESIGN-NOTE.md` sections 5-8 select shared-password sign-in and related rules.

## Container boundary

- One container exposes one TCP port, 47850. The host maps this port; container listens on all interfaces and requires sign-in.
- Mount persistent `/data` for config, cache, generations, accepted pointers, reports, logs, outputs, and the password hash. Back up and protect it; the hash is sensitive. Cache may be omitted from backup.
- Mount a server-side import folder read-only into the container. The browser sends no local file path; imports resolve within this mounted folder. Exact mount path is NOT DECIDED.
- No durable state or secret belongs in the image. Keep the same `/data` volume for upgrades.

## First start and sign-in

With no password set, first start creates required folders, enters setup state, and serves only the first-run page plus data-free health. The server prints a one-time setup code to the container console/log. Enter that code in first-run, then set one shared admin password (minimum 12 characters; a small built-in list of very common passwords is refused). Session user id is `admin` initially. A server restart signs everyone out; sessions are memory-only and never written to disk.

After five failed sign-ins, delay doubles to a 15-minute cap; no permanent lock-out. Exact schedule between threshold and cap is NOT DECIDED. Reverse-proxy sign-in is not supported.

## Environment settings and logs

No password, setup code, hash, or session token is configured through an environment variable. Exact supported environment setting names and defaults are NOT DECIDED; do not assume names beyond the contract's port default and `/data` mount.

Logs may report sign-in failure or password reset with a time. Never log passwords, setup codes, tokens, stream URLs, hashes, cookies, or full request headers. Setup code is intentionally printed once to the server console/log for first-run; protect access to container logs until setup completes.

## HTTP and password reset

Plain HTTP on a network is allowed with a warning on the first-run and sign-in pages. Put an HTTPS reverse proxy in front for network use; keep the application sign-in enabled behind it. Do not treat the proxy as an identity provider.

For a forgotten password, stop the container, run the product's one-shot password-reset command against the same `/data` volume, then start it again and complete setup with the new console code. Exact command syntax is NOT DECIDED and must not be guessed or run from this note. Reset changes only the sign-in credential state; preserve lineups, accepted state, config, and outputs.

## Not decided / not verified

- Final image name, import-folder mount path, environment setting names, and reset command syntax.
- Actual Docker image, port exposure, volume permissions, setup flow, log redaction, backup behavior, and reset behavior. No Docker runtime or product code was inspected or run.
