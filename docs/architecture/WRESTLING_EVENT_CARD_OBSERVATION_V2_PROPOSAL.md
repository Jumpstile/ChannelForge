# Wrestling event and match-card observations — v2 proposal

**Status: Unapproved design proposal.** This document and its synthetic schema/fixtures are not a production contract, adapter, or consumer API. `ChannelForgeExternalEvidenceObservation/v1` remains closed and unchanged. Normal architecture review and the source-access gate must pass before implementation.

## Recommendation

If Guide Intelligence needs match-card facts, add a versioned companion/successor observation: `ChannelForgeExternalEvidenceObservation/v2`. Its proposal shape links by exact `ObservationId` and `ProvisionalSubjectKey` to one complete, unchanged v1 event observation, then carries typed wrestling-card revision observations. It supplements the same canonical event truth layer; it does not create a wrestling event database, canonical bout identity, or a parallel acceptance path.

Existing v1 producers and consumers remain v1. No implicit upgrade, unknown-field tolerance, v1 alias, or consumer fallback. A future v2 validator must resolve and validate the referenced base using the existing v1 converter/schema and require an explicit v2-aware consumer.

## Proposed observation model

### Event identity

- The base v1 `ProvisionalSubjectKey` and `SourceRecordReference` identify the source's event assertion only. They remain hints to Guide Intelligence, not a ChannelForge `CanonicalEventId` or channel ID.
- Every card revision references the same provisional event key and the base event observation ID. Event lifecycle remains in the generic v1 event observation.
- A bout is a source-scoped match assertion under an event. Its optional `SourceMatchReference` is usable across revisions only when the source documents/stably supplies it and that claim has its own field-level evidence; otherwise keep the reference null and revisions uncorrelated. Do not derive a canonical `MatchId` from participants, title, or card position.
- Participant references/names remain source facts, not canonical competitor IDs. Roles distinguish individuals, teams, or other participants without assuming a two-person bout.

### Card disclosure and match facts

Each card revision is an observation snapshot with:

- source revision/reference when available; otherwise a deterministic adapter revision identity over normalized evidence, not a copied page body;
- source-data time (nullable), observation time, and fetch time kept distinct;
- `CardDisclosureState`: `Unknown`, `ExplicitlyUnannounced`, or `ItemsObserved`;
- explicit source-record evidence for `ExplicitlyUnannounced`; an empty match array alone never means “no card announced”;
- `Completeness`: `Unknown` unless the source explicitly claims a complete card. `ItemsObserved` never implies completeness;
- zero or more match observations with optional source match reference, status assertion, participants, stipulations, and card position. Each fact carries its own source-record reference and field-level provenance/timestamps.

An empty participant or stipulation list and a null card position mean no fact was observed in that snapshot, not that the bout has no participants/stipulation/order. Explicit “TBA” or equivalent remains a source assertion, not a default.

Participant substitutions, stipulation changes, position changes, and explicit bout cancellation create new observations/revisions; prior evidence is retained for comparison. A match absent from a later revision is **not** inferred removed or cancelled. `ExplicitlyCancelled` requires an explicit source assertion and its evidence reference. Event cancellation/postponement/rescheduling and bout cancellation are separate statuses with separate evidence.

### Source clocks

Use typed clock observations with a role (`EventLocalStart`, `BroadcastStart`, or `Unknown`), original displayed value, timezone-resolution state, optional IANA zone/offset, normalized UTC only when supported by explicit source evidence, and field-level source/observation/fetch provenance. An unknown zone leaves UTC null. Event-local and broadcast clocks are never substituted for each other. Generic event start/status facts remain in the v1 base; the v2 clock detail only preserves distinctions v1 cannot express.

### Availability separation

The card observation has no `Availability`, `Offering`, `Network`, market, or entitlement field. A separately corroborated network/service fact remains its own generic availability/network observation, with its own provenance and authorization. No offering evidence means availability is unknown; an event or card page alone does not establish carriage or entitlement.

## Versioning and compatibility

- Keep v1 schema, converter, output identity, and supported `FieldName` set untouched.
- V2 has its own discriminator/schema and converter. Each v2 card observation references a valid v1 event observation by `ObservationId`, source record, and provisional subject key; it does not reserialize or modify the v1 object.
- Consumers dispatch strictly on the explicit version. Existing consumers continue to accept only v1 until separately migrated and reviewed; they do not silently drop v2 card data.
- One production v2 payload represents one card revision. The synthetic fixture groups several such revision observations only to exercise transitions; production observations remain append-only and separately identifiable.
- V2 semantic identity includes the linked v1 event observation identity plus one source-scoped card revision/facts. Fetch and observation clocks remain provenance, not revision identity. Exact hashing/canonical ordering belongs in the later converter implementation review.
- Store/index card evidence only through the existing canonical event truth/storage lifecycle after review. Do not add a sports/wrestling-specific database or let a bout redefine channel identity.

## Issue mapping and gates

- **#29:** owns adapter/evidence contracts and the shared canonical Event model. Offline fixtures are appropriate now; a live adapter is not. Its written coverage/rights/quota/cost gate remains open.
- **#30:** may use card participants as schedule-matching evidence after explicit v2 consumption is reviewed. Card facts never auto-create or retarget a channel identity; ambiguity remains review evidence.
- **#175:** online adapters require an approved bounded source contract. This proposal is a future contract review, not permission to scrape or enrich guides. Accepted-state and source-set behavior are unchanged.
- **#191:** current accepted-XMLTV presentation work remains independent. No UI/taxonomy change is proposed; do not modify the reviewed PR #203 branch.

The AEW source-access gate is recorded in [#29](https://github.com/Jumpstile/ChannelForge/issues/29) and the [official wrestling source research for #191](https://github.com/Jumpstile/ChannelForge/issues/191#issuecomment-5958323753): site automation scope and cache/retention/display rights remain unresolved; public MCP is an access avenue, not authorization. No source content was fetched for this proposal.

## Preliminary internal architecture review

Self-review against the current contracts and architecture:

- **v1 closure:** pass by design; no v1 property or field is added.
- **Canonical truth:** pass by design; event identity is linked through v1 and the existing Guide Intelligence/canonical Event path. Card/bout IDs stay source-scoped.
- **Provenance and revision safety:** pass for the proposed shape; every source claim is revision- and field-evidenced, source clocks stay separate, and absence is not deletion evidence.
- **Availability:** pass by separation; no card observation infers a service or entitlement.
- **Remaining architecture risk:** a v2 envelope changes the adapter/consumer boundary and requires independent reviewer approval, explicit version dispatch, deterministic identity rules, and a storage/query impact check before any consumer ships. This self-review is not that approval.
- **Source gate:** fail/unknown for live ingestion until AEW coverage, automated-use, caching/retention/display, rate/quota, and cost terms are established under #29.

## Decisions for normal architecture review

1. Approve the companion/successor direction (`v2` references an unchanged v1 base plus card observations), or keep card detail adapter-private and defer Guide Intelligence integration. Recommendation: approve the v2 direction only after the following invariants are accepted.
2. Confirm identity policy: source match reference only for cross-revision grouping; otherwise no automatic bout correlation. Recommendation: fail closed.
3. Confirm card disclosure/completeness vocabulary and the rule that “unannounced” and “complete” require explicit evidence. Recommendation: adopt the rules above.
4. Confirm append-only revision lifecycle and independent event/bout status evidence. Recommendation: preserve each revision; missing items never imply cancellation.
5. Confirm the downstream Guide Intelligence owner and storage/query path before any v2 consumer. Defer consumer/storage approval until that owner and path are named; storage/index choices remain under #36, and #30 is only a possible future matching consumer after its own v2-aware review.

## Independent technical review recommendation — advisory, not approval

The independent design review recommends the v2 companion direction while keeping ordinary event identity/time/status on v1; fail-closed bout correlation unless a documented stable source reference has its own evidence; explicit evidence for unannounced/completeness claims; and append-only revisions where absence never implies cancellation. It recommends deferring any v2 consumer and its storage/query path until an owner and path are named. These recommendations are not formal architecture acceptance or product-owner approval.

The Product Owner/Engineering Manager owns the scope decision. Existing #191 owner dispositions identify @Jumpstile in that role; no independent architecture reviewer is currently assigned. Assign an independent formal reviewer through the existing architecture-proposal workflow before recording architecture acceptance.

After formal architecture acceptance and source rights, the next bounded implementation slice is one permitted AEW schedule-window adapter under #29. It emits ordinary v1 event assertions plus one linked v2 card observation per revision for report-only Guide Intelligence, with synthetic offline tests. It includes no #30 consumer or #191 UI work. Keep source-access rights as a separate gate; this proposal authorizes no live ingestion.
