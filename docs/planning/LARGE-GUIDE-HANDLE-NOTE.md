# Design note: large guide by server-issued handle (261-A)

This is a design note. It adds no code and no tests. Nothing was run. Existing size limits in the engine were not read; the numbers below are proposals.

## Problem

A guide file can be too large to send from the browser. With the server on another machine, the browser also cannot see the server's disk. ADR-0016 and the lineup workspace note say the browser never sends a path and never reads files.

## Idea

The server reads a large guide from its own disk. The browser only names it by a handle the server issued.

## Flow

1. The browser asks the server for the list of guide files in the server's allowed import folder: `GET /api/guides/available`. Each row has a `handle`, a display name, size and modified time. No path.
2. The user picks one. The browser sends `{ "handle": "..." }` in the normal source-add request.
3. The server resolves the handle to a file inside the import folder, opens it, and checks it before use.
4. The server reads it through the existing bounded stream code. Nothing is loaded whole into memory.

## Handle rules

- Opaque, random, issued by the server. Not a path, not a file name.
- Maps to a file only under the configured import folder. The server resolves the real path and refuses anything that leaves the folder, including links and `..`.
- Valid for a limited time and only for the issuing session. A stale handle gets a plain error.
- The server never returns the real path to the browser, logs, or reports.

## Limits (proposals, owner decision needed)

| Limit                                | Proposal                                                      |
| ------------------------------------ | ------------------------------------------------------------- |
| Max file size on disk                | Use the existing engine guide limit if one exists; else 1 GiB |
| Max expanded size (compressed files) | Existing bounded decompression limit                          |
| Handle lifetime                      | 15 minutes                                                    |
| Files listed per request             | 100, paged                                                    |

Owner decision needed: the size limit. Options: reuse the existing guide limit; set a new higher limit for local-disk guides. Recommendation: reuse the existing limit and raise it only with evidence from a real large guide.

Owner decision needed: how files reach the import folder. Options: user copies them there; upload through the browser into the folder. Recommendation: user copies them. Upload is a separate note.

## Error wording

Plain words, no paths:

- Unknown or expired handle: "That guide file is no longer available. Pick it again from the list."
- Too large: "This guide is larger than the limit of {limit}. Use a smaller file or ask the owner to raise the limit."
- Not a readable guide: "This file could not be read as a guide. Nothing was changed."
- Outside the import folder or missing: "That guide file was not found. Nothing was changed."
- Read failed partway: "Reading the guide stopped before the end. Nothing was changed."

Failures never change accepted state and never publish a partial result.

## Not done here

No route, no code, no change to the guide-id contract.
