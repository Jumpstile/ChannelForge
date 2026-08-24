# ADR 0015: Local worktrees and GitHub-only cross-machine handoffs

## Status

Accepted

## Context

ChannelForge has been operated from more than one local checkout and from
shared mapped-drive or UNC locations. A shared NAS Git worktree is not a safe
coordination mechanism: different machines can hold different revisions,
credentials, index state, worktree metadata, and uncommitted user changes.
Network availability also varies by process and machine, so a successful read
from one session does not prove that another agent can safely use the same
checkout.

The previously used `Y:\ChannelForge` checkout and its corresponding shared
NAS locations are preserved user data. They are not being deleted, renamed,
cleaned, or rewritten by this decision.

## Decision

- GitHub is the authoritative source for ChannelForge history, branches,
  reviews, and merged content.
- Every machine and agent works from its own local clone or local Git
  worktree. The local checkout must be verified with its repository root,
  remote, branch, HEAD, and status before work begins.
- A GitHub review or feature branch is the only cross-machine handoff. Agents
  must fetch the branch into a fresh local clone or worktree instead of copying
  a working directory or using a shared NAS checkout.
- NAS storage may hold backups, source data, generated artifacts, and
  repository mirrors. It must not be used as a shared active Git worktree for
  engineering changes.
- `Y:\ChannelForge` is de-authorized as an engineering checkout. Preserve it
  in place for user-controlled inventory, backup, or later migration decisions;
  do not edit, stage, commit, push, delete, rename, or reset it as part of the
  normal agent workflow.
- Repository scripts and documentation must use repository-relative paths,
  the verified local repository root, or explicit user-selected data paths.
  They must not require an active UNC/SMB Git worktree or hard-code a mapped
  development checkout. Backup scripts must receive machine-specific NAS
  source paths explicitly; they must not embed a host-specific default.
- A healthy runtime deployment or generated artifact on NAS is a separate
  operational concern. This decision does not authorize replacing, cleaning,
  or redeploying it.

## Required handoff sequence

1. Start from a fresh local clone or local worktree of the GitHub repository.
2. Verify `git remote`, branch, exact HEAD, status, and the intended file scope.
3. Make and validate the change locally.
4. Push only the review branch when publication of the handoff is authorized.
5. The receiving machine fetches that branch into its own local checkout and
   reviews the exact commit and changed paths.
6. Merge, release, deployment, or NAS mirror actions remain separate explicit
   decisions.

## Consequences

- A disconnected or unavailable NAS share cannot silently become the source of
  engineering truth.
- Dirty or stale NAS worktrees remain recoverable user data without being part
  of the active workflow.
- Agents must repeat small repository-identity checks, but those checks make
  stale-revision and split-brain failures visible before edits begin.
- Local source-data paths may still be network-backed when the product
  explicitly supports them; that does not make the Git checkout network-backed.
