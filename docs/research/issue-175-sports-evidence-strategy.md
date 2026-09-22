# Issue #175 Sports and External Evidence Strategy

## Status

Research-first proposal. No production adapter or shared canonical contract is authorized by this document.

Base: `cee646b25b80967741e7849a673709218cd06b69`

## Existing capability inventory

ChannelForge already has source-scoped `GuideEvidenceRecord` and `New-ChannelForgeGuideEvidence` contracts. They support provider display text, provider M3U metadata, XMLTV, AED-derived XMLTV/M3U, schedule sources, and accepted knowledge. Existing fields cover sport, league, participants, event type/status, canonical UTC times, source timezone, freshness, confidence, reason codes, volatile facts, and redaction.

Issue #121 already provides read-only native event-pattern inference. `GuideEventPatternRule` separates structured grammar, field candidates, timezone interpretation, evidence references, drift, cross-source assessment, confidence, review, publication state, and accepted-state safety. `GuidePatternExample` supports sports/event fields and safe fingerprints. Volatile facts are separately freshness- and contradiction-assessed.

Remote acquisition MUST reuse ADR 0014 bounded HTTPS transport and existing XMLTV/M3U cache machinery. No second downloader or arbitrary web scraper is proposed. IPTVBoss AED-derived XMLTV/M3U remains an optional evidence source, never a ChannelForge authority.

## Issue #121 coordination map

Issue #121 owns event-pattern semantics and read-only inference: provider display-text parsing, M3U metadata interpretation, single-team versus league/event scopes, AED bridge/import planning, structured extraction, drift detection, and CandidateOnly outputs.

This track owns source adapters, source-specific parsing, normalized sports/event observations, source relationship, field provenance, freshness, rate-limit behavior, and safe failure semantics.

Guide Intelligence owns comparison, conflict/gap detection, evidence aggregation, confidence/disposition, reports, proposals, enrichment, and all candidate/accepted-state boundaries. Adapters emit evidence only; they do not choose winners, mutate channel identity, publish guides, or change accepted state.

Temporary event metadata may change frequently. Durable channel identity MUST remain independent.

## Approved evidence classes

Priority order:

1. Official broadcaster/network schedules.
2. Official league schedules.
3. Official event-organizer schedules.
4. Approved trusted secondary schedules.
5. Provider/configured XMLTV evidence.
6. AED-derived XMLTV/M3U evidence.
7. Provider display text, M3U metadata, and inferred pattern evidence.
8. Accepted ChannelForge knowledge, explicitly identified as prior knowledge.

Every source declares `Authoritative`, `Independent`, `Mirror`, or `Unknown`. Mirrors do not count as independent corroboration. Enumeration order never resolves conflict.

## Adapter contract proposal

Proposed descriptor:

```text
EvidenceAdapterDescriptor
  AdapterId, ContractVersion, EvidenceClass, SourceRelationship
  TargetDomain, AllowedUrlPatterns, SupportedEntityTypes, SupportedEventTypes
  MaximumResponseBytes, MaximumDecompressedBytes, Timeout
  RedirectPolicy, RateLimitPolicy, RetryPolicy, CachePolicy, FreshnessPolicy
  ContentTypes, ParserVersion, RedactionPolicy, FailureCategories
```

Adapters MUST use existing bounded HTTPS transport; may tighten but not widen ADR 0014 limits; reject unsafe URLs, redirects, credentials, malformed/incomplete payloads, and oversized responses; validate complete content; preserve fetch/data timestamps; and return structured unavailable/failure results rather than partial evidence.

Failure categories remain distinct: invalid URL, unsafe destination, redirect rejected, timeout, rate limited, transport failure, HTTP status failure, response too large, unsupported content type, malformed/incomplete payload, parser validation failure, unavailable, stale, and cache failures.

## Normalized sports/event evidence proposal

Adapters should emit source-scoped observations, not merged canonical events:

```text
SportsEventObservation
  ObservationId, SourceId, AdapterId, SourceFamily, SourceRelationship, EvidenceClass
  Sport, League, LeagueAbbreviation, LeagueShortName, Season, Competition, Round
  EventIdentity, EventType, EventStatus
  HomeTeam, AwayTeam, SingleTeam
  Team abbreviations, nicknames, records
  Venue, Arena, City, State
  ScheduledStartUtc, UpdatedStartUtc, SourceTimezone, SourceTimeText
  Network, Channel, LiveState, Summary, Predictor, Odds
  FetchedAtUtc, SourceDataTimestampUtc, EvaluationInstantUtc
  FreshnessState, ReasonCodes, FieldProvenance, RedactedFields
```

Scheduled and updated starts are distinct. Provider availability windows are not event starts. Countdown/live tags are presentation derivatives. Odds and predictors are optional volatile evidence. Event identity and durable channel identity use separate namespaces.

## Field-level provenance and freshness

Every field requires source ID, adapter ID/version, evidence class, source relationship, observed/fetched timestamp, source data timestamp when available, freshness state, parser version, normalized value, safe original value where allowed, value fingerprint, and reason codes. A trustworthy event start proves only that field; it does not prove title, description, network, or channel assignment.

Freshness states are `Current`, `Stale`, `Unavailable`, and `Unknown`. Evaluation requires an injected evaluation instant, not wall-clock behavior in deterministic tests. TTLs are field/source specific: live state, network assignment, schedule time, and completed-event data need different windows. Stale evidence remains provenance but cannot silently become current evidence.

## Conflict and failure model

The system preserves disagreements rather than resolving them by source order. XMLTV versus official schedule, two official sources, recent schedule changes, moved networks, postponed/rescheduled/cancelled events, stale secondary schedules, and naming variants become explicit comparison inputs or contradiction groups for Guide Intelligence.

A failed adapter produces `SourceUnavailable`; it does not erase healthy evidence or accepted LKG. A disappeared event is not channel deletion evidence. Partial or malformed payloads are rejected entirely. No adapter writes accepted programmes, mappings, or channel identity.

## Rate limits and redaction

Each adapter declares per-host budget, minimum interval, concurrency, retryable statuses, bounded backoff, jitter policy, and cache reuse window. Initial implementation should be sequential with zero automatic retries unless the documented source requires bounded retry. Honor `Retry-After` only within the operation deadline.

Redact provider URLs/query strings, credentials, tokens, cookies, signed URLs, stream URLs, private paths, raw bodies, authorization headers, and cache validators outside cache-private metadata. Retain safe logical IDs, source labels, normalized event text, timestamps, fingerprints, parser versions, reason codes, and aggregate counts.

## Shared contract decision

A new shared contract is required and MUST be reviewed before production implementation:

`ChannelForgeExternalEvidenceObservation/v1`

Existing `GuideEvidenceRecord` is a strong downstream projection but does not fully define adapter identity/version, field-level provenance, source-data versus fetch time, per-field freshness, contradiction groups, parser version, updated start time, or event identity versus channel identity.

## First adapter shortlist and recommendation

Candidates:

- documented official league schedule feed;
- documented official broadcaster/network schedule feed;
- documented official event-organizer feed for combat sports/PPV;
- official ESPN feed only if a stable documented public contract is confirmed;
- approved trusted secondary schedule;
- existing AED-derived XMLTV/M3U bridge.

Recommended first production adapter: one bounded, documented official league schedule feed. It maximizes architectural value while exercising identity, start-time updates, postponed/rescheduled/cancelled states, freshness, provenance, XMLTV disagreement, unavailable responses, and rate-limit handling without prematurely coupling the contract to network presentation data. Combat-sports/event-organizer coverage should follow because it directly exercises Issue #121 UFC/PPV requirements.

## Safety disposition

No production adapter, accepted-state change, candidate-hash change, UI change, or merge is authorized. The next gate is ChatGPT review of `ChannelForgeExternalEvidenceObservation/v1`, followed by source-contract verification and redacted deterministic fixtures.

## Read-only candidate feed research

This section records source research only. It authorizes no adapter implementation and does not make any source an approved production dependency.

### Candidate 1: NHL.com schedule API

- **Organization/league:** National Hockey League.
- **Feed:** `https://api-web.nhle.com/v1/schedule/{date}`.
- **Public documentation:** The endpoint is publicly readable and returns structured JSON, but a stable first-party developer contract and published rate-limit policy were not located in this review. Treat the endpoint as a candidate requiring source-owner verification, not as a contract.
- **Authentication:** No credential was required for the inspected public request.
- **Event identity:** Numeric game ID, e.g. `2026010035`; season and game type are also present.
- **Time/status:** `startTimeUTC`, venue offsets/timezone, `gameState`, and `gameScheduleState`.
- **Participants:** Home/away team IDs, names, place names, abbreviations, and common names.
- **Venue:** Venue name and timezone are present.
- **Network:** `tvBroadcasts` contains network, market, country, and sequence fields when available.
- **Machine readability:** Strong JSON response; weekly schedule envelope contains date and game arrays.
- **Pagination:** Date-based schedule window with next/previous dates; no page token observed.
- **Rate limits/cache:** No published policy was verified. ChannelForge would need conservative sequential requests, bounded cache reuse, and no automatic retry by default.
- **Freshness:** The feed is schedule-oriented and can expose future state plus network changes, but source update timestamps were not observed in the inspected payload.
- **Operational complexity:** Low transport complexity; medium contract risk because public accessibility is clearer than formal API support.
- **ChannelForge transport:** Compatible with existing bounded HTTPS machinery if the host, path, response-size, and content-type policy are explicitly approved.

### Candidate 2: MLB Stats API

- **Organization/league:** Major League Baseball.
- **Feed:** `https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=YYYY-MM-DD`.
- **Public documentation:** The live official endpoint is publicly readable. A stable public first-party developer portal and official rate-limit commitment were not verified; much available endpoint documentation is community-maintained. This is useful evidence but a contract-support risk.
- **Authentication:** No credential was required for the inspected public request.
- **Event identity:** Numeric `gamePk` plus `gameGuid`, with links to the game feed.
- **Time/status:** `gameDate`, `officialDate`, status codes/states, `rescheduledFrom`, and `rescheduledFromDate` were present in the inspected response.
- **Participants:** Team IDs, names, abbreviations, short names, location names, league/division, and home/away roles.
- **Venue:** Venue ID and name.
- **Network:** Broadcasts are available through documented/community-described hydration paths, but were not present in the inspected non-broadcast response; network support requires separate verification.
- **Machine readability:** Strong JSON; date and season filters; response reports total games.
- **Pagination:** Date/range/team/league filters are available; no page-token pagination was observed for the inspected schedule request.
- **Rate limits/cache:** No official public limit was found in this review. Conservative caching and backoff are required.
- **Freshness:** Rescheduling fields demonstrate useful update semantics; no general source revision timestamp was observed.
- **Operational complexity:** Low transport complexity; medium-to-high contract risk because endpoint semantics are widely used but formal public support and rate limits are unclear.
- **ChannelForge transport:** Compatible with existing bounded HTTPS machinery, subject to host/path approval and response bounds.

### Candidate 3: NBA public schedule JSON

- **Organization/league:** National Basketball Association.
- **Feed candidate:** NBA schedule JSON under `data.nba.com`, including season schedule resources used by public clients.
- **Public documentation:** No stable official public developer contract for the schedule resource was verified. Commonly cited schemas and URLs are community-described or client-discovered.
- **Authentication:** Public access may work without credentials, but this was not treated as an approved guarantee.
- **Event identity/time/status/participants/venue/network:** Likely available in client schedule payloads, but exact fields, revision semantics, and status guarantees were not verified from an official contract.
- **Machine readability:** JSON candidate, but undocumented endpoint behavior.
- **Pagination:** Not established.
- **Rate limits/cache:** Not published or verified.
- **Freshness/stability:** Client-facing endpoint stability and permitted automated use remain unclear.
- **Operational complexity:** Higher legal and operational risk than the NHL and MLB candidates because the source is effectively undocumented.
- **ChannelForge transport:** Technically plausible, but not ready for approval without first-party contract and use-policy evidence.

### Candidate comparison and recommendation

The NHL feed is the strongest first research candidate based on the inspected payload: it exposes stable-looking game IDs, UTC start times, explicit schedule/game state, venue, participants, abbreviations, and broadcast networks in one response. It directly exercises the generic observation boundary without requiring credentials or browser automation.

The recommendation is therefore updated from the earlier generic league-feed recommendation to:

> **Recommended first adapter candidate: NHL.com public schedule feed, subject to first-party contract, permitted-use, and rate-limit verification before implementation.**

MLB remains a close alternative and has stronger observed rescheduling fields, but the inspected evidence did not establish a clearer supported public contract or rate-limit policy. NBA is deferred because the candidate schedule resources are insufficiently documented.

## Candidate source-to-observation mapping: NHL

This is a design mapping only; no mapper is implemented.

| NHL source field                             | Generic observation field                                          |
| -------------------------------------------- | ------------------------------------------------------------------ |
| `id`                                         | `ProvisionalSubjectKey` / event-id field observation               |
| `startTimeUTC`                               | scheduled-start field observation                                  |
| revised schedule value, if later exposed     | updated-start field observation                                    |
| `gameState`                                  | event-status field observation                                     |
| `gameScheduleState`                          | schedule-status field observation                                  |
| `awayTeam.id`, `homeTeam.id`                 | participant identity field observations                            |
| `awayTeam.commonName`, `homeTeam.commonName` | participant name observations                                      |
| `awayTeam.abbrev`, `homeTeam.abbrev`         | participant abbreviation observations                              |
| `awayTeam.placeName`, `homeTeam.placeName`   | participant location observations                                  |
| `venue.default`                              | venue field observation                                            |
| `venueTimezone` and offsets                  | source-timezone/time-context observations                          |
| `tvBroadcasts[].network`                     | network/channel-assignment field observation                       |
| `season`, `gameType`, `periodDescriptor`     | competition/context observations, subject to generic-field review  |
| `gameCenterLink`                             | safe source reference only; not a credential or canonical identity |

Team nicknames, records, logos, radio links, ticket links, countdowns, odds, predictors, and presentation labels remain outside mandatory generic v1 unless separately reviewed.

## AED/IPTVBoss classification

| AED concept                                      | Classification                                                                    |
| ------------------------------------------------ | --------------------------------------------------------------------------------- |
| title, subtitle/title2..title10, summary         | Generic observed text where sourced; otherwise Guide Intelligence inference input |
| team1/team2 and league/competition labels        | Generic participants/competition observations when directly sourced               |
| team abbreviation, location, arena, city/state   | Generic participant/venue observations when directly sourced                      |
| single-team and league/event scope               | Sports-adapter-specific context plus Guide Intelligence inference input           |
| sports/league AED selection and ESPN+ visibility | Guide Intelligence inference/input policy, not adapter authority                  |
| AED defaults and fallback chains                 | Guide Intelligence/source-selection behavior; not generic observation fields      |
| live tag and countdown                           | Presentation-only derivatives from observed status/time                           |
| predictor and odds                               | Sports-specific volatile evidence; not mandatory generic v1                       |
| record and nickname                              | Sports-specific enrichment; not mandatory generic v1                              |
| future AED JSON import                           | Future compatibility/import field set, requiring a separate reviewed mapping      |

## Evidence boundary after shared-contract reconciliation

The accepted shared boundary is `ChannelForgeExternalEvidenceObservation/v1`, implemented by the Guide Intelligence OMP. This track must emit no implementation of that contract and must not redefine it. Sports-specific source facts remain adapter-side until a future contract review generalizes them. Adapters do not assign canonical identity, confidence, contradiction groups, review disposition, eligibility, or accepted state.

## Source Governance / Production Dependency Gate

This gate separates technical accessibility from production eligibility. A public JSON response is not permission to automate, store, redistribute, or depend on a source.

### NHL: `api-web.nhle.com`

- **Endpoint control:** First-party NHL-controlled domain relationship is strongly indicated by the official NHL service and response branding, but a dedicated ownership statement for the subdomain was not located.
- **First-party documented:** No public developer/API contract for `api-web.nhle.com` was located.
- **First-party terms supported:** NHL Terms of Service, updated October 29, 2025, apply to NHL.com services. They prohibit unauthorized spidering, scraping, harvesting, or other unauthorized automated means; prohibit unreasonable infrastructure load; limit NHL content to personal, non-commercial use unless permission is obtained; and prohibit copying, distribution, storage, or exploitation without authorization.
- **Automated use:** `NOT PERMITTED WITHOUT SEPARATE AUTHORIZATION`. The first-party Terms prohibit unauthorized spidering, scraping, harvesting, and other unauthorized automated means to compile information. No API-specific authorization overriding or qualifying those Terms was found.
- **Authentication:** No credential was required for the inspected schedule request. This is observed behavior, not an authorization grant.
- **Rate-limit policy:** No published API rate limit was found.
- **Caching policy:** No API-specific caching policy was found. General terms create storage and use restrictions that require written clarification before caching beyond transient operational handling.
- **Storage/redistribution:** General terms restrict copying, distributing, storing, modifying, and exploiting NHL content without authorization. ChannelForge evidence retention and redistribution therefore require written permission or a clearly applicable license.
- **Versioning/stability:** No public versioning or stability commitment was found.
- **Observed technical quality:** High. The response contains numeric game IDs, UTC starts, schedule/game states, participants, venue/timezone, and broadcast networks.
- **Production eligibility:** `NO — HOLD`. Requires NHL written/source-owner confirmation covering API use, automated retrieval, storage, caching, and permitted internal evidence use.
- **Evidence:** [NHL Terms of Service](https://www.nhl.com/info/terms-of-service), Sections 1, 2, and 7; observed `https://api-web.nhle.com/v1/schedule/{date}` response.

### MLB: `statsapi.mlb.com`

- **Endpoint control:** Official MLB domain and MLB copyright/branding are present.
- **First-party documented:** `YES, DOCUMENTATION EXISTS; API SUPPORT AND ACCESS TERMS REMAIN UNCLEAR`. Current MLB Stats API documentation is hosted at `docs.statsapi.mlb.com`, with first-party navigation to documentation and API reference. This corrects the earlier statement that no first-party documentation existed. It does not establish unrestricted public production use.
- **Terms of Use:** MLB terms apply to MLB Digital Properties. They prohibit automated scripts from collecting information from or interacting with MLB Digital Properties, prohibit unreasonable infrastructure load, restrict reproduction/distribution, and state that MLB may change or discontinue databases, features, or content.
- **Automated use:** `NO/UNCLEAR FOR UNAUTHORIZED USE`. The public endpoint can respond without credentials, but the general terms expressly prohibit automated scripts absent authorization.
- **Authentication:** Inspected endpoint required no credential; first-party documentation includes a registration/login path for fuller API access. Exact production authorization model remains unresolved.
- **Rate-limit policy:** No public rate-limit commitment was found.
- **Caching policy:** No API-specific cache permission was found; general terms restrict storage and redistribution.
- **Versioning/stability:** Documentation exists, but no public SLA, version-retention, or endpoint stability commitment was located.
- **Observed technical quality:** High. Schedule responses expose `gamePk`, `gameGuid`, UTC game date, status, rescheduling fields, participants, and venue.
- **Production eligibility:** `NO — UNSUPPORTED_PUBLIC_ENDPOINT_CANDIDATE` until MLB confirms automated-use authorization, API terms, rate limits, caching, and permitted evidence retention.
- **Evidence:** [MLB Stats API documentation](https://docs.statsapi.mlb.com/getting-started/introduction-to-stats-api), [MLB API reference](https://docs.statsapi.mlb.com/reference), [MLB Terms of Use](https://www.mlb.com/official-information/terms-of-use), observed `https://statsapi.mlb.com/api/v1/schedule`.

### NBA: public schedule/client resources

- **Endpoint control:** NBA-controlled public web properties are official.
- **First-party documented:** The NBA Developer Portal is first-party documented, but access is limited to NBA teams and official NBA business partners. The public client-discovered schedule resources are not an approved general public API contract.
- **Automated use:** The NBA Terms of Use restrict copying, reproduction, distribution, and use of NBA content; the developer portal requires proper affiliation. Public client endpoint access does not establish permission.
- **Observed technical quality:** Candidate JSON schedule resources may contain useful schedule data, but exact fields, update semantics, support, and stability were not verified against a general public contract.
- **Production eligibility:** `NO — NOT_READY_FOR_CHANNELFORGE_ADAPTER`.
- **Evidence:** [NBA Developer Portal](https://developerportal.nba.com/), [NBA Terms of Use](https://www.nba.com/termsofuse), especially Sections 1, 7, 9, and 14.

### Additional candidate: Sportradar

Sportradar is a reputable permitted secondary sports-data provider rather than an official league source. Its developer documentation describes authenticated API access, free-trial/sandbox access, product-specific quotas, and commercial plans. Search evidence indicates rolling 30-day quotas and query-per-second limits, with pricing and redistribution rights governed by the selected product agreement. It is technically more governable than undocumented league web-client endpoints, but it introduces credentials, licensing cost, account enrollment, and a new sensitive configuration boundary that ChannelForge does not currently support for normal source enrollment.

Classification:

- documented contract: `YES`;
- authentication: required API key/account;
- free tier: trial/sandbox, not assumed production-eligible;
- rate limits: product/account-specific and documented;
- sports coverage: MLB, NBA, NHL, NFL and other sports depending on product;
- production status: `ALTERNATIVE, NOT SELECTED`;
- evidence: [Sportradar developer portal](https://developer.sportradar.com/), [account/rate-limit documentation](https://developer.sportradar.com/getting-started/docs/your-account), [terms](https://developer.sportradar.com/apps/tos).

Sportradar should be considered only after a credential-aware enrollment and licensing design is separately approved. No credentials are stored or implemented by this track.

### Production gate result

| Candidate           | Technically accessible | Technically useful |                 Documented |               Supported |               Permitted | Production eligible |
| ------------------- | ---------------------: | -----------------: | -------------------------: | ----------------------: | ----------------------: | ------------------: |
| NHL public schedule |                    Yes |                Yes |                         No |                 Unknown | Unclear / no by default |                  No |
| MLB Stats API       |                    Yes |                Yes |          Yes, current docs |                 Unclear | Unclear / no by default |                  No |
| NBA client schedule |               Possibly |         Unverified | No general public contract |                      No |              No/unclear |                  No |
| Sportradar          |           Credentialed |                Yes |                        Yes | Yes under product terms |      Contract-dependent |             Not yet |

No current candidate passes the production dependency gate. The earlier NHL recommendation is technically retained but operationally withdrawn pending written source-contract verification. This is not adapter design authorization.

## MLB Registered API Authorization Investigation

### Current first-party evidence

MLB now has a first-party Stats API documentation site:

- [Stats API documentation](https://docs.statsapi.mlb.com/)
- [Getting started](https://docs.statsapi.mlb.com/getting-started/introduction-to-stats-api)
- [API reference](https://docs.statsapi.mlb.com/reference)

The first-party self-registration page is also publicly inspectable:

- [MLB Stats API self-registration](https://inside.mlb.com/UserRegistrationForm/?GROUP=StatsAPI)

The registration page requires a user to enter a User ID/email and states that MLB will email the application status. No registration was performed and no terms were accepted.

### Access distinction

`PUBLIC_ENDPOINT_ACCESS` and `REGISTERED_API_ACCESS` must remain separate:

- **Public endpoint access:** `statsapi.mlb.com` responds without credentials in the inspected schedule request. MLB's general Terms prohibit automated scripts collecting from or interacting with MLB Digital Properties, so public accessibility is not permission.
- **Registered API access:** MLB provides first-party documentation and a registration/access workflow. The public pages inspected do not expose the post-registration API agreement, exact credentials, quotas, caching permissions, derived-data retention rules, or redistribution rights.

The registration page and documentation establish a credible official API path, but not enough evidence to approve ChannelForge's intended automated schedule retrieval and evidence retention. Registration would require user action and potentially acceptance of terms that cannot be inspected without proceeding.

### MLB decision

`MLB_API_REQUIRES_USER_REGISTRATION_REVIEW`

Required user-side evidence before approval:

1. complete MLB's registration personally;
2. review and retain the API-specific terms or access agreement presented;
3. confirm authentication/key requirements;
4. confirm automated schedule retrieval is permitted outside MLB-owned applications;
5. confirm quotas/rate limits;
6. confirm caching, derived evidence retention, and redistribution restrictions;
7. confirm version/deprecation policy.

No registration, credential acquisition, or legal-term acceptance was performed by ChannelForge.

The technical MLB candidate remains strong, but it is not production-eligible until those facts are supplied and reviewed.

## Documented Multi-Sport Provider Comparison

### Sportradar

Sportradar publishes a developer portal, API documentation, terms, product catalog, and account/rate-limit documentation.

- **Product coverage:** Separate products are available by sport/league. The account documentation explicitly describes MLB Base and product packages; the marketplace covers MLB, NBA, NHL, NFL, and other sports. A single account/application can hold multiple subscribed products, but product-by-product entitlement must be confirmed.
- **Authentication:** Account plus application API key, supplied in request headers.
- **Trial:** 30 days; default trial limit documented as 1,000 requests per rolling 30 days and 1 QPS. Trial data is intended for evaluation and access expires unless extended or converted.
- **Production:** Production access is reserved for customers; commercial terms are required.
- **Pricing:** No universal public production price was found. Product pricing is marketplace/account-specific or sales-negotiated.
- **Schedule/status fields:** Product-specific docs expose schedule/event resources; exact field coverage varies by sport product and must be checked before selection.
- **Broadcast fields:** Broadcast products/data are separate and may not be included in the base schedule package.
- **Quotas:** Rolling 30-day product quota and QPS limit, visible in the account; limits differ by product/access level.
- **Storage/redistribution:** Governed by product terms and B2B agreement; not assumed permitted for ChannelForge evidence retention or redistribution.
- **Personal-user fit:** Better documented than public league client endpoints, but the 30-day trial is not a production plan and commercial access may exceed a personal budget. Credential setup is additional onboarding friction.
- **ChannelForge fit:** Strong multi-sport breadth and explicit operational controls; requires a future credential-aware source enrollment and licensing decision.

Evidence:

- [Sportradar first-call/access documentation](https://developer.sportradar.com/getting-started/docs/make-your-first-call)
- [Sportradar account, products, trials, and limits](https://developer.sportradar.com/getting-started/docs/your-account)
- [Sportradar terms](https://developer.sportradar.com/apps/tos)

### SportsDataIO

SportsDataIO has a clearly documented multi-sport API model and is the strongest personal-user comparison found:

- **Coverage:** NFL, NBA, MLB, NHL, college football, college basketball, golf, NASCAR, plus broader commercial products.
- **Authentication:** Subscription/API key.
- **Free trial:** Self-serve, no credit card; structurally realistic but data is scrambled and not usable for production evidence.
- **Discovery Lab:** Real data, next-day delayed, eight sports including MLB/NBA/NHL/NFL; published tiers are Free (last season), $99/month or $599/year for Fantasy or Odds, and $149/month or $899/year for Fantasy + Odds.
- **Limits:** Discovery Lab provides 100–1,000 calls/day depending on tier.
- **Schedule/status/broadcasts:** Per-sport API documentation and data dictionaries exist; exact broadcast fields and event-state coverage require package-level verification.
- **Storage/redistribution:** Discovery Lab is explicitly not licensed for commercial redistribution. Other products require their own terms.
- **Personal-user fit:** More practical than Sportradar for a personal delayed-schedule use case, but $99/month is material and the free tier is historical only.
- **ChannelForge fit:** Strong documented multi-sport shape and simpler onboarding than a league-by-league adapter set; still requires credentials and a licensing/configuration decision.

Evidence:

- [SportsDataIO developer access and products](https://sportsdata.io/developers)
- [SportsDataIO API resources](https://sportsdata.io/developers/apis)

### Comparison

| Candidate           | Public contract                                      | Auth                                | Multi-sport             | Published limits | Personal fit                             | Current status                               |
| ------------------- | ---------------------------------------------------- | ----------------------------------- | ----------------------- | ---------------- | ---------------------------------------- | -------------------------------------------- |
| NHL public endpoint | No                                                   | None observed                       | NHL only                | No               | Technically easy, governance failure     | Not permitted without separate authorization |
| MLB Stats API       | First-party docs; post-registration terms unresolved | Registration/access likely required | MLB only                | Not verified     | Promising but user review required       | Registration review required                 |
| NBA public schedule | No general public contract                           | Unclear                             | NBA only                | No               | Poor governance fit                      | Not ready                                    |
| Sportradar          | Yes                                                  | API key/account                     | Broad, product-specific | Yes              | Medium/low until pricing known           | Future credentialed candidate                |
| SportsDataIO        | Yes                                                  | API key/subscription                | Broad                   | Product-specific | Medium; delayed personal plan documented | Future credentialed candidate                |

No source is currently approved for adapter implementation. MLB is the best league-controlled candidate pending user registration review. SportsDataIO is the most practical documented multi-sport personal-user fallback found, while Sportradar is the stronger enterprise-grade breadth candidate.

## Global Sports Evidence Provider Pivot

The primary research path is now multi-sport providers, not one adapter per league. League APIs remain specialist, corroborating, or fallback sources. All provider outputs must eventually enter the Guide Intelligence boundary through `ChannelForgeExternalEvidenceObservation/v1`; provider identity must not leak into Guide Intelligence.

### Global media and score aggregators

| Provider      | Region          | Structured access finding                                                                                                                             | Classification                         | ChannelForge suitability                                         |
| ------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------------- |
| ESPN          | Global/US       | Public ESPN JSON endpoints are used by ESPN clients, but no current public developer contract, support, rate limit, or automated-use grant was found. | FIRST_PARTY_STRUCTURED_BUT_UNSUPPORTED | Technically broad; not production-eligible without authorization |
| BBC Sport     | UK/global       | No public BBC Sport developer API for schedule/event data was found; platform APIs are restricted.                                                    | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| Sky Sports    | UK/global       | No public supported schedule API or developer contract found.                                                                                         | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| DAZN          | Global/regional | No public developer API; partner/internal data feeds are not a public integration path.                                                               | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| Flashscore    | Global          | Broad web coverage, but no documented public API; community scraping/wrappers are not acceptable.                                                     | NOT_SUITABLE                           | Reject arbitrary scraping                                        |
| Sofascore     | Global          | Public client JSON endpoints are widely used, but undocumented and unsupported; no permitted production API contract found.                           | FIRST_PARTY_STRUCTURED_BUT_UNSUPPORTED | Research only, not production                                    |
| OneFootball   | Global/Europe   | Public site/app coverage is broad, but no documented general schedule API suitable for external production use was verified.                          | MEDIA_WEB_ONLY                         | Not suitable pending authorization                               |
| LiveScore     | Global          | No documented public API contract found; public web/app data is not sufficient evidence.                                                              | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| CBS Sports    | US              | No documented general public multi-sport schedule API found.                                                                                          | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| TSN/Sportsnet | Canada          | Official schedule/media sites exist, but no general public API contract found.                                                                        | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| Fox Sports    | US              | No documented general public multi-sport schedule API found.                                                                                          | MEDIA_WEB_ONLY                         | Not suitable                                                     |
| beIN Sports   | Regional/global | No documented public schedule API suitable for external integration found.                                                                            | MEDIA_WEB_ONLY                         | Not suitable                                                     |

Media brands are valuable corroborating authorities when their schedules are directly available through an approved channel, but their public web JSON is not automatically an approved adapter source. The current investigation found no ESPN-like media aggregator that meets the full supported/permitted production gate.

### Documented multi-sport providers

#### SportsDataIO Global Sports API

First-party materials describe a Global Sports API launched for 2026, with a consistent model across sports and leagues, REST/JSON documentation, data dictionaries, and OpenAPI resources. The product page describes schedules, live scores, and results across hundreds of competitions. The developer documentation describes a roadmap toward 100+ sports and the current API resources describe dozens of competitions; separate marketing material cites 950+ global leagues. These figures are product claims at different maturity levels and must not be treated as guaranteed coverage until verified in a subscribed product.

- **Global coverage:** Broad international, multi-sport coverage; current breadth and competition entitlement are product-dependent.
- **Sports count:** Documentation claims 100+ sports as the build-out target; current available coverage is smaller and must be confirmed.
- **Competitions:** Dozens initially; marketing claims 950+ global leagues. Verify the actual requested competition in the coverage/product catalog.
- **Schedule data:** Schedules, live scores, and results; global model favors breadth over deep sport-specific detail.
- **Status data:** Live/result state is available; postponed/cancelled/rescheduled semantics and update timing require per-sport verification.
- **Broadcast data:** Not established as a Global Sports API guarantee. Treat network/streaming assignments as a separate verification item.
- **API model:** REST/JSON with consistent schema, documentation, data dictionary, and OpenAPI resources.
- **Authentication:** API subscription key.
- **Rate limits:** Product-specific. Discovery Lab documentation publishes 100–1,000 calls/day depending on tier; Global Sports API commercial limits are not publicly fixed.
- **Pricing:** No public Global Sports API price found. Discovery Lab real-data personal tiers start at $99/month or $599/year for a single capability, with $149/month or $899/year combined Fantasy + Odds; this is not necessarily Global API pricing.
- **Personal user fit:** Best documented personal-user direction found, but cost and broadcast-field coverage remain blockers.
- **ChannelForge fit:** High potential for a primary breadth provider if schedule/status/broadcast fields and terms are confirmed. One provider could reduce adapter proliferation substantially.

Evidence: [SportsDataIO Global API](https://sportsdata.io/global-api), [SportsDataIO developer access](https://sportsdata.io/developers), [API resources](https://sportsdata.io/developers/apis).

#### Sportradar general/global APIs

Sportradar documents League Specific and General Sport API families. General Sport APIs use consistent structures across global American football, baseball, basketball, ice hockey, soccer, and other sports. The developer portal includes coverage information, REST/JSON/XML documentation, schedules, event endpoints, and a coverage matrix.

- **Global coverage:** Broad international coverage; package and competition entitlements vary.
- **Sports count:** Broad multi-sport catalog; exact count is product/catalog dependent rather than one universal API.
- **Competitions:** Soccer documentation cites 650+ competitions in one package; coverage matrix is authoritative for a selected product.
- **Schedule data:** Documented schedule/event endpoints. Soccer schedule publication is described as within four hours of official confirmation and up to one month ahead depending on competition.
- **Status data:** General and league-specific event states, results, and live updates; exact postponement/cancellation semantics are product-specific.
- **Broadcast data:** Documented in some products, including NBA broadcasts and NFL schedule broadcast information; not guaranteed across every global package.
- **API model:** Versioned REST endpoints with JSON/XML responses and API-key authentication.
- **Authentication:** Account/application API key.
- **Rate limits:** Rolling 30-day quota and QPS limit; visible per product/account. Trial defaults documented as 1,000 requests/30 days and 1 QPS.
- **Pricing:** Production pricing is not publicly transparent; product/customer agreement or sales process required.
- **Personal user fit:** Low. Sportradar states its APIs are a B2B service and not intended to be called directly from a client application. Trial access is for evaluation, not a personal production entitlement.
- **ChannelForge fit:** High technical breadth, low beginner/product fit unless ChannelForge later obtains an approved server-side B2B account and credential-aware enrollment.

Evidence: [Sportradar getting started](https://developer.sportradar.com/getting-started/docs/get-started), [coverage information](https://developer.sportradar.com/getting-started/docs/coverage-information), [account and limits](https://developer.sportradar.com/getting-started/docs/your-account), [first call and B2B access note](https://developer.sportradar.com/getting-started/docs/make-your-first-call).

## Global coverage matrix

The following is a research coverage expectation matrix, not a claim that every row is included in every product tier. `V` means likely/documented product coverage requiring package verification; `U` means unresolved; `—` means not a practical current target.

| Competition/sport           | SportsDataIO Global | Sportradar Global/General |                   Media aggregators |
| --------------------------- | ------------------: | ------------------------: | ----------------------------------: |
| NFL                         |                   V |                         V |                    ESPN/unsupported |
| MLB                         |                   V |                         V |                    ESPN/unsupported |
| NBA                         |                   V |                         V |                    ESPN/unsupported |
| NHL                         |                   V |                         V |                    ESPN/unsupported |
| NCAA football               |            V/verify |                  V/verify |                    ESPN/unsupported |
| NCAA basketball             |            V/verify |                  V/verify |                    ESPN/unsupported |
| Premier League              |                   V |                         V | Broad web coverage, no approved API |
| Champions League            |            V/verify |                         V | Broad web coverage, no approved API |
| La Liga                     |                   V |                         V | Broad web coverage, no approved API |
| Bundesliga                  |                   V |                         V | Broad web coverage, no approved API |
| Serie A                     |                   V |                         V | Broad web coverage, no approved API |
| Ligue 1                     |                   V |                         V | Broad web coverage, no approved API |
| MLS                         |                   V |                         V |                    ESPN/unsupported |
| Formula 1                   |            V/verify |                  V/verify |                      Media web only |
| NASCAR                      |                   V |                  V/verify |                      Media web only |
| IndyCar                     |            V/verify |                  V/verify |                      Media web only |
| ATP                         |            V/verify |                         V |                      Media web only |
| WTA                         |            V/verify |                         V |                      Media web only |
| Grand Slam tennis           |            V/verify |                         V |                      Media web only |
| PGA/major golf              |                   V |                         V |                      Media web only |
| UFC                         |            V/verify |                  V/verify |                      Media web only |
| Boxing                      |            V/verify |                  V/verify |                      Media web only |
| Cricket                     |            V/verify |                         V |             Regional media web only |
| Rugby union                 |            V/verify |                         V |             Regional media web only |
| Rugby league                |            V/verify |                         V |             Regional media web only |
| International basketball    |            V/verify |                         V |                      Media web only |
| International hockey        |            V/verify |                         V |                      Media web only |
| Olympics/multi-sport events |                   U |        U/product-specific |                      Media web only |

For each provider, the required verification dimensions remain: future schedule horizon, event ID, participants, start/end, status changes, venue, broadcast/network/service, historical/live support, and geographic restrictions. Coverage breadth alone is not enough.

## Broadcast assignment value

Broadcast/network assignment is a first-class selection criterion. The provider must be tested for:

- TV network and streaming service;
- regional versus national market;
- country/market;
- alternate feeds and multiple broadcasters;
- ESPN+ or equivalent service assignments;
- whether assignments are schedule-time facts or merely editorial labels.

Sportradar documents broadcast fields in selected league products, including NBA and NFL examples, but does not establish universal broadcast coverage in General Sport APIs. SportsDataIO Global API broadcast coverage remains unverified. This is the largest unresolved difference between schedule breadth and Guide Intelligence value.

## Recommended multi-source strategy

Normal Guided Setup MUST require one approved sports provider, not two paid subscriptions:

```text
Primary approved global provider
    + XMLTV
    + provider M3U metadata
    + accepted ChannelForge history
    + optional secondary independent global provider
    + approved specialist source only for material uncertainty
        -> ChannelForgeExternalEvidenceObservation/v1
        -> Guide Intelligence comparison/corroboration/conflict/proposal
```

ChannelForge supports multiple providers, but the default product path is one required provider. A second global provider is optional and should be enabled only when its incremental corroboration value justifies cost, credentials, and terms. Provider identity remains provenance and does not leak into Guide Intelligence.

## SportsDataIO Global Schema Verification

`SPORTSDATAIO_SCHEMA_FULLY_REVIEWED=YES`

The complete current first-party Global API documentation was reviewed, including the introductory catalog, event-feed, schedule, results, live-state, team, athlete, venue, competition, phase, season, participant, and data-dictionary material. The documentation repeatedly shows `Key not yet enabled` for catalog and feed endpoints; no anonymous current-account catalog was available.

The provider's current public catalog is not anonymously enumerable from the documentation. Therefore, the following requested coverage is **not entitlement-confirmed** without an enabled key or written catalog response:

| Requested coverage                                                           | Current evidence classification                                                                   |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| NFL, MLB, NBA, NHL                                                           | Likely product target; Global entitlement not confirmed                                           |
| NCAA football, NCAA basketball                                               | Unresolved                                                                                        |
| Premier League, Champions League, La Liga, Bundesliga, Serie A, Ligue 1, MLS | Soccer is explicitly in the Global API examples; each competition entitlement remains unconfirmed |
| Major international soccer competitions                                      | Unresolved                                                                                        |
| Formula 1, NASCAR, IndyCar                                                   | Unresolved                                                                                        |
| ATP, WTA, Grand Slams                                                        | Tennis is explicitly in the Global API examples; competition-level entitlement unconfirmed        |
| PGA/major golf                                                               | Unresolved                                                                                        |
| UFC, boxing                                                                  | Unresolved                                                                                        |
| Cricket, rugby union, rugby league                                           | Unresolved                                                                                        |
| International basketball, international hockey                               | Unresolved                                                                                        |

“100+ sports,” “hundreds of competitions,” and “thousands of leagues” are first-party product claims, not verified current entitlements for a ChannelForge account. They MUST NOT be used as coverage guarantees.

### Event model

The current Global data dictionary documents:

- `GlobalSportsEventId`: unchanging 32-bit event identifier;
- `GlobalSportsPhaseId`: unchanging phase identifier;
- `Type`: sport type;
- `Name`;
- nullable `StartDate`;
- `Status` and `StatusDescription`;
- `Updated`;
- `LiveCoverage`;
- nullable `Attendance`;
- `Closed`;
- `Venue`;
- `RoundInfo`;
- sport-specific `EventState`;
- sport-specific `Participants`;
- optional `StatusComment`;
- sport-specific `Format`.

Participants have unchanging `GlobalSportsParticipantId`, name, type, side, and sport-specific results. Competition records have unchanging `GlobalSportsCompetitionId`; seasons and phases have separate stable identifiers.

The documentation does **not** expose a separate scheduled-end or duration field in the common Event model. EventState includes actual start/end fields where supported, but this is sport-state data, not a guaranteed future schedule duration.

`StartDate` is the scheduled start field. No separate `UpdatedStartDate` or revision-history field is documented. `Updated` is the record update timestamp, not explicitly a start-time revision timestamp.

The stable event-ID claim implies that a schedule correction should retain `GlobalSportsEventId`, but postponed/rescheduled transition behavior and TBD encoding are not documented. Current evidence is insufficient to assert whether a postponed event remains in place, is removed and re-emitted, or receives a replacement record. TBD start representation is also unresolved; `StartDate` is nullable, so null is possible, but not confirmed as the provider's only TBD representation.

### Future schedule horizon

The public Global documentation provides date and phase schedule endpoints but does not publish a normal future horizon, sport-specific horizon, incremental-ingestion SLA, network-assignment timing, or tournament participant-availability policy. Those are provider questions requiring enabled-account samples or written support answers.

Current disposition:

- future horizon: `UNKNOWN`;
- horizon by sport: `UNKNOWN`;
- incremental schedule arrival: technically plausible, not documented;
- broadcast assignment timing: `UNKNOWN`;
- postseason/tournament events before participants are known: `UNKNOWN`.

ChannelForge SHOULD use daily schedule refresh plus targeted near-term refresh only after these values are confirmed.

### Broadcast and streaming gap

No Global Sports API event or data-dictionary field for TV network, streaming service, broadcaster, market/country, national/regional designation, alternate feed, or multiple broadcaster assignment was found. ESPN+ or equivalent service designation is not documented.

`GLOBAL_API_BROADCAST_GAP=YES`.

The current evidence does not identify a SportsDataIO Global endpoint or separately priced SportsDataIO product that supplies broadcast assignments. SportsDataIO's Media & Broadcast solution pages are not evidence that the Global API includes those fields. Fantasy/Odds pricing MUST NOT be treated as broadcast entitlement.

`ADDITIONAL_PRODUCT_REQUIRED=UNKNOWN`; likely separate product, entitlement, or commercial feed, but this requires provider confirmation.

### Access classes

| Access class                 | Current evidence                                                                                                                           | ChannelForge interpretation                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Free Trial                   | Self-service; scrambled but realistic; selectable available leagues/feeds; no production evidence                                          | Integration-shape testing only                             |
| Replay                       | Real historical data replayed through API structure                                                                                        | Historical workflow testing; not current production        |
| Historical/free              | First-party materials describe replay and historical options; exact Global entitlement/pricing unresolved                                  | Not assumed current-data access                            |
| Discovery Lab                | Previously documented real, next-day-delayed data and 100–1,000 calls/day for selected products; current Global inclusion is not confirmed | Do not assume it includes Global Sports                    |
| Global Sports API production | Current schedules/live scores/results product; API key; production key obtained through provider contact; price not public                 | Only credible current-data path found, subject to contract |
| Commercial/full access       | Production key and selected coverage provisioned by SportsDataIO                                                                           | Contract-dependent                                         |

The current developer page says production keys provide real-time data and “unrestricted coverage” for selected feeds, but this is not a public Global price or entitlement schedule.

### Terms, caching, retention, and derived outputs

SportsDataIO Terms of Service state:

- automated access is prohibited when not authorized;
- paid use grants a limited, non-exclusive, non-transferable, non-sublicensable right under the Terms;
- site content may not be copied, distributed, republished, transmitted, or modified except as expressly allowed or authorized in writing;
- the public Terms do not specify API response caching duration, evidence-retention duration, event-ID retention, derived-data storage, or XMLTV output rights.

| Question                                                | Classification       | Evidence-based disposition                                                        |
| ------------------------------------------------------- | -------------------- | --------------------------------------------------------------------------------- |
| Personal/non-commercial use                             | `UNCLEAR`            | Terms do not create a clear Global personal-use license                           |
| Automated retrieval                                     | `CONTRACT_DEPENDENT` | API access is authorized only through the selected product/key terms              |
| Local caching                                           | `CONTRACT_DEPENDENT` | No API cache rule found                                                           |
| Evidence retention                                      | `CONTRACT_DEPENDENT` | No retention permission found                                                     |
| Storing event IDs                                       | `UNCLEAR`            | IDs are exposed as API data; retention permission is not stated                   |
| Derived normalized observations                         | `CONTRACT_DEPENDENT` | Requires API/product agreement review                                             |
| Local guide output informed by evidence                 | `CONTRACT_DEPENDENT` | Raw-response redistribution and derived-output rights are not separated publicly  |
| XMLTV generated from provider evidence                  | `CONTRACT_DEPENDENT` | Requires explicit clarification                                                   |
| Redistribution                                          | `RESTRICTED`         | Public Terms restrict copying/distribution; commercial product terms may qualify  |
| Sharing provider-derived fields with local applications | `UNCLEAR`            | Internal local use is not expressly granted or prohibited in the public API terms |

No legal conclusion is made. Written product-specific clarification is required before production enrollment.

## Home Request Budget

Illustrative cached single-household model. These are planning estimates, not provider quota claims. The API documentation publishes endpoint call intervals for some feeds, but not a household refresh policy.

| Component                    |                               Low |                      Expected |                            High |
| ---------------------------- | --------------------------------: | ----------------------------: | ------------------------------: |
| A. Baseline schedule refresh | 10 competitions × 1 call/day = 10 |                   20 × 1 = 20 |                     30 × 1 = 30 |
| B. Near-event refresh        |            5 competitions × 1 = 5 |                   10 × 2 = 20 |                     20 × 2 = 40 |
| C. Live/upcoming window      |                 5 events × 2 = 10 |                   10 × 2 = 20 |                     20 × 3 = 60 |
| D. Retry reserve             |                  10% of A+B+C = 3 |                 15% of 60 = 9 |                 20% of 130 = 26 |
| E. Full rebuild amortization |           1 rebuild / 30 days = 1 |               2 / 30 days = 2 |                 4 / 30 days = 4 |
| **Idle day total**           |       **10 + 5 + 0 + 2 + 1 = 18** |  **20 + 10 + 0 + 5 + 2 = 37** |   **30 + 20 + 0 + 10 + 4 = 64** |
| **Busy day total**           |      **10 + 5 + 10 + 3 + 1 = 29** | **20 + 20 + 20 + 9 + 2 = 71** | **30 + 40 + 60 + 26 + 4 = 160** |

Idle days omit live-window calls and use half of the near-event target. Busy days include the live/upcoming window. The retry reserve is rounded up; rebuild amortization is rounded to the nearest whole call.

`ESTIMATED_IDLE_DAY_REQUESTS=LOW 18 / EXPECTED 37 / HIGH 64`

`ESTIMATED_BUSY_DAY_REQUESTS=LOW 29 / EXPECTED 71 / HIGH 160`

Monthly model: 25 idle days + 5 busy days.

`ESTIMATED_MONTHLY_REQUESTS=LOW (25×18)+(5×29)=595`

`ESTIMATED_MONTHLY_REQUESTS=EXPECTED (25×37)+(5×71)=1,280`

`ESTIMATED_MONTHLY_REQUESTS=HIGH (25×64)+(5×160)=2,400`

The expected model is below the previously documented 100–1,000 calls/day Discovery Lab range, but the high busy-day model is not. Whether Discovery Lab includes Global Sports remains unconfirmed. Production-key “unrestricted coverage” wording is not a price or service-level commitment.

## Low-cost corroboration

`football-data.org` is a documented, API-key-based, low-cost/free football-data candidate with competition schedules, teams, participants, dates, and status-oriented match data. It is soccer-only, not a global multi-sport solution; its licensing and retention terms must be reviewed before use. It is therefore a possible selective soccer corroborator, not a default dependency.

No credible inexpensive, permitted, documented multi-sport corroborator with sufficient coverage and explicit storage/automation terms was established.

`BEST_LOW_COST_CORROBORATING_PROVIDER=football-data.org for selective soccer only, pending terms review`

`NO_SUITABLE_LOW_COST_CORROBORATOR_FOUND=YES for general multi-sport use`

XMLTV and provider M3U metadata remain the normal low-cost corroborating evidence.

## Separate broadcast provider assessment

`SEPARATE_BROADCAST_PROVIDER_USEFUL=YES`

For ChannelForge, a specialized permitted listings/broadcast provider may add more value than a second box-score provider. However, this research did not establish a personal-user broadcast-only API with documented automation, local retention, and derived XMLTV rights.

Documented candidates requiring commercial/contract review:

- Gracenote / TMS: strong listings and broadcast metadata; enterprise/licensing path;
- Sportradar selected league products: documented broadcast fields, but B2B and product-specific;
- SportsDataIO Media & Broadcast offerings: potentially relevant, but no evidence that Global Sports API entitlement includes broadcast assignments.

Preferred decision order:

1. Global schedule provider + XMLTV/M3U metadata by default.
2. Add a broadcast-specialist provider if broadcast assignment remains materially incomplete.
3. Add Global Provider B only when independent event/status corroboration is more valuable than broadcast coverage.

## Corrected product model

`SUPPORTED_PROVIDER_COUNT=2_OR_MORE`

`DEFAULT_REQUIRED_PROVIDER_COUNT=1`

`DEFAULT_EVIDENCE_STRATEGY=PRIMARY APPROVED GLOBAL PROVIDER + XMLTV + provider M3U metadata + accepted ChannelForge history`

`OPTIONAL_SECOND_PROVIDER_STRATEGY=SECONDARY INDEPENDENT GLOBAL PROVIDER only when enabled by the user and justified by uncertainty/cost`

`SPECIALIST_SOURCE_STRATEGY=APPROVED league/broadcaster/event-organizer evidence only for material unresolved uncertainty`

`ESPN_ROLE=HIGH_VALUE_UNSUPPORTED_RESEARCH_SOURCE`

The eventual beginner UX should expose `Sports intelligence: Connected`; provider-specific evidence plumbing remains behind the setup and provenance boundary.

## Updated product conclusion

- SportsDataIO Global remains the primary candidate, but current competition entitlement, schedule horizon, event-transition semantics, broadcast fields, and Global pricing are unresolved.
- One approved provider is sufficient for normal Guided Setup when combined with XMLTV, provider metadata, and accepted history.
- A second paid provider is optional, not a default requirement.
- A separate broadcast provider may be more valuable than a second global schedule provider.
- No production adapter is authorized.

League-specific adapters remain necessary for:

- competitions absent from the selected global provider;
- authoritative status changes or schedule corrections;
- broadcast assignments missing from global feeds;
- independent corroboration when global providers agree incorrectly;
- specialist sports such as Olympics, niche motorsports, regional cricket/rugby, and event-organizer-controlled combat sports.

CREDENTIAL_SUPPORT_EVENTUALLY_REQUIRED=YES. A commercial global provider requires secure credential-aware enrollment; no credentials are implemented or stored by this track.

No production adapter or shared-contract change is authorized by this pivot.

## SportsDataIO Provider Confirmation Gate

The technical schema gate is complete. Provider selection remains blocked on three confirmation gates: coverage, personal product/cost, and ChannelForge usage rights. No account, registration, credential, or terms acceptance is authorized by this packet.

SportsDataIO may still be acceptable as ChannelForge's first global schedule provider without broadcast assignments. Broadcast evidence is secondary and may be supplied later by XMLTV, provider M3U metadata, AED/event-pattern evidence, accepted ChannelForge history, or an optional specialist adapter.

### Confirmation request context

ChannelForge is a local/home IPTV and EPG management application. It periodically retrieves sports schedule and event metadata as evidence when reconciling a user's own IPTV playlist and XMLTV guides. It is not intended to redistribute raw SportsDataIO responses.

### A. Coverage questions

Please return one classification for every requested item:

`AVAILABLE | NOT_AVAILABLE | SEPARATE_PRODUCT | SEPARATE_ENTITLEMENT | UNKNOWN`

For the specific personal/developer product being quoted, identify the current classification for:

| Group  | Requested coverage                                                                                                                                                 |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| US     | NFL; MLB; NBA; NHL; NCAA football; NCAA basketball                                                                                                                 |
| Soccer | Premier League; UEFA Champions League; La Liga; Bundesliga; Serie A; Ligue 1; MLS; major international competitions                                                |
| Other  | Formula 1; NASCAR; IndyCar; ATP; WTA; Grand Slams; PGA/major golf; UFC; boxing; cricket; rugby union; rugby league; international basketball; international hockey |

Also confirm:

1. How far ahead schedules are normally published for each representative sport.
2. Whether schedule changes retain the same `GlobalSportsEventId`.
3. How TBD starts are represented.
4. How postponed events are represented.
5. How cancelled events are represented.
6. How rescheduled events are represented.
7. Whether the event record is updated in place or replaced.
8. Whether the provider supplies a change/revision indicator beyond `Updated`.
9. Whether tournament events can appear before participants are known.

### B. Personal product and cost questions

1. Is the Global Sports API available to an individual or personal non-commercial developer?
2. Is there a self-service plan?
3. What is the minimum plan that provides current, real, unscrambled Global data?
4. What is the monthly price?
5. What is the annual price?
6. What request limit applies?
7. What QPS limit applies?
8. Which sports and competitions are included in that minimum plan?
9. Does one Global entitlement cover all enabled sports, or are sports/competitions sold separately?
10. Is a trial key available with real current data rather than scrambled data?
11. Does the proposed personal/developer plan support the following preliminary request envelope?

```text
Expected idle day: 37 requests
Expected busy day: 71 requests
Expected month: 1,280 requests
Planning range: 595–2,400 requests/month
```

The estimates assume caching and incremental refresh rather than continuous full polling.

### C. ChannelForge usage-rights questions

For the quoted product/license, classify each right as:

`PERMITTED | RESTRICTED | NOT_PERMITTED | CONTRACT_DEPENDENT`

Please answer whether the license permits:

1. Automated API retrieval.
2. Local caching.
3. Storing normalized observations.
4. Storing SportsDataIO event IDs.
5. Retaining historical observations.
6. Comparing observations with third-party XMLTV.
7. Deriving local event/channel matches.
8. Creating local XMLTV/EPG output informed by SportsDataIO evidence.
9. Displaying that derived guide locally in the user's household.
10. Sharing locally generated XMLTV with other applications on the same user's private network.
11. Retaining provenance stating that SportsDataIO supplied a particular fact.
12. Retaining derived data after the raw cache expires.

Please identify the controlling API/product agreement, terms, or data-license section for each non-obvious answer. General website Terms should not be treated as a substitute for API/product authorization.

### D. Optional broadcast questions

Broadcast assignment is not a prerequisite for selecting the first global schedule provider. Please answer separately whether SportsDataIO offers a documented product providing:

- TV network;
- broadcaster;
- streaming service;
- ESPN+ or equivalent assignment;
- market/country;
- national/regional designation;
- multiple broadcast assignments.

If yes, identify:

```text
PRODUCT=
ENTITLEMENT=
PRICE=
CAN_SHARE_API_KEY_ACCOUNT=
EVENT_ID_JOIN_KEY=
```

The critical technical question is whether broadcast records join reliably to `GlobalSportsEventId` or another stable Global identifier.

### Generic provider-confirmation template

The same three-gate request can be sent to another candidate without changing the questions:

#### COVERAGE

- Which requested sports and competitions are available?
- Classify each as `AVAILABLE`, `NOT_AVAILABLE`, `SEPARATE_PRODUCT`, `SEPARATE_ENTITLEMENT`, or `UNKNOWN`.
- What schedule horizon, event-ID stability, TBD representation, and postponed/cancelled/rescheduled model apply?

#### PERSONAL PRODUCT/COST

- Is the product available to an individual personal non-commercial developer?
- Is there a self-service current-data plan?
- What are the minimum price, annual price, request limit, QPS limit, and entitlements?
- Does the plan support 37 idle-day, 71 busy-day, and 1,280 monthly requests with caching/incremental refresh?

#### CHANNELFORGE USAGE RIGHTS

- Are automated retrieval, local caching, normalized observations, event-ID retention, historical retention, XMLTV comparison, derived local EPG output, household display, private-network sharing, provenance retention, and post-cache derived-data retention permitted?
- Classify each right as `PERMITTED`, `RESTRICTED`, `NOT_PERMITTED`, or `CONTRACT_DEPENDENT`.
- Identify the controlling product terms.

### Gate result

`TECHNICAL_SCHEMA_GATE=PASS`

`COVERAGE_CONFIRMATION_REQUIRED=YES`

`PRODUCT_PRICING_CONFIRMATION_REQUIRED=YES`

`LICENSING_CONFIRMATION_REQUIRED=YES`

`SPORTSDATAIO_CAN_BE_SCHEDULE_ONLY_PROVIDER=YES`

`HOLD_FOR_PROVIDER_PRODUCT_CONFIRMATION`

## Standing Product Requirement: Professional Wrestling

Professional wrestling coverage is a first-class event domain and is extremely important to the user. It MUST NOT be treated as an optional niche after the conventional sports matrix.

### Required promotion evaluation

Every primary/global provider and specialist event source MUST be evaluated for:

- WWE;
- AEW;
- TNA;
- NJPW;
- MLPW;
- GCW (Game Changer Wrestling);
- other significant promotions as relevant.

For each provider and promotion, the confirmation checklist MUST classify:

```text
PRO_WRESTLING_SUPPORTED=YES | NO | PARTIAL | UNKNOWN
PRIMARY_PROVIDER_PRO_WRESTLING_COVERAGE=YES | NO | PARTIAL | UNKNOWN
PRIMARY_PROVIDER_REQUIRES_WRESTLING_SPECIALIST=YES | NO | UNKNOWN
PRO_WRESTLING_SPECIALIST_ADAPTER_REQUIRED=YES | NO | UNKNOWN
PROMOTIONS_SUPPORTED=
WWE=
AEW=
TNA=
NJPW=
MLPW=
GCW=
OTHER_PROMOTIONS=
EVENT_SCHEDULES=
WEEKLY_SHOWS=
PPV_PLE=
SPECIAL_EVENTS=
TOURING_LIVE_EVENTS=
STABLE_EVENT_IDS=
EVENT_STATUS=
VENUES=
BROADCAST_NETWORK=
STREAMING_SERVICE=
CARD_MATCH_DATA=
PARTICIPANTS=
CHAMPIONSHIPS=
CARD_CHANGES=
FUTURE_HORIZON=
```

The event model evaluation MUST cover:

- promotion;
- event/show identity;
- weekly television shows;
- PPV/PLE/premium events;
- special events;
- touring/live events where available;
- event date/time;
- revised event time;
- TBD handling;
- venue and city/location;
- live/upcoming/completed/cancelled/postponed/rescheduled status;
- broadcaster/network;
- streaming service;
- country/market;
- stable event identifier;
- future schedule horizon.

Where available, the evaluation SHOULD also cover advertised matches, wrestlers/participants, match order/card position, championships/titles, card changes, event subtype, and episode/show name. These deeper fields remain adapter-specific unless a future reviewed contract generalizes them; they MUST NOT be added to `ChannelForgeExternalEvidenceObservation/v1` by this requirement.

### Volatile wrestling evidence

A wrestling card is volatile evidence. ChannelForge MUST NOT assume an advertised match remains unchanged. Opponent changes, participant substitutions, match cancellation, title-match changes, card additions/removals, event rescheduling, venue changes, and broadcast/service changes require fresh observations and field-level provenance.

Wrestling-event metadata MUST NOT redefine durable channel identity. Event identity and channel identity remain separate concerns.

### Wrestling specialist path

Conventional global sports-data providers MUST NOT be assumed to cover professional wrestling adequately. SportsDataIO professional-wrestling coverage has not yet been confirmed.

Current state:

```text
PRO_WRESTLING_SUPPORTED=UNKNOWN
PRIMARY_PROVIDER_PRO_WRESTLING_COVERAGE=UNKNOWN
PRIMARY_PROVIDER_REQUIRES_WRESTLING_SPECIALIST=UNKNOWN
PRO_WRESTLING_SPECIALIST_ADAPTER_REQUIRED=UNKNOWN
```

Decision rule:

- If the selected primary provider provides adequate WWE, AEW, TNA, NJPW, MLPW, and GCW coverage, set:

  ```text
  PRIMARY_PROVIDER_REQUIRES_WRESTLING_SPECIALIST=NO
  ```

- If the selected primary provider lacks or materially under-covers GCW or any other mandatory promotion in WWE, AEW, TNA, NJPW, MLPW, and GCW, set:

  ```text
  PRIMARY_PROVIDER_REQUIRES_WRESTLING_SPECIALIST=YES
  PRO_WRESTLING_SPECIALIST_ADAPTER_REQUIRED=YES
  ```

The result MUST remain unknown until provider confirmation. A wrestling specialist remains an approved source direction, not a settled implementation requirement.

The highest-value wrestling evidence for Guide Intelligence is:

1. What wrestling event/show is airing?
2. When does it start?
3. Which promotion owns it?
4. Which network or streaming service carries it?
5. Has the event or card changed?
6. Is the XMLTV listing stale or incomplete?
7. Can event identity help map a temporary/event channel correctly?

Detailed wrestling statistics are lower priority than guide/event identity.

### Wrestling additions to the provider-confirmation packet

The SportsDataIO and generic provider confirmation checklists MUST additionally ask:

- Is professional wrestling supported as a first-class sport/event domain?
- Are weekly television shows, PPV/PLE events, and special events covered?
- Which of WWE, AEW, TNA, NJPW, MLPW, GCW, and other significant promotions are covered?
- Are event identity, promotion, date/time, revised time, venue, city, status, network, streaming service, market, and stable IDs available?
- What is the future schedule horizon?
- Are advertised matches, participants, card position, championships, card changes, subtype, and episode/show names available?
- Are wrestling updates and volatile card changes represented as field updates on the same event ID or as replacement records?
- Can wrestling event records be joined to broadcast/service assignments?

Professional wrestling is now a required product-evaluation gate, while broadcast data remains a secondary provider-selection concern and deeper card fields remain adapter-specific.
