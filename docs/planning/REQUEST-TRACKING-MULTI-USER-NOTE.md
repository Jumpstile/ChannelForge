# Design note: request tracking for several users (issue #51-A)

Design note only. No code and no tests. Written Nov 23, 2026. Nothing was run.

Owner decision (Nov 23, 2026): request tracking stays in scope for a client/server product that may have several users.

A request is a user asking for a change, for example "add this channel" or "fix this guide". Tracking follows each request from ask to answer.

## Dependency on the login design

The client/server design note (docs/planning/CLIENT-SERVER-DESIGN-NOTE.md) was not present in this tree when this was written, and was not read. This note assumes only that the login design gives each user a stable user id and one role. If that note says otherwise, this note changes.

A single-user install has one implicit owner and needs no login. Tracking works there too, with one user.

## States

| State     | Meaning                                         | Who moves it       |
| --------- | ----------------------------------------------- | ------------------ |
| Open      | Asked, not looked at.                           | Any user (creates) |
| In review | Someone is looking at it.                       | Owner or editor    |
| Approved  | Agreed. Waiting to be done.                     | Owner or editor    |
| Done      | Change applied through the lineup editing path. | Owner or editor    |
| Declined  | Refused, with a short reason.                   | Owner or editor    |
| Withdrawn | The asker took it back.                         | The asker          |

Only forward moves, plus Withdrawn from Open or In review. A Done request links to the applied change set; it never changes the lineup itself.

## Roles

| Role   | Can do                                                       |
| ------ | ------------------------------------------------------------ |
| Owner  | Everything. Manage users and roles. Approve, decline, apply. |
| Editor | Create, review, approve, decline, and apply requests.        |
| Viewer | Create requests and see their own. Cannot approve or apply.  |

Owner decision needed: may a viewer create requests? Option A: yes. Option B: no, viewers only watch. Recommendation: A, since asking changes nothing.

## Audit trail

Every state change writes one record: request id, user id, old state, new state, time (UTC), short note. Records are append-only, kept in durable state (ADR-0009 audit history), and never edited. No stream URL, password, token or file path is stored in a record or note; free text is length-limited.

## What each user sees

- Owner and editor: all requests, filters by state, the audit trail.
- Viewer: own requests and their state. Not other users' requests, not the audit trail.
- Everyone sees plain state words and the decline reason on their own requests.

## What is built first

1. Single-user request list: create, state, notes, audit records. No login needed.
2. Roles and per-user views once the login design is accepted.
3. Notifications: later, and only if the owner asks.

Owner decision needed: build step 1 before the login design is done? Option A: yes. Option B: wait. Recommendation: A; the record already holds a user id, so step 2 adds no rewrite.

## Guardrails

Tracking never changes the lineup, the guide builder, M3U or XMLTV bytes, or guide-id contract v1.0. If it is off or removed, ChannelForge still builds guides and playlists.

## Not verified

- No code read. The client/server note and its login design.
- Whether issue #51 has more scope than described by the owner.
- Whether a durable audit store already exists.
