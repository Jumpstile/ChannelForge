# Aggregation Policies and Channel Numbers

Status: decision record for issue 153. Slice 1 (this note) is docs only. Slice 2 (your own channel numbers) is now built, using the recommendations for owner decisions 4, 5, 6 and 7 below; the owner has not answered them yet. Everything else here that is not already in [Multi-lineup and guide aggregation](MULTI_LINEUP_AGGREGATION.md) is still **NOT BUILT**. That note says what the code does today. This note says what later slices must build, and in what order.

## In plain words

### Two playlists carry the same channel

Today the first playlist wins. The other copy is dropped from the output. It is listed in the run result, but you are never asked. The goal is that this drop becomes a visible review item, and that you can choose what happens.

ChannelForge asks this question in exactly these words (NOT BUILT):

```text
ChannelForge found ESPN in more than one playlist.
What should happen?

1. Keep both streams and use Provider B as failover if Provider A fails.
2. Prefer Provider B and use Provider A as failover.
3. Keep only Provider A.
4. Keep only Provider B.
5. Keep both as separate channels.
6. Ask me later / mark review needed.
```

Choices 1 and 2 are the same policy with the two providers swapped. Choices 3 and 4 are one policy with two sources. So the six choices make five policies:

| Policy         | What you get                                                                                     | Questions 1-6        |
| -------------- | ------------------------------------------------------------------------------------------------ | -------------------- |
| `Failover`     | One channel. An ordered list of streams. A player that supports it moves to the next on failure. | 1 and 2              |
| `PreferSource` | One channel. One main stream. The other stays on record as a backup. It is not played.           | (see the note below) |
| `KeepOnly`     | One channel. One stream. The other source is left out, on purpose, and recorded.                 | 3 and 4              |
| `KeepSeparate` | Two channels in the lineup.                                                                      | 5                    |
| `ReviewNeeded` | Nothing is accepted for this channel until you decide.                                           | 6                    |

Note on `PreferSource`: the issue lists it as a policy but the six-choice question has no line for it. The question words are fixed by the issue, so this note keeps them. `PreferSource` is what choices 1 and 2 become on a profile with no failover (see Failover below): main stream plus recorded backup. [Owner decision 1.]

### The safe default

Today's behavior stays the default: the first source wins. One change: the dropped copy must show up as a `ReviewNeeded` item with the question above, not vanish. The lineup does not change, so nothing about the output moves. This is NOT BUILT.

### When ChannelForge asks

Only when your answer changes the lineup. Examples: two sources would become one channel, or one source would be dropped. It does not ask when the answer cannot change the output, for example two entries that are byte-for-byte the same stream address. Beginners see the safe default and a review item. Ordered failover lists and priorities stay in an advanced view.

### Your own channel numbers

- The number belongs to the channel in your lineup (the canonical channel), not to one provider's row.
- The numbers providers send (`tvg-chno`) stay on record as evidence. They are never overwritten.
- ChannelForge may suggest a number from provider data or from a numbering block. Your accepted number wins.
- If two channels get the same number, that is a review item. Nothing is accepted until you fix it.
- A re-run keeps your numbers unless you change them.
- A number change never changes the XMLTV channel id. Guide matching stays on the guide id.

### Failover

Plain M3U has no failover. A line in an M3U file is one name and one stream address. There is no standard way to say "try this one next". So:

- Failover stays **NOT BUILT** until we ship an output profile that can carry it.
- A profile that could carry it is one where the player or server itself holds more than one stream per channel. Candidates, none verified here: a Dispatcharr-style profile (a channel with several streams), and an Emby or Jellyfin-style profile with multiple sources per channel. [INFERENCE] These come from general knowledge of those products, not from this repo. Whether each really supports ordered failover must be checked in the profile slice.
- On a plain M3U profile, a `Failover` choice is shown but not accepted. It falls back to `PreferSource`, and the report says so. No silent downgrade.

## Technical section

### Where the choice is saved: `state/channel-decisions.json`

Facts from the repo:

- The file exists today. It is a JSON array of records `key`, `name`, `choice`, `guideId`, `decidedAt`. It is read by `Read-ChannelForgeChannelDecisions.ps1`. The key is a 64-character lowercase hex hash of the stream address.
- It has **no** schema version today.
- It is described only in `MULTI_LINEUP_AGGREGATION.md` and `docs/user/Build-Your-First-Lineup.md`. It is not named in any ADR, in `docs/adr/blocker-2-contract`, or in the durable state matrix. So it is **not a frozen contract** as far as I found. [INFERENCE] I searched by keyword only.
- The reader rejects an unknown `choice` and stops the run. An older build would stop on any new choice value. That is the safe failure, and the reason an explicit version is needed.

Proposal. Keep the file and the path. Change the top level from a bare array to an object, with an explicit version:

```json
{
  "schemaVersion": "channel-decisions/v2",
  "guideChoices": [
    {
      "key": "<64 hex>",
      "name": "ESPN",
      "choice": "KeepWithoutGuide",
      "guideId": null,
      "decidedAt": "2026-11-12T20:00:00Z"
    }
  ],
  "duplicatePolicies": [
    {
      "channelKey": "<canonical channel key>",
      "policy": "PreferSource",
      "primarySourceId": "<logical source id>",
      "alternateSourceIds": ["<logical source id>"],
      "decidedAt": "2026-11-18T00:00:00Z"
    }
  ],
  "channelNumbers": [
    {
      "channelKey": "<canonical channel key>",
      "number": 206,
      "decidedAt": "2026-11-18T00:00:00Z"
    }
  ]
}
```

Rules:

- `policy` is one of `Failover`, `PreferSource`, `KeepOnly`, `KeepSeparate`, `ReviewNeeded`. `alternateSourceIds` is ordered. `Failover` uses that order. `KeepSeparate` has no source ids.
- `number` is an integer from 1 to 9999. [Owner decision 4 on the range.]
- The old bare-array file is read as v1 and rewritten as v2 only after the user accepts a migration. The old records become `guideChoices` with no change of meaning. A file with an unknown version stops the run, like a damaged file does today. Nothing is published.
- `channelKey` is the canonical channel key from the identity model (`CHANNEL_IDENTITY_MODEL.md`). The existing guide choice key (stream hash) stays as it is, because it is already in use. [Owner decision 5.]
- Source ids are the ids from `Get-ChannelForgeLogicalSourceId.ps1`. They are already stable.

Alternative: a second file, for example `state/channel-policies.json`, and leave this file alone. That avoids a migration, but gives two decision files and two readers. Recommendation: extend the one file, with the version bump, because the user edits one place and the reader is reused.

### Number collisions and the guide

- Collision order of checks: your number against your number, then your number against a block-assigned number. A user number always beats a block number. The displaced block channel moves to the next free number in its block, or becomes unnumbered with the existing warning. Two user numbers equal: both channels become `ReviewNeeded`. Nothing is picked.
- The XMLTV channel id comes from the guide binding (guide-id contract v1.0). A number is a presentation field. It must never be used to build or rewrite a guide id. A later test must prove that changing a number leaves every XMLTV `channel` id byte-identical.
- Number output: `Export-ChannelForgeM3UPlaylist.ps1` already writes `tvg-chno` from `Channel.AssignedNumber` (through `ConvertTo-ChannelForgeM3UEntryBytes.ps1`). Block-assigned numbers reach the output today. Only `PreferredNumber` is unread. Slice 2 must feed the user number into `AssignedNumber`; it does not need a new output field.

### Where the policy is recorded

Two places, with different jobs:

1. **The saved choice** (`channel-decisions.json`, above). This is the user's standing answer. It is read on every run.
2. **The decision manifest and accepted generation.** When acceptance runs, the choice that was applied is copied into the decision manifest, with the source ids and the number. This is the record of what was accepted. A later run compares its new proposal to it. Today the manifest holds only `DuplicateCount` for duplicates. NOT BUILT.

The guide-id contract v1.0 is described in the planning notes under `docs/planning` (for example `PHASE1-EPG-DESIGN-NOTE.md`). I did not find a copy of it under `docs/adr` or `docs/architecture`. [INFERENCE] The lane rules say it is there. Whatever the location, this plan does not change it.

### Contracts touched

| Contract                                                                                                                                                                         | Touched by                                              | Change                                                                                                                                       |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `state/channel-decisions.json`                                                                                                                                                   | policies, numbers                                       | Version bump (v1 bare array to `channel-decisions/v2`). Not frozen per the docs I found.                                                     |
| Candidate manifest (`candidate-manifest/v2`)                                                                                                                                     | per-channel policy, contributing sources, number change | Additive only, if new fields are optional and absent means today's behavior. Otherwise a version bump. [NOT VERIFIED: canonical form rules.] |
| Decision manifest (`decision-manifest/v2`)                                                                                                                                       | applied policy and number                               | Additive only on the same condition. Otherwise a version bump.                                                                               |
| Accepted state (`accepted-state/v2`)                                                                                                                                             | accepted number, accepted policy, stream list           | Version bump, because the accepted lineup content changes. FROZEN family: owner and a version plan required.                                 |
| Evidence records (`GuideEvidenceRecord`, external evidence contract)                                                                                                             | none for slices 1-6                                     | None. Provider numbers are already carried as channel evidence. Slice 7 (guide conflicts) may add. Additive only.                            |
| Guide quality scorecard (`guide-quality-scorecard/v1`)                                                                                                                           | none until slice 7                                      | None now. Additive only later.                                                                                                               |
| Guide-id contract v1.0                                                                                                                                                           | nothing                                                 | None. Frozen. Never broken. A channel is never dropped. The `guide: null` marker stays.                                                      |
| `blocker-2-contract` (v7 is the current frozen authority per `FREEZE-RECORD.md`; v6 is historical; v8 is only a proposal that `Build-My-Lineup.ps1` pins as a candidate version) | accepted-state and manifest shape                       | Any shape change in the manifests above goes through that contract's freeze process.                                                         |

The numbers in "Additive only" are a design aim. They hold only if no reader rejects an unknown field. That was not checked.

### Order of slices

Matches the audit's slice list. Sizes are the audit's, not measured.

| Order | Slice                                                                                                 | Size            | Needs                                         |
| ----- | ----------------------------------------------------------------------------------------------------- | --------------- | --------------------------------------------- |
| 1     | This note.                                                                                            | small (docs)    | Owner review of the decisions below.          |
| 2     | User-chosen numbers: read `channelNumbers`, win over blocks, collision review, show in the candidate. | medium          | Decisions 4 and 5. File version bump.         |
| 3     | Duplicate review item: stop the silent drop, keep today's default, show the question.                 | small to medium | Decision 2.                                   |
| 4     | Save and replay `KeepOnly`, `KeepSeparate`, `PreferSource`, `ReviewNeeded` in `duplicatePolicies`.    | medium          | Decision 1.                                   |
| 5     | Failover: ordered alternate streams through the lineup to a profile that supports it.                 | large           | Decision 3. NOT BUILT until a profile exists. |
| 6     | Record policy and number in the decision manifest and accepted generation.                            | medium          | Version plan for the frozen family.           |
| 7     | Multi-guide conflict gate.                                                                            | medium to large | Separate decision. Not part of this note.     |
| 8     | Report additions: per-channel policy, sources, number, guide freshness.                               | small           | Slices 3 to 7.                                |
| 9     | Update `MULTI_LINEUP_AGGREGATION.md` and add a beginner page.                                         | small           | Each slice as it lands.                       |

Slices 2 and 3 are independent and can go in either order. Slice 6 must land before anything is "accepted" with a policy, because an applied policy that is not in the decision manifest cannot be checked on the next run.

## Open owner decisions

1. **`PreferSource` in the question.** The issue's six choices have no line for it. Recommendation: keep the six lines as written, and treat `PreferSource` as the stored form of choices 1 and 2 on a profile with no failover.
2. **Default for the review item.** Recommendation: keep first-source-wins as the default and mark it `ReviewNeeded`, so the lineup does not change on upgrade.
3. **First failover target.** Recommendation: do not build failover until you name one output profile. Until then choices 1 and 2 are recorded but act as `PreferSource`, and the report says so.
4. **Number range.** Recommendation: 1 to 9999, integers only.
5. **Which key for new records.** Recommendation: the canonical channel key for policies and numbers. Keep the stream-hash key for guide choices.
6. **One decision file or two.** Recommendation: one file, `channel-decisions/v2`, with a migration the user accepts.
7. **Is `state/channel-decisions.json` frozen?** I found no doc that freezes it. Recommendation: treat it as not frozen, and say so in the durable state matrix when slice 2 lands.

## Not verified

- No code, test or validator other than the two markdown checks was run.
- I did not read how `candidate-manifest/v2` and `decision-manifest/v2` treat unknown fields.
- Player and server failover support is general knowledge, not checked.
