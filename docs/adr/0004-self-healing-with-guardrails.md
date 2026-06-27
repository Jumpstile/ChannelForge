\# ADR 0004: Self-healing with guardrails



\## Status



Accepted



\## Context



Provider playlists, channel names, guide IDs, logos, and EPG sources may change over time. ChannelForge should detect drift and repair safe changes automatically where possible.



\## Decision



ChannelForge will support self-healing behavior with strict guardrails.



Repairs are divided into three levels:



1\. Auto-fix

&#x20;  - High confidence

&#x20;  - Safe

&#x20;  - Reversible

&#x20;  - Fully documented in build reports



2\. Suggest fix

&#x20;  - Medium confidence

&#x20;  - Requires user approval

&#x20;  - Included in review reports



3\. Block build

&#x20;  - Low confidence

&#x20;  - Ambiguous

&#x20;  - Security-sensitive

&#x20;  - Could corrupt lineup or production output



\## Consequences



\- No risky repair happens silently.

\- Every automatic repair must explain why it was made.

\- Every repair must be logged in the flight recorder.

\- Self-healing must preserve backups and rollback.

\- User trust is more important than automation speed.

