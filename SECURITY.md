# Security Policy

**Repository publication status:** `PASS`. The repository is public and GitHub private vulnerability reporting is enabled. The supported version is the current `main` branch until the first tagged release. Product release status remains `NOT_RELEASE_READY`; do not publish a release until the First Usable Alpha gate is satisfied.

## Reporting a vulnerability

Use GitHub private vulnerability reporting from the repository Security tab. It is enabled and is the only approved private reporting route for now; no public email contact is listed. Do not disclose an unpatched vulnerability in a public issue, pull request, discussion, chat, attachment, or comment before coordinated review.

Do not post provider URLs, M3U or XMLTV contents, Xtream Codes/XC credentials, API keys, tokens, passwords, private keys, accepted-lineup contents, generation identifiers, private paths, private network details, or sensitive logs publicly.

If GitHub private vulnerability reporting is unavailable, stop before disclosure. A public issue is not an acceptable substitute for a secret or active vulnerability report.

Provide only redacted evidence: affected version or commit, safe reproduction steps, impact, and sanitized logs or screenshots. Use synthetic fixtures and reserved domains only.

## Coordinated response

Maintainers will acknowledge reports when practical, investigate privately, coordinate remediation, and decide whether a sanitized advisory or release notice is appropriate. Exposed credentials should be rotated immediately through the relevant provider or service owner.

## Scope

In scope:

- ChannelForge application code and scripts;
- local web server;
- web UI;
- source acquisition and transport boundaries;
- M3U and XMLTV parsing;
- guide and EPG handling;
- accepted-generation storage, promotion, rollback, and redaction boundaries; and
- CI and workflow security.

Out of scope:

- third-party IPTV, EPG, hosting, or authentication providers;
- user-provided playlists, guides, or credentials;
- illegal or unauthorized stream sources;
- downstream tools not controlled by ChannelForge; and
- Plex, Dispatcharr, IPTVBoss, or similar behavior unless ChannelForge integration code is directly involved.

## Safe test data

Use synthetic, deterministic, reserved-domain fixtures only. Never use real provider data, real subscriptions, real playlists, real guides, real credentials, or real user filesystem paths.

## Supported versions

The current `main` branch is the only supported version line until the first
tagged release. The supported-version policy will be reviewed and updated with
that first tagged release.

| Version line          | Security support status                              |
| --------------------- | ---------------------------------------------------- |
| Current `main` branch | Supported until the first tagged release             |
| First tagged release  | Policy to be reviewed and published with the release |

## Response expectations and disclaimer

Response timing is not guaranteed. Security support is not guaranteed for every version or deployment. The project and Materials are provided as-is, without warranty or guarantee of support.

**Repository publication gate:** PASS. Repository visibility changed to public
on 2026-09-18 after hosted-ref cleanup, all-tip secret scanning,
branch-protection verification, and exact-head pull-request CI. GitHub private
vulnerability reporting is enabled. GitHub Support cleanup is complete: known
sensitive commits are not reachable from hosted branch or tag tips, and the
affected PR diff/code surfaces were removed while PR discussion history was
preserved. PR #163 merged and post-merge public `main` CI passed on
`9879b302709e8d9c72a7c4dd552add5ce031a5f1`. Product release remains a
separate gate and is `NOT_RELEASE_READY` until the First Usable Alpha
requirements are complete.
