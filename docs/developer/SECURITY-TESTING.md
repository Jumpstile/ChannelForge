# ChannelForge security-testing roadmap

> Status: Implemented CI baseline; promotion/recovery runtime testing remains
> gated on explicit authorization for that runtime work.

This page explains what runs automatically, what a contributor can run locally,
and which scanners are intentionally deferred. It is written for the current
repository, not for a hypothetical native build.

## What this repository actually builds

ChannelForge is a PowerShell 7.6 Core module hosted on .NET 10. It has one
tracked C# source file,
`src/ChannelForge/Private/Transport/ChannelForgePinnedHttpTransport.cs`, which
is compiled at runtime by a fixed `Add-Type` loader.

There is currently no C++ source, C++ project, `.sln`, `.vcxproj`, CMake file,
native compiler target, or produced Windows `.exe`/`.dll` artifact in this
checkout. That is why the active native-tool plan is deliberately narrow:

- CodeQL analyzes the tracked C# transport in `none` build mode and analyzes
  GitHub Actions workflows.
- Semgrep uses repository rules that work on PowerShell and generic text, plus
  a C# certificate-validation rule.
- Gitleaks, frozen-byte verification, dependency review, and the SBOM job are
  active now.
- MSVC `/analyze`, Clang-Tidy, AddressSanitizer, and BinSkim are deferred. They
  become applicable only when a native source/build/output surface is added.
  A future activation must provide the real build command, compiler/toolchain
  version, output directory, and a Windows adversarial test before claiming a
  native PASS.

## CI matrix

| Gate                             | Trigger                                  | Environment                               | Scope                                                                                                                                |
| -------------------------------- | ---------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Existing PowerShell quality gate | Main pushes and pull requests            | Windows, PowerShell 7.6/.NET 10           | Formatting, config/docs, PSScriptAnalyzer, and full Pester                                                                           |
| Security fast checks             | Every push and pull request, plus manual | Ubuntu; Gitleaks, Semgrep, and PowerShell | Secret scan, custom Semgrep rules, and frozen v9/v8 byte fingerprints                                                                |
| CodeQL                           | Pull requests/main, weekly, and manual   | Ubuntu                                    | C# transport and GitHub Actions workflows; `security-extended` queries                                                               |
| Dependency review                | Pull requests                            | Ubuntu                                    | New dependency vulnerabilities at moderate severity or higher                                                                        |
| SBOM                             | Pull requests, main, and manual          | Ubuntu                                    | SPDX inventory of repository-visible dependencies; uploaded for 14 days only                                                         |
| Security gated validation        | Pull requests/main and manual            | Windows, PowerShell 7.6/.NET 10           | Contract-oracle tests, deterministic path/URL mutations, C# loader/transport adversarial tests, destructive-path tests, and analyzer |

The SBOM workflow sets `upload-release-assets: false` and only uploads a
short-lived workflow artifact. None of these workflows merges, tags, packages,
publishes, or releases anything.

## Run the useful checks locally

From the repository root:

```powershell
npm ci
npm run format:check
pwsh -NoLogo -NoProfile -File .\scripts\security\Test-FrozenContractIntegrity.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Validate-ScriptAnalyzer.ps1
Invoke-Pester -Path .\tests\security -CI
Invoke-Pester -Path .\tests\unit -CI
```

If Docker is available, run the same custom Semgrep rules locally:

```powershell
docker run --rm -v "${PWD}:/src" -w /src semgrep/semgrep scan --config .semgrep --error --metrics=off
```

Gitleaks is already part of the PowerShell CI workflow. A local installation
can run its normal repository/history scan with redaction enabled; do not add
real provider URLs or credentials merely to exercise the scanner.

## Adversarial and property-style coverage

`tests/security/ChannelForgeSecurityAdversarial.Tests.ps1` currently exercises
the live code that exists:

- deterministic accepted/rejected path mutations, including traversal,
  sibling-prefix, UNC, drive/system, and empty values;
- HTTPS, credential, local-address, reserved-address, and malformed URL
  mutations;
- the C# transport's fail-closed certificate-validation source invariants; and
- the frozen acceptance journal/recovery contract's legal phase set, every
  publication/reopen boundary, first-match predicates, and mixed-generation
  A-J rejection matrix.

The repository has not authorized the #103 promotion/recovery runtime in this
checkout. The journal tests therefore verify the authoritative contract text;
they do not claim process-kill, restart, pointer-swap, FileIdentity, or
TOCTOU runtime certification. Once that runtime is explicitly authorized, the
next gated slice must add real fault hooks and process-level tests for every
implemented A01-A60 hook, every legal journal phase, every publication and
recovery boundary, first-generation and Generated/NotGenerated XMLTV vectors,
live/stale locks, safe-handle identity changes, reparse/path substitution,
cross-volume rejection, mixed OLD/NEW state, and no-mutation recovery. A hook
must not be invented or silently omitted to make the matrix green.

## Native-tool activation rule

When a real native target appears, add a separate gated job with these
evidence requirements:

1. MSVC `/analyze` (or the documented equivalent) against the exact Windows
   build target.
2. Clang-Tidy using the generated `compile_commands.json`, with the selected
   `bugprone`, `cert`, and `concurrency` checks recorded.
3. AddressSanitizer runtime tests on a supported compiler/configuration,
   including a reproducible failing-memory fixture and a clean run.
4. BinSkim against the exact produced PE files, with SARIF retained as the
   gated artifact.

Until those inputs exist, the correct result for all four is **NOT APPLICABLE**,
not a green or release-quality claim.

## Evidence boundary

A successful fast check, gated workflow, CodeQL alert upload, or SBOM artifact is
validation evidence only. It does not authorize a merge, contract change,
package, tag, publication, or release. The frozen contract files remain
protected by exact-byte fingerprints; changing a normative byte requires the
governed new revision and freeze process.
