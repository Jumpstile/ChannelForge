# ChannelForge Onboarding

Start here before engineering changes.

ChannelForge is an evidence-driven PowerShell project for building accurate, trustworthy, deterministic television lineups. Do not implement before you understand the project source of truth, safety rules, architecture, and current project memory.

## First Steps

1. Verify your environment before engineering:
   - Confirm the working directory is the intended ChannelForge repository.
   - Check `git status`.
   - Check `git remote -v`.
   - Confirm expected project files are present, including `README.md`, `CONSTITUTION.md`, `AI_COLLABORATION.md`, `ROADMAP.md`, `src/`, and `docs/`.
2. Read [CONSTITUTION.md](CONSTITUTION.md).
3. Read [AI_COLLABORATION.md](AI_COLLABORATION.md).
4. Read [PROJECT.md](PROJECT.md).
5. Read [PRINCIPLES.md](PRINCIPLES.md).
6. Read [docs/reference/SECURITY.md](docs/reference/SECURITY.md).
7. Read [docs/developer/FIRST_READ.md](docs/developer/FIRST_READ.md).
8. Read the ADRs in [docs/adr](docs/adr).
9. Review [ROADMAP.md](ROADMAP.md) and relevant GitHub Issues before choosing implementation work.
10. Read the relevant architecture, developer, and engineering docs for the change.

## Canonical Project Memory

- Repository docs are the engineering source of truth.
- ADRs preserve accepted architecture decisions.
- GitHub Issues are project memory for bugs, feature requests, release blockers, follow-ups, and decisions that need tracking.
- Generated outputs are disposable artifacts unless a governing document says otherwise.

## Before Implementation

Do not implement before you can answer:

- What problem is being solved?
- What evidence supports the change?
- What is the source of truth?
- Which ADRs or docs constrain the design?
- What tests or checks will verify the result?
- What security, regression, or user-data risk exists?

If the repository does not answer a material question, ask the user or capture the uncertainty as follow-up work.
