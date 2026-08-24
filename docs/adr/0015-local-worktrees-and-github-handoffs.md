# ADR 0015: Local worktrees and GitHub-only cross-machine handoffs

## Status

Accepted

## Context

ChannelForge has historical references to more than one checkout and to shared
mapped-drive or UNC locations. A shared NAS Git worktree is not a safe
coordination mechanism: different machines can hold different revisions,
credentials, index state, worktree metadata, and uncommitted user changes.
Network availability also varies by process and machine, so a successful read
from one session does not prove that another agent can safely use the same
checkout.

The previously used `Y:\ChannelForge` path and associated shared locations are
historical, preserved user-controlled data. They are not current engineering
guidance, and this ADR does not authorize inspecting, editing, deleting,
renaming, cleaning, resetting, or rewriting them.

## Decision

- GitHub is authoritative for ChannelForge history, branches, reviews, and
  merged content.
- Every machine and agent works from its own independent local clone or local
  Git worktree. Before work begins, verify the repository root, remote, branch,
  exact HEAD, and status.
- The canonical desktop engineering checkout example is
  `C:\REPOS\ChannelForge`. A second-machine validation checkout example is
  `E:\REPOS\ChannelForge`. These are independent local-clone examples, not
  shared paths; record and verify the actual local repository root used for
  each validation.
- A pushed GitHub review or feature branch is the only cross-machine handoff.
  A receiving machine fetches the exact ref or SHA into its own local checkout;
  it does not copy a working directory or use a shared NAS checkout.
- NAS, mapped-drive, synchronized, and SMB paths may hold source data, outputs,
  caches, staging content, evidence, backups, packages, mirrors, or an
  explicitly authorized runtime deployment. They must not be authoritative
  active Git worktrees for implementation, review, validation, or release work.
- Historical notes and examples must be labeled historical or non-authoritative
  when they describe an old checkout, handoff path, or operating procedure.
- Repository scripts and documentation must use repository-relative paths, the
  verified local repository root, or explicit user-selected data paths. They
  must not require an active UNC/SMB Git worktree or hard-code a mapped
  development checkout.

## Boundary with runtime path safety

Runtime path guards classify paths by role and canonical containment. A guard
that rejects a UNC or absolute path for a specific input under
`data/playlists/` or `data/providers/` is a product safety rule for that input;
it is not a blanket statement that every NAS-backed source-data, output, cache,
staging, evidence, backup, package, mirror, or deployment path is invalid.

The Git workspace rule is separate: a shared NAS Git worktree is never
engineering evidence, even when a NAS path is valid for another role.

## Required handoff sequence

1. Start from an independent local clone or local worktree of the GitHub
   repository.
2. Verify the remote, branch, exact HEAD, status, intended file scope, and
   expected ancestry or baseline.
3. Make and validate the change locally.
4. Push only the review branch when publication of the handoff is authorized.
5. The receiving machine fetches the exact branch or SHA into its own local
   checkout and reviews the exact commit and changed paths.
6. Merge, release, deployment, or NAS mirror actions remain separate explicit
   decisions.

## Evidence requirements

Validation and release evidence records the local checkout path, branch, HEAD,
origin ref, clean status, ancestry or baseline, and package or artifact commit
identity. A shared NAS Git worktree, a dirty checkout, or an unverified mirror
is not implementation, review, validation, or release evidence.

## Consequences

- A disconnected or unavailable NAS share cannot silently become the source of
  engineering truth.
- Dirty or stale historical worktrees remain recoverable user data without
  becoming part of the active workflow.
- Agents repeat small repository-identity checks, making stale-revision and
  split-brain failures visible before edits begin.
- Local source-data paths may still be network-backed when the product
  explicitly supports them; that does not make the Git checkout network-backed.
