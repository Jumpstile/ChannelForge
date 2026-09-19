# First Usable Alpha Release Readiness

Status: `NOT_RELEASE_READY`

Target release: `v0.1.0-alpha.1`

Tracking issue: #164

## Purpose

This plan separates repository publication from product release readiness.

The ChannelForge repository is public, protected, and has passed post-merge
hosted validation on `main`. That work is complete. The next gate is whether a
normal IPTV user can install, start, configure, accept, restart, refresh, and
understand ChannelForge without a development environment.

ChannelForge remains **Early Alpha** until this gate is complete.

## Product principle

> Automate the obvious. Learn from corrections. Interrupt only when uncertainty matters.

## Release gate

The first downloadable alpha is authorized only when all of the following are
true:

- [ ] A user can install and start ChannelForge without setting up a developer
      environment.
- [ ] ChannelForge Guided Setup / Beginner Workflow works end-to-end through the
      intended user-facing surface.
- [ ] A user can provide an M3U playlist and optional XMLTV source; no-guide mode
      remains supported.
- [ ] Exact mapping is automated and uncertainty is surfaced clearly enough to
      block unsafe publication when review matters.
- [ ] Explicit acceptance promotes only through the immutable accepted-generation
      boundary.
- [ ] Accepted configuration and state survive restart, and stable reruns are
      recognized without forcing setup to be repeated.
- [ ] Normal source refresh/update works without forcing the user to redo setup.
- [ ] The user can see what ChannelForge produced, whether it is accepted, and
      what needs attention.
- [ ] Update/upgrade behavior for the alpha is defined and beginner-readable.
- [ ] Install/start/setup/accept/restart/refresh is smoke-tested from a clean
      supported environment.
- [ ] A release/tester artifact is reproducibly produced from an exact green
      commit by a documented process.
- [ ] Required CI, secret scan, packaging validation, and clean-install smoke
      evidence are green at the release-candidate SHA.
- [ ] Install, first-run, troubleshooting, limitations, update, and uninstall
      documentation are synchronized and understandable without prior
      ChannelForge knowledge.

## Alpha.1 scope boundary

The following are not required for `v0.1.0-alpha.1` unless implementation
shows that they are prerequisites for the release gate above:

- complete event-guide automation;
- automatic AED adoption or relearning;
- full expert regex/date/time authoring;
- every planned deployment target; and
- 1.0-level compatibility breadth.

These remain legitimate follow-on work. Their absence must stay visible in
Current Limitations and release notes.

## Evidence required at release authorization

Before creating `v0.1.0-alpha.1`, record:

1. the exact release-candidate commit SHA;
2. required hosted CI results for that SHA;
3. secret-scan result for that SHA;
4. packaging/build reproduction result;
5. clean-machine install/start/setup/accept/restart/refresh smoke evidence;
6. the exact artifact hashes;
7. confirmation that documentation matches shipped behavior; and
8. the owner/gatekeeper release authorization.

## What repository publication already proved

The repository-publication gate is closed. Evidence includes:

- GitHub Support historical de-reference cleanup completed;
- hosted branch/tag tip privacy scanning completed with no classified findings;
- repository visibility is public;
- GitHub private vulnerability reporting is enabled;
- `Main-Protection` remains enforced;
- required `secret-scan` and `quality-gates` checks remain enforced;
- PR #163 merged; and
- post-merge public `main` CI passed on
  `9879b302709e8d9c72a7c4dd552add5ce031a5f1`.

Do not reopen the old repository-publication gate unless new evidence shows a
real regression in one of those controls.

## Release boundary

Public repository visibility does not equal a product release.

Do not create a release, tag, package, or tester build merely because the
repository is public or CI is green. The gate in issue #164 must be complete
with exact-head evidence first.
