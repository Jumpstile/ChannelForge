# ChannelForge Constitution

## Purpose

This constitution defines how ChannelForge is built, reviewed, and protected. It exists so decisions remain explainable after the moment has passed.

## Policy Precedence

When repository guidance appears to conflict, apply it in this order:

1. Owner directives and repository governance, including this Constitution.
2. Accepted ADRs and security or release policies.
3. Standing engineering workflow policies, including the local-worktree and GitHub-handoff policy in issue #92.
4. Role-specific entrypoint instructions such as `CHATGPT.md`, `CLAUDE.md`, and `CODEX.md`.
5. Task-specific issue and pull-request instructions.
6. Historical notes and examples.

A lower level may clarify a higher level but must not override it. Historical material is context only unless it is explicitly reaccepted. If a material conflict remains, stop, preserve the evidence, and record it for resolution rather than guessing.

## Core Principles

### Evidence over assumptions

Every important decision must be grounded in repository evidence, user-approved facts, tests, logs, documentation, or reproducible behavior. If evidence is missing, say it is missing.

### Environment Verification Before Engineering

Before engineering work begins, confirm the working directory, Git status, Git remote, and expected repository structure. Do not assume the active shell, checkout, or branch is the intended ChannelForge environment.

### Single Source of Truth

Repository docs, ADRs, source data, and tests are the authoritative engineering record. Adapter files, chat transcripts, generated outputs, local tool state, and external GUIs must point back to canonical repository sources instead of redefining policy.

### Repository Independence

ChannelForge must remain understandable, buildable, and governable from the repository itself. Local machine state, external applications, private configuration, and generated artifacts may support workflows, but they must not be required to understand project rules or accepted architecture.

### Trust but continuously verify

ChannelForge should be trusted because it verifies itself. Passing tests, green CI, documented decisions, review checklists, and repeatable outputs are part of the product.

### Security first

Secrets, provider URLs, generated playlists, XMLTV data, logs, backups, and production paths are sensitive. Security is not a final pass. It is part of every design, implementation, test, and release decision.

### Deterministic behavior

The same inputs must produce the same meaningful outputs. Non-determinism must be intentional, documented, and isolated.

### Documentation is part of the product

A feature is incomplete until a careful beginner can understand what it does, why it matters, how to use it, how to verify success, and how to recover from failure.

### Tests before commits

Relevant tests must pass before a commit. Failing tests are evidence, not noise.

### Deep bug and vulnerability sweeps

Before release, ChannelForge must receive deliberate bug, regression, and vulnerability review. A build that merely works once is not release-ready.

### Self-healing with guardrails

ChannelForge may repair safe, high-confidence issues automatically. Ambiguous, risky, destructive, or security-sensitive changes require review and approval.

### User experience is engineering

The user experience is not decoration. Clear messages, predictable workflows, safe defaults, previews, approvals, and recovery paths are engineering responsibilities.

### Institutional knowledge

Lessons learned, ADRs, issues, checklists, and release notes preserve project memory. Important discoveries should become durable artifacts.

### Repository docs and user documentation

Repository docs are the engineering source of truth. [`docs/user/`](docs/user/README.md) is the user-facing knowledge base. Engineering rules, ADRs, security policy, and release gates belong in the repository; user walkthroughs, screenshots, troubleshooting, and examples belong in `docs/user/`. User-facing changes must review both documentation sets and record the outcome in issue, pull request, or release evidence.

## Roles

### Product Owner / Engineering Manager

The Product Owner / Engineering Manager sets priority, protects scope, clarifies acceptance criteria, decides when risk is acceptable, and owns landing and release decisions. This role owns the product outcome, not every implementation detail.

### Review and coordination

Review and coordination contributors assess architecture, security and release impact, scope, governance, and handoff evidence. They may maintain issue and pull-request evidence when the task authorizes it, but they do not override higher-level policy, accept product scope, or independently authorize merge or release.

### Implementation and validation

Implementation and validation contributors read the repository, make scoped changes, run tests, and report exact evidence. Independent validation confirms the pushed branch and commit when required. This role does not expand scope or self-authorize commit, push, merge, or release actions.

### GitHub and tracker authority

GitHub is the authoritative cross-machine handoff and repository state. GitHub Issues and pull requests are project memory for security issues, bugs, feature requests, technical debt, release blockers, evidence, and decisions that need follow-up. They record and coordinate work but do not override higher-level policy or independently authorize merge or release.

## Definition of Done

A change is done only when:

- The problem and evidence are understood.
- The design fits the established architecture.
- The implementation is scoped and readable.
- Relevant tests pass locally.
- Documentation is updated.
- Security impact is reviewed.
- Bug and regression risk is reviewed.
- Any needed ADR, checklist, or issue update is complete.
