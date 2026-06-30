# FIRST READ

> **Read this document before writing a single line of code.**

Welcome to ChannelForge.

This project is intentionally engineered differently from many software projects.

Before contributing, read these documents in order:

1. [Project Charter](../architecture/PROJECT_CHARTER.md) — mission, success criteria, non-goals
2. [Manifesto](../architecture/MANIFESTO.md) — the five pillars and the golden rule
3. [Engineering Principles](../engineering/ENGINEERING_PRINCIPLES.md) — safety, testing, security, backup, and release rules
4. [Channel Identity Model](../architecture/CHANNEL_IDENTITY_MODEL.md) — why provider labels are evidence, not truth
5. [Style Guide](../../STYLEGUIDE.md) — naming, comments, error handling, and validation standards

Understanding these documents is more important than understanding the code.

---

## Our Mission

ChannelForge exists to produce accurate, trustworthy, deterministic television lineups through verifiable evidence, transparent decision-making, and uncompromising engineering discipline.

We are not building "just another IPTV tool."

We are building an evidence-driven television knowledge engine.

---

## Before Writing Code

Ask yourself:

- What problem am I solving?
- Is there already an engine responsible for this?
- What is the source of truth?
- Can this decision be explained?
- Can this be tested?
- Can this be reversed?
- Does this improve trust?

If you cannot answer these questions, stop and review the architecture.

---

## Engineering Principles

Every important decision should be:

- Explainable
- Reproducible
- Reversible

Every change should include:

- Documentation
- Tests
- Security review
- Regression review

For the complete set of safety rules, backup requirements, and release gates, see [Engineering Principles](../engineering/ENGINEERING_PRINCIPLES.md).

For the definition of done, see [CONSTITUTION.md](../../CONSTITUTION.md).

---

## Philosophy

ChannelForge does not guess.

ChannelForge verifies.

Truth is established through evidence, not assumptions.

User-approved data is always the highest authority.

---

## Final Thought

Write code as though the next developer knows nothing.

One day, that developer may be you.

Build software people can trust.
