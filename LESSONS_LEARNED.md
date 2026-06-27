\# Lessons Learned



This document captures important lessons discovered while building ChannelForge.



A lesson may come from a bug, design change, security review, failed assumption, user experience issue, or release.



The goal is not blame. The goal is institutional memory.



\## Entry template



\### YYYY-MM-DD - Short title



\*\*Area:\*\* Architecture | Bug | Security | Testing | Documentation | User Experience | Release



\*\*What happened?\*\*



Describe the event or discovery.



\*\*Why did it happen?\*\*



Explain the root cause or decision context.



\*\*What changed?\*\*



Describe the fix, redesign, test, document update, or process change.



\*\*How do we prevent it from happening again?\*\*



List regression tests, checklist updates, ADRs, or review steps.



\---



\## 2026-06-26 - IPTVBoss first layout crash required source user



\*\*Area:\*\* Bug / Architecture



\*\*What happened?\*\*



IPTVBoss 3.10.5 crashed after creating and saving the first layout in a fresh database.



\*\*Why did it happen?\*\*



Decompilation showed that IPTVBoss attempted to call `getFirst()` on the source user list when loading a layout. A fresh database had no users, so layout loading failed with `NoSuchElementException`.



\*\*What changed?\*\*



The working process now requires creating `USER1` through Sources -> Manage Users before creating the first layout.



\*\*How do we prevent it from happening again?\*\*



Document first-run order clearly. Treat GUI state as unreliable unless validated. Prefer ChannelForge-owned source-of-truth configuration over undocumented GUI assumptions.

