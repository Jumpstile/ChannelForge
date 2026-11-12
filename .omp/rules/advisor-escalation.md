---
description: Evidence-backed advisor disposition and explicit Sol escalation
alwaysApply: true
agents: [main]
---

Keep GPT-5.6 Luna as the primary OMP model. RoutineReview (Claude Sonnet 5) is the
normal enabled advisor. EscalationReview (GPT-5.6 Sol High) stays disabled unless the
user explicitly enables it. Never auto-dispatch sol-escalation or auto-enable Sol.
Recommend /escalate for architecture, contradictory evidence, determinism/provenance,
final PR/release gates, or disputed advisor findings, and wait for explicit invocation.

Every advisor finding must be explicitly dispositioned with evidence; no silent ignores.
Maintain a finding table in the response or existing authorized review record: ID,
source/test/runtime/release claim, accepted/fixed or rejected or deferred/blocked,
supporting/counter-evidence, and remaining action/owner. Rejection needs counter-evidence;
deferral needs a reason and next verification. Unresolved findings are not passed.
Do not claim tests ran from source inspection or runtime certification from tests.
Preserve exact SHA/environment/artifact provenance and all project-specific rules.
Reviews do not grant commit, push, merge, deployment, or release authority.

For a one-shot user invocation, use task agent sol-escalation with its configured
Sol High model, no effort override, no fallback substitution, and a bounded evidence
packet. Return to Luna to disposition results. For continuous escalation, the user
uses /advisor configure to enable EscalationReview and disables it after the review.
/advisor off stops all advisors, including routine Sonnet; it is not the escalation-only switch.
