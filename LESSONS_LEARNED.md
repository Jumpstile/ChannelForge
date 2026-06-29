# Lessons Learned

This document captures important lessons discovered while building ChannelForge.

A lesson may come from a bug, design change, security review, failed assumption, user experience issue, or release.

The goal is not blame. The goal is institutional memory.

## Entry template

### YYYY-MM-DD - Short title

**Area:** Architecture | Bug | Security | Testing | Documentation | User Experience | Release

**What happened?**

Describe the event or discovery.

**Why did it happen?**

Explain the root cause or decision context.

**What changed?**

Describe the fix, redesign, test, document update, or process change.

**How do we prevent it from happening again?**

List regression tests, checklist updates, ADRs, or review steps.

---

## 2026-06-28 - Tracked provider URLs exposed private subscription data

**Area:** Security / Documentation / CI

**What happened?**

Tracked provider and EPG configuration files contained private subscription-style provider URLs. A unit test also asserted one private provider URL directly.

**Why did it happen?**

The project had a secrets policy, but the source-of-truth example files were created before automated secret scanning and local-only provider file conventions were fully enforced.

**What changed?**

Tracked provider and EPG files were replaced with `https://example.invalid/...` placeholders. Real provider files now belong in ignored `*.local.json` or `*.local.csv` files. The provider parser test was changed to use placeholders, `SECURITY.md` was updated, and Gitleaks was added to CI.

**How do we prevent it from happening again?**

Run secret scanning in CI, treat provider URLs as secrets, keep real provider data in local-only files, and capture security findings as GitHub Issues with the `security` label.

---

## 2026-06-26 - IPTVBoss first layout crash required source user

**Area:** Bug / Architecture

**What happened?**

IPTVBoss 3.10.5 crashed after creating and saving the first layout in a fresh database.

**Why did it happen?**

Decompilation showed that IPTVBoss attempted to call `getFirst()` on the source user list when loading a layout. A fresh database had no users, so layout loading failed with `NoSuchElementException`.

**What changed?**

The working process now requires creating `USER1` through Sources -> Manage Users before creating the first layout.

**How do we prevent it from happening again?**

Document first-run order clearly. Treat GUI state as unreliable unless validated. Prefer ChannelForge-owned source-of-truth configuration over undocumented GUI assumptions.
