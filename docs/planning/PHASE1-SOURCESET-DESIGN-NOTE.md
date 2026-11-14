# Phase 1 design note: source set v2 (issue #175, Alpha.1)

Contract: sourceset/v2

Design only. No product code, test, schema or workflow was changed. No product code or test was run. Facts below come from reading this tree on Nov 13, 2026.

## Why

Issue #175 asks for one durable, server-owned list of playlists and guides, with explicit bindings between them. This note fixes the contract for headless steps 1 to 6 so each later PR stays small.

The main finding: this tree already holds a large part of steps 1 to 6 (see the next section). The work left is to close real gaps, not to build from scratch. The slice plan is written for that.

## What exists today

| Step                      | Real file and function                                                                                                                                                                                                                                         | State                                                                                                                                                                                                                                           |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 Records                 | Private\Invoke-ChannelForgeSourceEnrollment.ps1 (`Write-ChannelForgeSourceSet`, `Read-ChannelForgeSourceEnrollmentRecord`, `Assert-ChannelForgeSourceEnrollmentV2Integrity`), schemas\source-enrollment.schema.json                                            | Built. One canonical JSON file, state\source-enrollment.json, version string `source-enrollment/v2`. Atomic write, reparse-point checks, `EnrollmentHash`. Records have ID, label, kind, enabled, present, priority, hash, provenance, refresh. |
| v1 migration              | Same file, `Convert-ChannelForgeSourceEnrollmentV1ToV2`                                                                                                                                                                                                        | Built. A v1 file is converted in memory on every read to one playlist plus zero or one guide with a default binding. A read never rewrites the file.                                                                                            |
| 2 Multi-source            | Private\Convert-ChannelForgeGuidedSetupSourceSet.ps1 (`ConvertFrom-ChannelForgeGuidedSetupMultiSourceRequest`), Get-ChannelForgeGuidedSetupProposal.ps1 (limits 8 playlists, 8 guides, 16 bindings, 16 MB total), Invoke-ChannelForgeGuidedSetupAcceptance.ps1 | Built for the browser path only. No headless entry point. Limits live in the browser code, not in the store.                                                                                                                                    |
| 3 Public HTTPS            | `Test-ChannelForgeSourceUrl`, `Read-ChannelForgeGuidedSetupRemoteBytes` (calls `Open-ChannelForgeRemote*SourceStream`, the pinned transport), `Get-ChannelForgeRemoteSourceBytes`                                                                              | Built. No second downloader. The reader rejects URLs with user info, query or fragment.                                                                                                                                                         |
| 4 Bindings                | Same enrollment file, `binding` records (GuideId, PlaylistIds, AppliesToAll, ExplicitlyUnbound, Enabled, Revision)                                                                                                                                             | Records built. No headless way to change one. `Revision` is stored but nothing reads it.                                                                                                                                                        |
| 5 Candidate               | Private\New-ChannelForgeCandidateProposalFromSourceSet.ps1, Public\New-ChannelForgeSourceSetCandidateProposal.ps1                                                                                                                                              | Built (contract v7). Guides with no binding are not applied. Identity gaps are listed below.                                                                                                                                                    |
| 6 Refresh and persistence | scripts\Invoke-ChannelForgeSourceRefresh.ps1, Public\Get-ChannelForgeSourceRefreshPlan.ps1, `Update-ChannelForgeSourceEnrollmentRefreshState`                                                                                                                  | Partly built. Per-source result and last-known-good are kept. Gaps are listed below.                                                                                                                                                            |

Accepted-state store (not changed by this note): Private\Invoke-ChannelForgeGenerationStore.ps1, Public\Publish-ChannelForgeAcceptedGeneration.ps1, Public\Recover-ChannelForgeAcceptedState.ps1.

Helpers to reuse, all existing: `Get-ChannelForgeDomainHash`, `ConvertTo-ChannelForgeCanonicalJson`, `Write-ChannelForgeSourceEnrollmentAtomicJson`, `Assert-ChannelForgeSourceEnrollmentPath`, `Get-ChannelForgeSourceSetSourceId`, `Write-ChannelForgeSourceSet`, `Get-ChannelForgeSourceEnrollmentIntegrity`, `Get-ChannelForgeRemoteSourceBytes`, `Test-ChannelForgeSourceUrl`, `Get-ChannelForgeLogicalSourceId`, `Test-ChannelForgeCandidateNamespace`, `Publish-ChannelForgeReviewedCandidate`.

## Real gaps found (by reading)

1. **Binding revision is not in the candidate identity.** `ConvertTo-ChannelForgeCandidateManifest` hashes only source IDs and input byte hashes. A binding change that gives the same match result gives the same hash.
2. **`Enabled` on a binding is ignored.** The candidate builder reads only `AppliesToAll` and `ExplicitlyUnbound`.
3. **Two bindings for one guide are legal on disk, but the builder keeps only the last.** The browser parser allows one binding per guide; the store does not.
4. **One bad playlist blocks every source.** `Get-ChannelForgeSourceEnrollmentInputs` throws when any local source is missing. Records are not lost, but nothing can refresh.
5. **Refresh builds one candidate per changed source.** Two changed sources give two candidates, and neither shows both changes. A changed local source builds with the first playlist only and ignores bindings.
6. **No remove, no edit, no replace.** The only writer rebuilds the whole set. The one-playlist default binding in `Write-ChannelForgeSourceSet` would silently retarget a guide if it ran after a removal.
7. **Replacing bytes overwrites the snapshot in place.** The managed file name is the source ID, so a replacement erases the last-known-good file before the record is updated.
8. **Small record faults.** `Present` is always true, even for a remote source with no snapshot. The migrated v1 record carries a `LegacyVersion` key that the schema does not list. Label is not checked for uniqueness.

## Contract: sourceset/v2

### Name and version

`sourceset/v2` is the contract name in docs and review. The on-disk version string stays `source-enrollment/v2`. Renaming it would invalidate every saved `EnrollmentHash` for no user gain (owner question 1).

### Storage

- One file: `state\source-enrollment.json`. Canonical JSON, UTF-8, atomic temp-then-move write. Source bytes live in `state\managed-sources\`.
- The file is the only authority for which sources exist. Candidates, caches and reports are derived and disposable.
- A failed read of this file reports `Corrupt` and changes nothing.

### Record shapes

Source record (same shape for playlists and guides; field names as in the schema today):

| Field                   | Type                         | Shown to user            | Rule                                                                                        |
| ----------------------- | ---------------------------- | ------------------------ | ------------------------------------------------------------------------------------------- |
| SourceId                | 64-hex                       | no                       | Server-made. Assigned once and stored. Never recomputed from content (see ID rules).        |
| Kind, Format            | M3U or XMLTV; m3u or xmltv   | Kind                     | Playlists hold only M3U. Guides hold only XMLTV.                                            |
| Label                   | string, 1 to 128 chars       | yes                      | Safe display name. Unique per kind, ignoring case. No control characters.                   |
| SourceKind              | managed-file or public-https | yes (as words)           | No other kinds in Alpha.1.                                                                  |
| Enabled                 | bool                         | yes                      | A disabled source stays in the set and is skipped by candidates.                            |
| Present                 | bool                         | yes                      | True only when a validated snapshot exists in `managed-sources`.                            |
| Priority, OrderKey      | int, string                  | no                       | Order of merge only. Never decides which playlist a guide serves.                           |
| ManagedPath             | string or null               | no                       | `state/managed-sources/<64-hex>.m3u` or `.xml`. Checked against the allowed root on use.    |
| Url                     | string or null               | no                       | Public HTTPS only. No user info, query or fragment. Treated as a secret in logs and status. |
| ContentHash, ByteLength | 64-hex or null; int or null  | no                       | Of the stored snapshot. Domain `managed-source-bytes/v1`.                                   |
| Provenance              | object                       | no                       | Origin (guided-setup, legacy-source-enrollment/v1, source-set-v2) and time. No secrets.     |
| Refresh                 | object                       | State and last time only | State, LastValidatedAtUtc. Other keys are internal.                                         |

Binding record: `BindingId`, `GuideId`, `PlaylistIds` (sorted, unique), `AppliesToAll`, optional `ExplicitlyUnbound`, `Enabled`, `Revision` (integer, 1 or more). Never shown: IDs. Shown: guide label, playlist labels, enabled, "all playlists" or "no playlist".

Set record: `SourceSetId`, `EnrollmentId`, `Status`, `GuideMode`, `Playlists` (1 to 8), `Guides` (0 to 8), `Bindings` (at most one per guide), `AcceptedWorkflow`, `RefreshPolicy`, `LastRefreshStatus`, `CreatedAtUtc`, `UpdatedAtUtc`, `EnrollmentHash`. Unchanged from the schema. Limits are enforced by the store, not only by the browser (slice 1).

### ID rules

- `SourceId` = `Get-ChannelForgeSourceSetSourceId` over kind, source kind and a source key, at creation. It is stored and never recomputed. Replacing or refreshing bytes keeps the ID. A migrated v1 record keeps its stored content-derived ID for the same reason.
- `BindingId` = domain hash `source-binding/v2` over guide, playlists, mode and `Revision`. A new revision is a new ID.
- No ID is derived from a URL or a path. IDs never reach the browser.

### Migration from v1

- Read: v1 loads as one playlist (label "Saved playlist"), zero or one guide (label "Saved guide"), and, when a guide exists, one default binding to that playlist, revision 1. The v1 hash check runs first.
- Write: the first write after a read saves v2. Until then the file stays v1. No second authority is created.
- `LegacyVersion` is removed from the converted record, or added to the schema (slice 1).

## Binding rules

1. A guide serves the playlists listed in its binding. `AppliesToAll` means every enabled playlist at candidate time. Source order and priority never imply ownership.
2. One guide may serve many playlists (one binding with many IDs). One playlist may have many guides (many guides name it). One binding per guide.
3. A guide with no binding, or a disabled binding, is not applied. It is listed as actionable. It is never retargeted. The one-playlist default binding applies only when a set is first created, never on edit.
4. Replacing or refreshing a guide keeps its `SourceId`, so its binding stays.
5. Removing a playlist removes that ID from every binding. A binding left with no playlist is kept as a binding with no target, and its guide becomes actionable. Nothing else changes.
6. Removing a guide removes its binding and nothing else.
7. Every change to a binding (targets, ALL, unbound, enabled) adds 1 to `Revision`.

### How the binding enters the candidate hash

The frozen build-identity schema (contract v7, PART-B) lists the exact fields of `BuildIdentityInput`. This note does not add a field. Binding identity goes into a value the schema already hashes: the guide's logical source ID.

- `BindingFingerprint` = `Get-ChannelForgeDomainHash` domain `source-binding-identity/v2` over `Revision`, `Enabled`, mode (playlists or none) and the sorted logical IDs of the effective playlists. ALL is resolved to the enabled playlists.
- Guide logical source ID = `Get-ChannelForgeLogicalSourceId` as today, with the fingerprint appended to the provider component. Playlist logical IDs are unchanged.

The effect: any change to targets, ALL, unbound, enabled or revision changes `SelectedLogicalSourceIds` and `InputArtifactHashes`, so it changes `BuildIdentity` and the manifest hash.

### When the hash equals today's value

A set is **simple** when all hold: one enabled playlist, at most one enabled guide, and the guide's effective binding is that one playlist, enabled, not unbound, revision 1. ALL with one playlist counts as that playlist.

For a simple set the fingerprint is not applied, so the hash is the value each existing caller produces today:

- A v1 config, or a one-playlist guided setup on the single-source path, still builds through `New-ChannelForgeCandidateProposal` unchanged.
- A one-playlist set on the source-set path still builds through `New-ChannelForgeCandidateProposalFromSourceSet` with today's label-based logical IDs.

The two routes give different hashes for the same bytes today. They differ in the M3U source name (file base name or label), the guide source ID (`candidate-xmltv` hashed by `Get-ChannelForgeRawXmltvProjection`, or label-based `Get-ChannelForgeLogicalSourceId`) and the contract version (v8 or v7). Both feed `InputArtifactHashes` and `SelectedLogicalSourceIds`. A v2 set built on the source-set route therefore does **not** match the legacy route, and this note does not merge them.

**Legacy identity rule.** The route is chosen by the record, never by the caller. A simple set whose playlist `Provenance.Origin` is `legacy-source-enrollment/v1` or `guided-setup` (the origins written for v1 files and the single-file browser path) is built through `New-ChannelForgeCandidateProposal` with the file base name, `candidate-xmltv` guide ID and contract version that path uses today. Every other set uses the source-set builder. So a migrated v1 config keeps its hash by routing, with no hash math. The one catch: today the browser path names the file `input` and refresh names it by source ID, so those two legacy callers already differ from each other. The rule keeps each caller's current name; it does not make them agree (owner question 8).

A binding change on a simple set (revision 2 or more) changes the hash and moves the set to the source-set route. That is intended and shown to the user as a changed candidate.

Label feeds the logical ID today. Renaming a source therefore changes the candidate identity. No rename operation is planned; remove and add instead.

## Failure semantics

| Event                                                    | Result                                                                                                                                                           |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One remote source fetch fails                            | That source reports `REFRESH_FAILED` (Degraded). Its snapshot and record are not touched. Other sources refresh. The set file stays.                             |
| A source has bytes on disk that no longer match its hash | State `Changed`. A candidate is built for review. Nothing is accepted.                                                                                           |
| A source file is missing or unsafe                       | That source reports `Unavailable`. Its record stays. No candidate is built (a candidate without it would drop channels). Other sources still refresh and report. |
| A remote source was never fetched (no snapshot)          | `Present` false. It blocks candidates and is reported as needs attention. Other sources are unaffected.                                                          |
| A guide fails to parse                                   | The whole candidate fails with the guide named. Accepted output is unchanged.                                                                                    |
| Two guides disagree for the same channel and time        | Not designed here (step 8). From reading, the merge fails closed. The candidate fails; no output is replaced.                                                    |
| The set file is corrupt                                  | `Corrupt`. No write, no delete. Accepted output is unchanged.                                                                                                    |
| A write stops half way                                   | Atomic move keeps the old file. A snapshot replaced early shows as `Changed`, never as silent success (slice 8 removes this window).                             |

Rules that always hold: a candidate never writes accepted state; a failed refresh never overwrites a snapshot; no channel is dropped; `guide: null` stays; the file is deleted by no failure path.

## Out of scope and why

| Item                                                    | Why                                                                               |
| ------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Browser controls (step 7)                               | Headless first. Each control needs the commands below.                            |
| Cross-guide comparison (step 8)                         | Needs a policy design. Today a conflict fails closed.                             |
| Online evidence adapters (step 9), enrichment (step 10) | No user problem in steps 1 to 6.                                                  |
| A new build-identity field                              | Changes frozen contract v7. Needs a new contract revision (owner question 2).     |
| Merging the single-source and source-set hash routes    | Would change today's hashes. Frozen.                                              |
| Source rename, reorder commands                         | Rename changes identity. Priority works as written.                               |
| Credential or tokenized URLs                            | Stay unsupported.                                                                 |
| Conditional fetch (ETag) for enrolled sources           | Full bounded fetch works. The unused cache keys in `Refresh` are a later cleanup. |

## PR slice plan, steps 1 to 6

Each slice targets under 150 changed lines (product code plus tests) and changes no published bytes for a simple set. Test files: tests\unit\SourceEnrollment.Tests.ps1 and tests\unit\SourceRefreshExecutor.Tests.ps1 unless named.

| #   | Step | Slice                                                                                                                                                                             | Files                                                                                                                                   | What it protects for the user                                                                             |
| --- | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1   | 1    | Store hygiene: limits in the store, one binding per guide, unique labels, `Present` means snapshot exists, `LegacyVersion` fix                                                    | Invoke-ChannelForgeSourceEnrollment.ps1, Get-ChannelForgeGuidedSetupProposal.ps1 (limits move), source-enrollment.schema.json           | A hand-edited or corrupt file cannot give a guide two owners or an unlimited set. Labels name one source. |
| 2   | 2    | Headless add and remove of managed-file sources. Remove drops only that relationship and never auto-binds                                                                         | New Public\Add-ChannelForgeSourceSetSource.ps1, Remove-ChannelForgeSourceSetSource.ps1, ChannelForge.psd1                               | A user can build a multi-source set without the browser. Removing a playlist does not retarget a guide.   |
| 3   | 3    | `-Url` on add: fetch with `Get-ChannelForgeRemoteSourceBytes`, parse, then save. Nothing saved on failure                                                                         | Add-ChannelForgeSourceSetSource.ps1 only                                                                                                | A bad or tokenized URL never becomes a saved source. Same transport and trust code.                       |
| 4   | 4    | `Set-ChannelForgeSourceSetBinding`: playlists, ALL, unbound, enabled. Adds 1 to `Revision`. Rejects invalid targets                                                               | New Public\Set-ChannelForgeSourceSetBinding.ps1, ChannelForge.psd1                                                                      | The user picks which playlists get which guide. A guide is never retargeted silently.                     |
| 5a  | 5    | Binding fingerprint in the guide logical ID for non-simple sets. Route simple legacy-origin sets to the single-source builder. Honor `Enabled`. Golden hash test for a simple set | New-ChannelForgeCandidateProposalFromSourceSet.ps1, one small helper for the fingerprint, new test                                      | A binding change shows as a changed candidate. A simple set keeps today's hash.                           |
| 5b  | 5    | Move the script-local enrolled candidate builder into a module function and use it from the refresh script and headless callers                                                   | Public\New-ChannelForgeEnrolledCandidate.ps1 (moved code), Invoke-ChannelForgeSourceRefresh.ps1, ChannelForge.psd1                      | One way to build a candidate from the saved set. No duplicate logic.                                      |
| 6a  | 6    | Refresh builds one candidate with every changed source replaced. A changed local source uses the set builder, not the first playlist                                              | Invoke-ChannelForgeSourceRefresh.ps1, SourceRefreshExecutor.Tests.ps1                                                                   | A multi-source refresh shows all changes together. Bindings are honored.                                  |
| 6b  | 6    | Accept a reviewed refresh candidate: new snapshot named by content hash, record updated, old snapshot removed after success. IDs and bindings kept                                | New Public\Update-ChannelForgeSourceSetSource.ps1, reuse `Publish-ChannelForgeReviewedCandidate`, `Test-ChannelForgeCandidateNamespace` | Refreshed content survives restart. A crash never leaves the user without a last-known-good file.         |

Order: 1, 2, 3, 4, 5a, 5b, 6a, 6b. Slices 2 to 4 depend on 1. Slice 6b may pass 150 lines; if it does, split the shared acceptance code out first and say so at the top of the result.

Gap 4 (one bad playlist blocks all) is handled in 6a: per-source states are reported for all sources even when a candidate cannot be built.

## Owner questions

1. **Contract name.** Keep the on-disk version `source-enrollment/v2` and call the contract `sourceset/v2` in docs? Recommend yes. A rename breaks saved hashes for no gain.
2. **Where does binding identity go?** (A) Fold it into the guide logical ID, no contract change. (B) Add a field to `BuildIdentityInput`, which needs a new contract revision through the freeze process. Recommend (A) for Alpha.1; revisit (B) at the next contract revision.
3. **Maximum sources.** Keep 8 playlists, 8 guides, 16 MB total, and enforce in the store? Recommend yes. Bindings follow: at most 8.
4. **ALL with one playlist.** Allowed today. Treat it as equal to the explicit single binding? Recommend yes (this is the "simple" rule above).
5. **Headless accept in step 6.** Include slice 6b now, or leave acceptance to the browser step? Recommend include 6b. Without it a refreshed source never becomes the saved snapshot except by running guided setup again.
6. **Rename.** Accept that renaming a source (remove and add) changes the candidate identity once? Recommend yes. Making identity ignore labels would change today's hashes.
7. **Playlist unavailable.** Block the candidate (recommended) or build without that playlist and list the dropped channels for review? Recommend block. Dropping channels breaks "never drop a channel".
8. **Legacy hash promise.** Is "same hash as today" met by routing simple legacy sets through the single-source builder (recommended)? The alternative is to accept that a migrated v1 config gets a new hash once, on its first source-set build. Recommend routing: it needs no accepted-state migration. Still not proven; slice 5a adds the golden test.

## Later list (not this round)

- Unused `Refresh` keys (`CacheKey`, `ETag`, `LastModified`) are never filled.
- A second copy of the set file for recovery from corruption.
- Conditional fetch for enrolled public sources.
- The single-source and source-set routes give different hashes for the same bytes.
- Steps 7 to 10.

## Risks to frozen contracts

- **Guide-id v1.0.** No slice changes binding resolution by `tvg-id`. `Resolve-ChannelForgeM3UXmltvBinding` is not edited. No channel is dropped. `guide: null` stays.
- **raw-xmltv-occurrence/v2 and raw-m3u-occurrence/v2.** Readers and projections are not edited. The fingerprint changes only the opaque logical source ID of a guide in a non-simple set. Not verified: that nothing downstream (lineup history) depends on a guide logical ID staying the same across binding changes.
- **M3U entry byte format.** Untouched.
- **BuildIdentityInput schema (contract v7).** Not changed in option (A) of question 2.
- **Single-source behavior.** Not edited. Proven only by the golden hash test in slice 5a, which has not been written or run.

## Not verified

- No code or test was run. Every "built" or "gap" statement is from reading.
- Gap 1 and gap 4 follow from the code paths named, not from a run.
- That a conflict between two guides makes the candidate fail (read from the earlier EPG note and the export code path, not re-read here).
- That the pinned transport applies its caps to the enrolled-source path exactly as to provider sources.
