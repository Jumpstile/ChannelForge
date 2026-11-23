# Plan: optional set-top-box layer

Planning note only. No code and no tests. Written Nov 23, 2026. Nothing was run.

Owner decision (Nov 23, 2026): ChannelForge may grow into a set-top-box type system (guide, browse, search, start playback) on client/server. That part is OPTIONAL. ChannelForge must keep working alone as a builder of guides and playlists for Plex and other IPTV viewers. Users may use their own IPTV viewer.

## Rules for every stage

- Set-top-box parts sit on top of the guide builder. The builder never depends on them. Removing them changes no builder output.
- Frozen: guide-id contract v1.0, the `guide: null` marker, never drop a channel. M3U, XMLTV and accepted-state bytes do not change.
- Security: stream URLs and credentials never appear in the repo, logs, reports or error text. Fixtures and docs use only neutral placeholder hosts (for example example-host). On screen, a source may be named by host only, as in the lineup workspace note; if a host could identify a provider, show a label the user chose instead. Never show anything after the host.
- Each stage reads the accepted lineup. None writes it.

## Stage 1: browse and search the accepted lineup

- Needs first: the read-only lineup workspace (issue #56 view part) and the client/server design.
- Gives: browse by group, search by name, see guide state.
- Never changes: the builder, accepted state, output files.
- Milestone: pull forward from Milestone 8. It is almost the same as the lineup workspace, so little extra cost.

## Stage 2: guide screen

- Needs first: stage 1 and the timeline grid (issue #43).
- Gives: a time grid for viewers, now and next.
- Never changes: guide data, guide ids.
- Milestone: with #43, early. The grid is useful to the builder too.

## Stage 3: start playback

What "start playback" means. Owner decision needed.

| Option | Meaning                                                  | Cost and risk                                                             |
| ------ | -------------------------------------------------------- | ------------------------------------------------------------------------- |
| A      | Hand the stream address to the user's own player or app. | Smallest. Address must reach the client without being logged or shown.    |
| B      | Play inside ChannelForge (built-in player).              | Large. Codecs, buffering, many devices. ChannelForge becomes a media app. |
| C      | A, with B added later if users ask.                      | Same start as A.                                                          |

Recommendation: A, as a stage in its own right, with a rule that the address is passed directly to the player and never written to a file, log, report or error. Revisit B only on real demand.

- Needs first: stage 1, login (client/server), a decision on how credentials are held (ADR-0002).
- Never changes: how the builder writes playlists.
- Milestone: Milestone 8 stays, because it adds the secret-handling risk.

## Stage 4: living-room client

- Needs first: stages 1 to 3 and a remote-friendly design (large text, remote keys, ADR-0006).
- Gives: an app on a TV box or similar.
- Never changes: the server API contract for stages 1 to 3.
- Milestone: Milestone 8, last. Choice of device is an owner decision.

## Proposed milestone placement

Epic #62, #188 and #67 are in Milestone 8 "Cross-Service Discovery" as future scope.

| Part                      | Proposal                         | Why                                                |
| ------------------------- | -------------------------------- | -------------------------------------------------- |
| Stage 1 browse and search | Move earlier, with #56 workspace | Same data and routes, little new work.             |
| Stage 2 guide screen      | Move earlier, with #43           | Shared with the builder's timeline grid.           |
| Stage 3 playback          | Stay in Milestone 8              | Secret handling and client/server needed first.    |
| Stage 4 living-room       | Stay in Milestone 8              | Depends on all earlier stages and a device choice. |

Which issue number maps to which stage was not checked (see below).

## Not verified

- No code read and no GitHub access. The titles and contents of #62, #188 and #67 were not read; the milestone placement is a proposal from the owner's description only.
- The client/server design note was not present in this tree.
- Whether any playback or player code exists.
