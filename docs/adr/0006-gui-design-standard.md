# ADR-0006: GUI design standard

## Status

Accepted

## Context

Issue #10 ("Define the GUI-first product path") commits ChannelForge to a GUI-first experience, but no design standard existed to govern _how_ that GUI should be designed. Without one, GUI work risks becoming a collection of ad hoc screens shaped by internal architecture rather than user goals, with no consistent approach to safety, feedback, or error prevention — directly at odds with ChannelForge's existing five pillars (Truth, Trust, Recoverability, Determinism, Self-Healing; see the [repository README](../../README.md#five-pillars)) and its evidence-over-assumptions principle ([ADR 0005](0005-evidence-over-assumptions.md)).

These are established product design principles, not cosmetic UI preferences, drawn from:

- Don Norman — _The Design of Everyday Things_
- Alan Cooper — _About Face_
- Steve Krug — _Don't Make Me Think_ (optional supporting influence)

## Decision

All GUI design for ChannelForge — Issue #10 and every GUI-related issue after it — must follow these rules:

1. Design around user goals, not internal architecture.
2. Make system state visible.
3. Make safe workflows the default workflows.
4. Prevent errors before reporting them.
5. Prefer recognition over recall.
6. Use progressive disclosure.
7. Minimize unnecessary choices.
8. Provide immediate, understandable feedback.
9. Make recovery from mistakes obvious and safe.
10. Never encourage editing tracked files or exposing secrets.
11. Explain what happened after every major operation.
12. Every screen must answer: "What is the user trying to accomplish?"

Rule 10 is a ChannelForge-specific application of [ADR 0002](0002-secrets-policy.md) and the Issue #20 local-only configuration workflow (see [Safe Local Configuration](../user/SAFE_LOCAL_CONFIGURATION.md)) to the GUI surface specifically: a GUI must never present a workflow whose easiest or default path is editing a tracked file or exposing a secret, even if an unsafe path is technically possible.

GUI work must produce, and have reviewed, the following **before** any visual mockup or implementation begins:

- **Personas** — who is actually using this GUI.
- **User journeys** — the paths a persona takes through the product to accomplish a goal.
- **Task flows** — the concrete steps within a journey, independent of any specific screen design.
- **Safety model** — what's reversible, what requires confirmation, what's prevented outright.
- **Feedback model** — how system state and the result of every action are communicated.
- **Error prevention model** — how mistakes are made structurally hard before they're merely reported.

This UX architecture must be reviewed before GUI implementation begins. Mockups and implementation are downstream of this work, not a substitute for it.

## Consequences

- GUI issues (starting with #10) are scoped around user journeys and task flows, not screens or features, before any implementation work is estimated or started.
- A GUI feature that cannot be explained in terms of "what is the user trying to accomplish" is a signal to redesign, not just to add UI to.
- This raises the up-front design cost of GUI work but reduces the risk of building an interface that exposes unsafe configuration patterns, hides the deterministic build pipeline behind opaque buttons, or surprises a user with a change they didn't anticipate.
- Existing engineering principles already require explainability and reversibility ([ADR 0005](0005-evidence-over-assumptions.md), [CONSTITUTION.md](../../CONSTITUTION.md)); this ADR extends those same expectations explicitly into the GUI layer rather than leaving them implicit.

## Verification

- Issue #10 (and any GUI issue after it) includes documented personas, user journeys, task flows, a safety model, a feedback model, and an error prevention model before implementation work begins.
- GUI design review checks each of the twelve rules above explicitly, not just visual polish.
- No GUI workflow ships whose default or easiest path requires editing a tracked file or exposes a secret (rule 10) — this is checked the same way Issue #20's local-only configuration workflow is checked for the CLI today.
- Documentation: this ADR is linked from Issue #10 and any future GUI-related issue.

## Related Issues

- #10
