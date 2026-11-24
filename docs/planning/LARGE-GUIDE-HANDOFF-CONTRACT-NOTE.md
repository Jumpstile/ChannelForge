# Draft contract: large guide handoff by server-issued handle (261-A)

This is a proposal, not an implementation contract. It adds no code or tests. Read evidence is named below; unverified details remain marked NOT VERIFIED.

## Purpose and boundary

The browser cannot upload a very large XMLTV guide and must never send a local path. The server reads a guide from its own permitted disk area. A handle is only a temporary reference; the engine remains responsible for parsing, validation, candidate generation, and explicit acceptance. A failed read or parse changes no accepted state and publishes no partial result.

## Getting a guide onto the server

Recommendation: an administrator chooses one import folder on the server host and copies guide files there using that host's normal file tools. Do not add browser upload in this slice. The folder is separate from generated outputs and is read-only to guide selection. This avoids large browser requests and avoids giving the browser file-system authority.

Docker: mount an administrator-selected host directory into a documented container import location, read-only. Windows server: configure an administrator-selected import folder with read access for the service account. Portable Windows bundle: keep loopback-only behavior; configure the import folder through server configuration or the launcher, never through browser folder selection. No browser request carries a folder or path.

Folder configuration, permissions, link/reparse-point behavior, and exact locations are NOT VERIFIED against implementation; no handle implementation exists in the paths read. These are design requirements, not claims about current behavior.

## Handle and browser exchange

1. An authenticated browser asks for available guides. The server returns a bounded page of opaque random handles plus safe display name and size; no path or full filesystem name is returned. Do not return modified time unless a user need is established.
2. A handle maps server-side to one file below the configured import root and is bound to the issuing authenticated session. On resolution, verify that the file still exists and is still within the allowed root; reject links or path escapes. Open the file only after checks.
3. The handle expires after 15 minutes (proposal). Expired, revoked, unknown, or other-session handles are indistinguishable to the browser. Refresh the list to obtain a new handle. Changing session or signing out invalidates it.
4. The browser submits the handle in the existing guide-selection operation; it never submits a path, filename as authority, or file bytes. The server replies with ordinary proposal/status data and safe errors, never a resolved path.

The routes and request fields are proposed; no current route contract was verified. Authentication uses the server sign-in boundary being designed; portable loopback mode remains unchanged and does not gain sign-in.

## Limits and messages

Use existing guide and decompression limits; do not increase them merely because disk input avoids browser upload. The server must enforce file-size limits before and while reading, and the existing streaming/trim path should be reused where the caller has playlist channel IDs. No unbounded whole-file buffering. A parsed guide that remains over the current limit after trimming fails without publication.

The existing server-side maximum applicable to this handoff is NOT VERIFIED. Do not promise a 1.8 GB file is accepted until the limit, stream path, and real workload are measured. The proposed 1 GiB fallback in the older handle note is not adopted here.

Show a short plain message with a Details option. Suggested messages:

- Expired/unavailable: "That guide is no longer available. Refresh the list and pick it again." Details: "The selection expired, was removed, or is not available to this session."
- Too large: "This guide is over the server's {limit} limit." Details: "No lineup was changed. Choose a smaller guide or ask the server administrator about the limit."
- Invalid/unreadable: "ChannelForge could not read this guide. Nothing was changed." Details may show a safe error category, never the path or raw parser input.
- Read stopped: "ChannelForge could not finish reading this guide. Nothing was changed." Details may show a safe error category.

The Details option must not expose filesystem paths, stream URLs, credentials, raw headers, or server internals.

## Logging and frozen contracts

Log safe event category, time, and outcome; optionally a non-reversible request correlation ID. Never log paths that may contain personal information, guide contents, stream URLs, credentials, cookies, tokens, or full request headers. Do not log the handle as a durable identifier. Auth design's secret redaction rules continue to apply.

Untouched: guide-id contract v1.0; raw digest projections; M3U entry byte format; BuildIdentityInput; blocker-2-contract v7/v8/v10; accepted-state; candidate-manifest; decision-manifest; ADR-0014; journal v2; package-manifest format. The handle is transport/session routing only: it is not an identity, hash input, manifest field, or acceptance decision. Existing `InputArtifactHash` hashes the exact input XMLTV bytes when imported directly, or the trimmed temporary guide bytes when trimming runs; keep those existing byte semantics, and do not use the handle as guide identity. Exact bytes remain governed by current contracts.

## Smallest-first slices

1. **Import-root setting and safe listing.** Establish per-deployment read-only root, bounded list, safe display fields, and containment checks. Verify no path appears in browser response or logs.
2. **Session-bound expiring handles.** Issue opaque handles, resolve only within root, invalidate on expiry/sign-out, return uniform unavailable errors.
3. **Existing guide selection integration.** Accept handle at the guide-selection boundary and feed the existing local-file import/trim path without changing parser or identity contracts.
4. **Limits, safe diagnostics, deployment wiring.** Prove bounded streaming, no partial publication, and Docker/Windows/portable behavior; document mount and folder setup.

Each slice needs user-visible checks for path secrecy, expiry, refusal of escape/missing files, and no accepted-state change on failures. Do not add upload or a new parser in these slices.

## Owner questions

1. Guide placement: server-side import folder or browser upload? **Recommendation:** server-side folder and administrator copy; upload is separate scope.
2. Handle expiry and binding? **Recommendation:** 15 minutes, issuing session only, invalidate on sign-out.
3. Size limit? **Recommendation:** current engine limit until evidence supports a separately approved increase; do not claim 1.8 GB support yet.
4. Which safe display metadata? **Recommendation:** basename sanitized for display and size only; no absolute paths or modified times.
5. Network-server authorization? **Recommendation:** require the shared-admin sign-in design before enabling handles on non-loopback server modes; keep portable loopback mode as-is.

## Read evidence and NOT VERIFIED

Read: ADR-0016; ADR-0014; SERVER-AUTH-DESIGN-NOTE.md; CLIENT-SERVER-DESIGN-NOTE.md; existing LARGE-GUIDE-HANDLE-NOTE.md; `Write-ChannelForgeTrimmedXmltvGuide`, `Import-ChannelForgeXmltvSource`, `Build-Lineup.ps1` references, and `gui/src/app/guidedSetupProposal.ts`. Reused helpers: `Write-ChannelForgeTrimmedXmltvGuide` and the existing `Import-ChannelForgeXmltvSource` flow are the identified trim/import path; implementation integration is not asserted.

Observed: local XMLTV imports can trim to playlist IDs via a streaming trimmer and temporary file, then hash the trimmed file bytes; the browser rejects guides over 12 MB before base64 encoding and currently directs users to the desktop app or command line.

NOT VERIFIED: PR #259 and #260 implementation details, desktop app behavior (it is described as old/optional in current architecture), exact current server limits and routes, server import-root support, authentication implementation, Docker mounts and Windows service permissions, handle security details, and support for 1.8 GB. No product code or runtime was run.
