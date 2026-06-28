# Repository Docs and GitHub Wiki

## Repository Docs Are Engineering Source of Truth

Documentation in this repository is versioned with the code. It is the engineering source of truth for architecture, safety rules, contribution workflow, ADRs, checklists, security policy, and release gates.

Use repository docs for:

- Architecture decisions.
- Engineering standards.
- Security policy.
- Source-of-truth configuration rules.
- Release and review checklists.
- Contributor workflow.
- Lessons learned.

Repository docs must change in the same branch as the engineering behavior they describe.

## GitHub Wiki Is the User Knowledge Base

The GitHub Wiki should become the beginner-friendly user knowledge base. It can be more tutorial-oriented, screenshot-heavy, and task-focused than repository engineering docs.

Use the Wiki for:

- First-run guide.
- IPTVBoss Pro token guide.
- EPG source guide.
- Alias review guide.
- Troubleshooting.
- Screenshots and walkthroughs.
- Examples of user projects ChannelForge can support.

## Synchronization Rule

If a Wiki page describes behavior controlled by code, configuration, security policy, or release gates, the repository docs remain authoritative. Update repository docs first, then update the Wiki.

## Issue Tracking

Wiki work should be tracked in GitHub Issues with the `wiki` and `documentation` labels.
