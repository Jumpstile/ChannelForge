# ADR 0014: Secure bounded HTTPS acquisition transport

## Status

Accepted

## Context

ChannelForge currently supports local XMLTV ingestion and local provider processing. Remote XMLTV and remote M3U acquisition require a shared transport boundary that prevents DNS rebinding, unsafe destinations, redirects, proxies, unbounded buffering, credential leakage, and degraded-success publication.

The current module manifest declares PowerShell 7.0. The required `SocketsHttpHandler.ConnectCallback` API is available on newer .NET runtimes, but the supported ChannelForge transport floor must remain aligned with a currently supported PowerShell LTS line.

This ADR defines transport only. It does not implement XMLTV parsing, M3U parsing, caching, scheduling, provider adapters, or GUI behavior.

## Decision

### Runtime floor

The minimum supported runtime for ChannelForge remote HTTPS acquisition is:

- PowerShell 7.6 or newer.
- PowerShell Core edition only.
- .NET 10 or newer.
- No Windows PowerShell 5.1 support.
- No remote-transport fallback for PowerShell 7.0–7.5.

PowerShell 7.6 is the current Microsoft LTS line. PowerShell 7.4 remains supported only until 2026-11-10, so it is not adopted as a new long-lived ChannelForge product floor.

Before remote transport ships, the module manifest must change from:

```powershell
PowerShellVersion = '7.0'
```

to:

```powershell
PowerShellVersion = '7.6'
```

This is an intentional compatibility change. The 7.6 floor applies to the module version containing the adopted transport architecture, including local-only commands. The transport helper remains lazy-loaded: local-only commands do not compile or invoke it.

The API availability floor and the supported product floor are deliberately different. `ConnectCallback` exists in earlier .NET versions, but retired PowerShell runtimes are not supported ChannelForge targets.

### Narrow C# helper exception

ChannelForge may introduce one narrowly scoped source-level C# helper through `Add-Type -TypeDefinition`.

The helper may contain only:

- `SocketsHttpHandler` construction;
- DNS-resolution coordination;
- validated-address selection;
- direct socket connection;
- connection callback implementation;
- generic HTTP response streaming;
- bounded byte accounting;
- transport-safe error translation.

The helper must not contain:

- XMLTV or M3U parsing;
- provider logic;
- cache logic;
- scheduling;
- persistence;
- GUI behavior;
- merge or domain-model decisions;
- arbitrary user-provided code or configuration compilation.

Proposed source location:

```text
src/ChannelForge/Private/Transport/ChannelForgePinnedHttpTransport.cs
```

The tracked `.cs` source is read as UTF-8 from the installed module. It is not generated, downloaded, modified, or replaced at runtime.

A private PowerShell loader may be added at:

```text
src/ChannelForge/Private/Initialize-ChannelForgePinnedHttpTransport.ps1
```

The loader must:

- verify that the expected helper type and transport-contract version are not already loaded with a conflicting definition;
- reuse the already loaded matching type/version;
- never attempt recompilation for a matching loaded type;
- read only the tracked source file;
- compile only on first remote-transport use;
- avoid compilation during ordinary module import;
- fail closed if compilation or capability checks fail;
- surface compiler warnings and errors;
- silently suppress no compiler diagnostics;
- never download source, assemblies, packages, or dependencies.

Compilation failure is a terminating capability failure for remote acquisition only. Since the adopted module policy makes PowerShell 7.6+ universal, local-only behavior remains usable without invoking or compiling the helper, although the module itself requires 7.6.

This is a tightly constrained exception for one security boundary. It does not establish a general precedent for adding compiled C# to ChannelForge. Any other C# helper requires a separate architecture decision.

The helper is source-reviewed and compiled in memory; it is not a separately signed binary. Supply-chain protection therefore depends on protected repository history, code review, CI compilation on supported runtimes, release integrity controls, and secret scanning. A future separately packaged binary requires its own signing and distribution decision.

### Transport contract

The private transport exposes a payload-neutral response contract equivalent to:

```text
ChannelForgeHttpsPayload
  SourceId
  StatusCode
  StatusDisposition
  ContentType
  ContentEncodings
  ContentLength
  HasPayload
  ResponseStream
  Dispose()
```

`ContentEncodings` is an immutable ordered collection of normalized encoding tokens. Multiple `Content-Encoding` header values are concatenated in wire order, trimmed, and normalized invariantly. The order is preserved because encoding order is semantically meaningful.

The response stream is raw response-body data. It is not a string, byte-array snapshot, parsed XML document, parsed playlist, cache entry, or generated artifact.

The transport uses response-headers-read semantics and leaves the response body streaming. XMLTV, M3U, and future provider adapters own format detection, decompression selection, parsing, validation, and provenance.

### HTTP status contract

Ordinary acquisition requires HTTP 200 by default.

The transport contract must also support an explicitly caller-authorized status policy for future use. A caller may authorize a status such as 304 for conditional caching under ADR 0013, but:

- the caller must opt in explicitly;
- a 304 is returned as status metadata;
- a 304 has `HasPayload = false`;
- a 304 has no consumable payload stream;
- a 304 is never treated as fresh payload by the transport;
- XMLTV and M3U payload parsers must reject a 304 as input;
- cache interpretation remains outside this ADR.

Redirects remain rejected regardless of caller status policy.

Partial content, no-content, error, and other non-authorized statuses remain failures. In particular, 206, 204, 3xx, 4xx, and 5xx responses are not ordinary payload success.

### Endpoint validation and connection pinning

For each request:

1. Validate the URI before DNS resolution.
2. Require an absolute `https` URI.
3. Require port 443.
4. Reject URI user information such as `username:password@host`.
5. Reject unsupported or malformed host names.
6. Resolve the host name once.
7. Validate every returned IPv4 and IPv6 address.
8. Reject the entire resolution result if any candidate is private, loopback, link-local, multicast, unspecified, reserved, documentation-only, carrier-grade NAT, or otherwise not globally routable.
9. Normalize and sort the remaining candidates.
10. Attempt candidates in that stable order.
11. Pin the first successfully connected validated address to the request's `ConnectCallback`.
12. Connect directly to that IP address with a socket.
13. Preserve the original hostname in the request URI.
14. Allow the normal HTTPS stack to use the original hostname for TLS SNI and certificate hostname validation.
15. Never connect by passing the original hostname to a second uncontrolled DNS lookup.

A literal IP address is validated directly. A hostname is resolved before connection.

A mixed DNS answer containing both allowed and blocked destinations is rejected rather than filtered. This treats an ambiguous DNS response as unsafe.

### Deterministic address ordering

Candidate family order is:

1. IPv6
2. IPv4

Within each family, candidates are ordered lexicographically by normalized address bytes:

- IPv6 uses its 16-byte address representation.
- IPv4 uses its 4-byte address representation.

The IPv6-first rule preserves modern dual-stack preference while remaining deterministic and avoiding dependence on platform DNS enumeration order. This is not a racing or Happy-Eyeballs policy. Candidates are attempted sequentially in the defined order.

Selected addresses are operational connection details only. They must not affect identifiers, artifact ordering, warnings, hashes, evidence identity, or build decisions.

The callback must reject any connection context whose host or port does not match the validated request. It must not silently accept a different destination supplied by the HTTP handler.

Each source request uses a handler/client lifetime that cannot be shared across unrelated source hosts. Initial implementation is sequential and uses one pinned connection decision per source request.

Proxy use is disabled. The transport does not use environment proxy settings because proxy routing would invalidate the direct-address pinning guarantee.

### Network policy

| Policy | Decision |
|---|---|
| Scheme | HTTPS only |
| Port | 443 only |
| HTTP method | GET only initially |
| URI credentials | Rejected |
| Automatic redirects | Disabled |
| Cookies | Disabled |
| Default credentials | Disabled |
| Proxy | Disabled |
| Automatic decompression | Disabled |
| Automatic retries | Zero |
| Compressed/raw body limit | 256 MiB hard maximum |
| Decompressed body limit | 256 MiB hard maximum |
| DNS resolution timeout | 10 seconds |
| TCP connection timeout | 10 seconds |
| Response-header timeout | 30 seconds |
| Body-read inactivity timeout | 30 seconds |
| Total request deadline | 120 seconds |
| TLS certificate validation | Platform default validation; no bypass |
| TLS hostname | Original requested hostname |
| Cancellation | Immediate linked-token cancellation; no retry |

Adapters may request smaller limits but may not raise the hard maximums without a new ADR decision.

Credentials required by a future adapter must be supplied through a separate secret-aware mechanism. Credentials must never be embedded in the URI. Authorization headers, if later supported, must not be logged, copied into evidence, forwarded across redirects, or included in diagnostics.

### Redirect policy

Automatic redirects are disabled.

Every 3xx response is a `RedirectRejected` failure. The `Location` header is not emitted in user-facing diagnostics because it may contain credentials, signed tokens, or an unsafe destination.

Future redirect support would require a separate ADR amendment or decision and must:

- validate every hop independently;
- resolve and validate every hop's addresses;
- pin every hop's connection;
- reject HTTPS-to-HTTP downgrade;
- avoid forwarding credentials or cookies across hosts;
- enforce a bounded hop count;
- preserve deterministic ordering and error behavior.

### Streaming and response bounds

The transport must never perform unbounded response buffering.

The raw response stream is wrapped in a bounded reader that:

- checks `Content-Length` early when present;
- continues enforcing the limit while reading;
- handles chunked and missing-length responses;
- throws `ResponseTooLarge` as soon as the raw byte limit is crossed;
- disposes the response and connection on violation.

`Content-Length` is advisory only. Enforcement during reading is authoritative.

Automatic HTTP content decompression is disabled so the raw compressed-byte limit can be enforced. Adapters or a shared generic decompression wrapper must enforce the decompressed-byte limit while data is expanded.

A decompression limit failure is reported as `DecompressionLimitExceeded`. It must not become a successful partial payload.

### Content-type handling

The transport does not infer payload meaning from content type.

It must:

- expose the normalized media type and ordered content-encoding list;
- allow the caller to provide an explicit media-type allowlist;
- reject a declared type outside that allowlist as `UnsupportedContentType`;
- permit a missing content type only when the caller explicitly allows it;
- treat `application/octet-stream` as generic bytes, not as proof of a valid payload;
- leave format validation and magic-byte checks to the adapter.

The transport must not contain XMLTV-specific or M3U-specific media-type logic.

### XC / Xtream Codes compatibility boundary

ADR 0014 defines the secure HTTPS acquisition transport for #88, #89, and future adapters that satisfy this policy.

It does not guarantee compatibility with every XC/Xtream Codes server.

Full #90 support may encounter:

- non-standard ports;
- HTTP-only endpoints;
- provider-specific credential or query conventions;
- provider-specific response behavior.

ADR 0014 must not be weakened to accommodate those cases.

Before #90 supports an endpoint outside this policy, #90 must receive a dedicated provider-compatibility and security decision. No silent HTTPS-to-HTTP downgrade is permitted.

Any insecure or legacy compatibility mode, if ever authorized, must be:

- explicit;
- opt-in;
- clearly warned;
- bounded;
- isolated from the default transport;
- separately reviewed and tested.

Credentials still require a dedicated secret-aware configuration boundary. “Full XC support” remains a product requirement, but it must be achieved consciously rather than by weakening the default secure transport.

### Error model

Transport failures use deterministic categories:

| Category | Meaning |
|---|---|
| `DnsFailure` | Name resolution failed or returned no usable address |
| `BlockedDestination` | At least one resolved address was unsafe or not globally routable |
| `TlsFailure` | TLS negotiation or platform certificate/hostname validation failed |
| `Timeout` | DNS, connection, headers, body inactivity, or total deadline expired |
| `RedirectRejected` | The server returned a 3xx response |
| `ResponseTooLarge` | Raw response bytes exceeded the hard limit |
| `DecompressionLimitExceeded` | Expanded bytes exceeded the hard limit |
| `NonSuccessHttpStatus` | The response status was not authorized by the caller |
| `UnsupportedContentType` | Declared media type was outside the caller's allowlist |
| `ConnectionFailure` | Direct connection failed after deterministic candidate attempts |
| `Cancelled` | Caller cancellation was requested |

A caller-authorized 304 is not an error category, but it is a status-only outcome with no payload. It must not be consumed by payload parsers.

Diagnostics may include:

- stable `SourceId`;
- error category;
- status disposition;
- request phase;
- HTTP status, when safe;
- byte counts, when safe;
- timeout class.

Diagnostics must not include:

- raw URLs;
- URI user information;
- query strings;
- authorization headers;
- cookies;
- signed URLs;
- credentials;
- local absolute paths;
- arbitrary response bodies;
- raw DNS answers or selected IP addresses in build reports.

### Shared architecture

The transport belongs to the cross-cutting security/ingestion boundary defined by ADR 0007.

The dependency direction is:

```text
Build orchestration
    -> source adapter
        -> bounded HTTPS transport
            -> DNS/address policy and socket connection
```

The transport does not depend on:

- XMLTV classes;
- M3U classes;
- provider-specific adapters;
- merge logic;
- output serialization;
- cache state;
- durable snapshots;
- GUI code.

The same payload contract is available to:

- #89 remote XMLTV acquisition;
- #88 remote M3U acquisition;
- future provider adapters, including #90, when separately approved.

Sharing transport does not merge #88, #89, or #90 scope.

### Determinism

Network behavior must not alter meaningful artifacts or decisions for identical successful content.

The implementation must guarantee that:

- DNS answer order does not affect candidate order;
- IPv6 candidates are considered before IPv4 candidates;
- address bytes determine order within a family;
- request retries are not used;
- candidate connection attempts occur in stable order;
- selected IP addresses are not used as identifiers, ordering keys, warnings, hashes, or artifact content;
- response timing does not affect parsed records, evidence identity, merge ordering, output bytes, or decisions;
- transport diagnostics are separated from canonical artifacts;
- identical successful payload bytes produce identical downstream results regardless of which validated address served them;
- a 304 status cannot produce a payload or alter artifacts without separately approved cache logic.

A different payload or actual transport failure is a legitimate input change and may produce a different result. Network timing alone must not.

### Testing strategy

CI must not contact live provider URLs.

Tests must use reserved placeholder domains, injected DNS answers, deterministic fake streams, local test endpoints, and fixtures.

Required coverage includes:

- URI scheme, port, user-information, and malformed-host rejection;
- IPv4 and IPv6 private, loopback, link-local, multicast, unspecified, reserved, documentation, and carrier-grade address filtering;
- rejection of mixed safe/unsafe DNS answers;
- explicit IPv6-before-IPv4 candidate-family ordering;
- deterministic address-byte ordering within each family;
- injected DNS failure and empty-answer behavior;
- verification that the connection callback receives the original hostname but connects to the selected IP;
- verification that a second uncontrolled hostname resolution cannot occur;
- TLS SNI and certificate hostname preservation using an ephemeral local test certificate;
- redirect rejection for every common 3xx response;
- HTTPS downgrade rejection in future redirect-policy tests;
- ordinary status policy requiring 200;
- future-authorized 304 pass-through at the transport-contract layer;
- proof that 304 has no payload stream and cannot be consumed by XMLTV/M3U payload logic without cache code;
- raw response-size enforcement with and without `Content-Length`;
- chunked-response bounds;
- bounded gzip/ZIP decompression;
- timeout at DNS, connect, headers, and body-read phases;
- immediate cancellation and disposal;
- non-200 status handling;
- content-type allowlist behavior;
- deterministic results from identical payloads served through different validated-address orderings;
- secret redaction for URI user information, signed URLs, headers, and exception messages;
- repeated module import and lazy helper-load behavior;
- reuse of an already loaded matching helper type/version without recompilation;
- conflicting loaded helper version failure;
- unsupported-runtime and missing-capability failure;
- compiler warnings and errors surfaced rather than silently suppressed.

The production loopback/private-address policy must remain enabled during tests. Any local TLS test server must use an explicit test-only dependency-injection seam rather than a runtime configuration switch that weakens production policy.

### Consequences

Positive consequences:

- Remote XMLTV and M3U adapters share one security boundary.
- DNS rebinding is addressed at the actual connection point.
- Redirects, proxies, retries, and unbounded buffering cannot silently bypass policy.
- Transport errors are stable and safe to publish.
- Identical payloads remain deterministic regardless of network details.
- 304 can be added to future cache workflows without redesigning the transport.
- XC compatibility remains a deliberate adapter decision rather than a weakening of the default security contract.

Tradeoffs:

- The supported module floor rises from PowerShell 7.0 to 7.6.
- PowerShell 7.4 and 7.5 are not supported by the transport contract.
- Strict mixed-DNS rejection may reject unusual but legitimate dual-stack configurations.
- Zero redirects may require canonical final URLs.
- Disabled proxy support may not fit enterprise environments.
- Zero retries may reduce transient network recovery.
- Hard byte limits may reject unusually large valid sources.
- The source-level C# helper adds a reviewed runtime compilation boundary.
- Initial sequential, one-request-at-a-time use favors determinism and safety over throughput.

### Explicit non-goals

This ADR does not implement or authorize:

- remote XMLTV acquisition itself;
- remote M3U acquisition itself;
- cache or conditional-request reuse;
- scheduling or unattended refresh;
- provider or XC adapter logic;
- GUI behavior;
- durable source snapshots;
- last-known-good or offline/degraded-success publication;
- XMLTV or M3U parsing;
- XMLTV/M3U merge logic;
- redirects;
- HTTP POST;
- arbitrary proxy support;
- DNS pinning for unrelated application code;
- insecure XC compatibility modes.

### Adoption and implementation order

After ADR approval, implementation proceeds in these bounded slices:

1. Raise the module manifest and runtime contract to PowerShell 7.6.
2. Add the narrowly scoped C# source and lazy loader; compile and test without network access.
3. Add deterministic endpoint validation, address classification, family ordering, and error mapping.
4. Add pinned socket connection and original-host TLS validation.
5. Add raw streaming, response bounds, cancellation, content-encoding collections, and generic decompression bounds.
6. Add status-policy tests, including 304 metadata-only pass-through.
7. Add local deterministic HTTPS test fixtures and secret-redaction regression tests.
8. Integrate the transport into #89 remote XMLTV without cache or scheduling.
9. Integrate the same transport into #88 remote M3U without provider-adapter expansion.
10. Design cache interpretation separately under ADR 0013.
11. Reassess #90 only after a dedicated XC compatibility/security decision.

## Related decisions

- ADR 0004 — Self-healing with guardrails
- ADR 0007 — Modular boundaries and dependency direction
- ADR 0008 — Canonical domain model versus target projections
- ADR 0009 — Durable state, persistence, migrations, caching, and retention
- ADR 0010 — Deterministic runs, clocks, identifiers, ordering, and serialization
- ADR 0011 — Security boundaries, adapter isolation, secret handling, and update integrity
- ADR 0012 — Performance and scaling targets
- ADR 0013 — Caching and incremental rebuilds
- #88 — Provider M3U live fetch
- #89 — XMLTV EPG fetch/parse/cache
- #90 — XC / Xtream Codes provider adapter
