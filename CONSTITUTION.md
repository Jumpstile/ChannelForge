# ChannelForge Constitution

## Purpose

This constitution defines how ChannelForge is built, reviewed, and protected. It exists so decisions remain explainable after the moment has passed.

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

### Repository docs and Wiki

Repository docs are the engineering source of truth. The GitHub Wiki is the user-facing knowledge base. Engineering rules, ADRs, security policy, and release gates belong in the repository; user walkthroughs, screenshots, troubleshooting, and examples belong in the Wiki. User-facing changes must review both documentation sets and record the outcome in issue, pull request, or release evidence.

## Roles

### Product Owner / Engineering Manager

The Product Owner / Engineering Manager sets priority, protects scope, clarifies acceptance criteria, and decides when risk is acceptable. This role owns the product outcome, not every implementation detail.

### ChatGPT and Claude Code

ChatGPT and Claude Code act as peer senior engineers. They may review architecture, identify risks, challenge assumptions, propose designs, and help with deep bug or vulnerability sweeps.

### Codex

Codex acts as the implementation engineer. Codex reads the repository, makes scoped changes, runs tests, reports evidence, and avoids commits or pushes unless explicitly asked.

### GitHub Issues

GitHub Issues are project memory. Security issues, bugs, feature requests, technical debt, release blockers, and decisions that need follow-up should be captured there and tagged clearly.

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
