\# ChannelForge Style Guide



> Status: Living Document



\---



\# Purpose



This document defines the coding standards for the ChannelForge project.



These standards exist to make the project:



\- Easy to read

\- Easy to maintain

\- Easy to review

\- Easy to test

\- Consistent across the entire codebase



\---



\# Core Philosophy



Write code for the next developer.



Assume they know nothing.



That next developer might be you six months from now.



\---



\# General Rules



\## Prefer clarity over cleverness.



Good:



```powershell

foreach ($Channel in $Channels) {



}

```



Bad:



```powershell

$Channels | % { ... }

```



Avoid aliases.



Always use full cmdlet names.



\---



\## One responsibility per function.



Functions should perform one task well.



Avoid large "God functions."



\---



\## Approved Verbs



Use PowerShell approved verbs whenever possible.



Examples:



\- Get-

\- Set-

\- New-

\- Remove-

\- Test-

\- Read-

\- Write-

\- Import-

\- Export-

\- ConvertTo-

\- ConvertFrom-

\- Invoke-



Avoid unapproved verbs.



\---



\# Variables



Use descriptive variable names.



Good:



```powershell

$ProviderConfiguration

```



Bad:



```powershell

$p

```



Avoid abbreviations unless universally understood.



\---



\# Functions



Every public function should include:



\- Comment-based help

\- Parameter validation

\- Error handling

\- Examples

\- Unit tests



\---



\# Comments



Comment WHY.



Not WHAT.



Bad:



```powershell

$i++

```



Good:



```powershell

\# Skip duplicate channels that were already merged.

$i++

```



\---



\# Error Handling



Never ignore errors silently.



Prefer:



```powershell

try {



}

catch {



}

```



Fail with meaningful messages.



\---



\# Input Validation



Treat all external data as untrusted.



Always validate:



\- File paths

\- URLs

\- JSON

\- XML

\- Provider data

\- User input



\---



\# Security



Never:



\- Trust provider data

\- Execute downloaded code

\- Store secrets in source control

\- Skip validation



\---



\# Testing



Every bug fix requires:



\- A regression test



Every new feature requires:



\- Unit tests



CI must pass before merging.



\---



\# Documentation



Every significant feature must update:



\- README (if appropriate)

\- Developer Guide

\- Architecture

\- Tests



Documentation is part of the feature.



\---



\# Backups



Before modifying production data:



\- Backup

\- Verify backup

\- Apply changes

\- Verify result



Recovery must always be possible.



\---



\# Self-Healing



Automatic repairs must be:



\- Safe

\- Deterministic

\- Explainable

\- Logged

\- Reversible



\---



\# Definition of Done



A feature is complete only when:



\- Architecture reviewed

\- Code implemented

\- Code commented

\- Tests written

\- Tests passing

\- Documentation updated

\- Security reviewed

\- Regression checked

\- CI green



\---



\# The ChannelForge Standard



Every important decision must be:



\- Explainable

\- Reproducible

\- Reversible



\---



\# Motto



Build software people can trust.

