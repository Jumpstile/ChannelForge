# Design note: remote credential enrollment

This is a design note. It adds no code, no tests and no schema change. It comes from reading this tree. Nothing was run. Anything not confirmed is marked `[INFERENCE]` or listed under "Not verified".

Examples use `example.invalid` hosts and fake logins only (`user: demo`, `password: demo-not-real`).

## 1. The problem and who it protects

Many IPTV providers put the user's login inside the playlist link and the guide link. A typical link looks like this:

```text
https://tv.example.invalid/get.php?username=demo&password=demo-not-real&type=m3u_plus
```

Today ChannelForge refuses this link. Source enrollment rejects a remote link that has user info, a query or a fragment (`Edit-ChannelForgeSourceSet.ps1`, `Convert-ChannelForgeGuidedSetupSourceSet.ps1`, `Test-ChannelForgeSourceUrl.ps1`). The refresh script and the opt-in scheduled task only handle public HTTPS sources. A user whose provider link carries a login cannot refresh remotely.

This note protects that user. Their login is a paid account. If it leaks, someone else can use it, the provider may ban it, and the user loses the account. The design must let the user refresh remotely without the login ever being written where a person, a log or a backup could read it.

## 2. Requirements

The secret is the part of the link that identifies the account. The rest of the link (host, and a path with no login in it) is not secret.

The secret must never appear in:

- the repository, or any tracked file;
- any saved state file in readable form (`state\source-enrollment.json`, managed sources, review sessions, refresh results, last-known-good snapshots);
- reports, logs, Doctor output, error text or exception messages;
- command lines (no `-Url` or `-Password` argument, no `cmdkey /pass:`);
- any URL printed anywhere (display is host-only, as `Get-ChannelForgeRedactedSourceHost` does today);
- the output playlist or guide.

It must also work with the existing pinned HTTPS transport (ADR-0014) without loosening it:

- HTTPS only, port 443, no proxy, no cookies, GET only;
- redirects stay rejected (every 3xx is `RedirectRejected`);
- the existing size and time limits stay (256 MiB hard maximum, 10 s DNS, 10 s connect, 30 s headers, 30 s body inactivity, 120 s total);
- zero automatic retries.

ADR-0014 already says credentials must come through "a separate secret-aware mechanism" and never be embedded in the URI. This design is that mechanism. See section 7 for the one place that needs an ADR amendment.

## 3. Where to store the secret on Windows

### Options compared

| Option                                   | How it works                                                                                                                                                                                                                                                      | Good                                                                                                                   | Bad                                                                                                                                                                                                                                                                    |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Windows Credential Manager               | Windows keeps the secret per user. Users can see and delete it in a Windows screen.                                                                                                                                                                               | Familiar place. Windows manages it.                                                                                    | PowerShell 7 has no built-in command for it. Reading it needs a C# or native call (ADR-0014 allows only one C# helper, for transport) or a third-party module (new dependency). The `cmdkey` tool puts the secret on a command line. Not good enough for this product. |
| DPAPI-protected file in the user profile | The secret is encrypted with the Windows login of the current user. Only that user, on that PC, can decrypt it. PowerShell 7 does this with `ConvertTo-SecureString` / `ConvertFrom-SecureString` (no key given) or `System.Security.Cryptography.ProtectedData`. | Built in, no new dependency, no C#. Easy to delete. Works with the existing scheduled task (it runs as the same user). | The file can be copied, but it is useless on another PC or for another user. A user can still see that the file exists.                                                                                                                                                |

### Recommendation

Use a DPAPI-protected file, current-user scope, with no extra key.

- Location: `%LOCALAPPDATA%\ChannelForge\credentials\<ref-id>.cred`. Never inside the repository or the `state` folder. `LOCALAPPDATA` does not roam.
- One file per enrolled source. The file holds only the encrypted secret and a format version. Nothing else.
- The ref id is a random 128-bit value (hex). It is not derived from the secret, the link or any host, so it reveals nothing.
- Writes go to a temporary file in the same folder and are moved into place, so a crash never leaves a half-written file. The folder gets an access list for the current user only.
- `[INFERENCE]` `ConvertFrom-SecureString` without a key uses DPAPI on Windows in PowerShell 7. The first slice must prove this on the supported runtime before anything else is built on it.

### What the secret is

The secret is the whole link, stored encrypted. This is the simplest rule and it also covers links where the login sits in the path (`/live/demo/demo-not-real/1.ts` style). ChannelForge does not try to guess which part is the login. The source-set record keeps only non-secret parts (below).

### What the source-set record keeps instead

The source record keeps an opaque reference and a host-only label:

- `CredentialRef`: the random ref id. Never the secret, never a hash of it.
- `DisplayHost`: scheme and host, for example `https://tv.example.invalid`. No path, no query.
- `Url`: `null`. This field already exists and already allows null (`schemas\source-enrollment.schema.json`).

### Failure modes

| Situation                              | What happens                                                                                                                                                                                                                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Roaming profile                        | The file lives in `LOCALAPPDATA`, which does not roam. On another PC the file is absent, so refresh fails closed with "run enroll again". Good. `[INFERENCE]` Some managed domains redirect `LOCALAPPDATA`; DPAPI still ties the file to the user, so it still fails safely. |
| Different user runs the scheduled task | The existing task runs as the user who installed it (`Interactive`, `Limited`, per `Initialize-ChannelForgeScheduledOperation.ps1`). Another user cannot decrypt the file. Fail closed, same message.                                                                        |
| Backup and restore                     | A restored file is only readable on the same Windows install and user. After a reinstall or a new PC it is unreadable. Fail closed, same message. The repository backup never holds the secret, because it is not in the repository.                                         |
| Windows password reset by an admin     | Decryption can fail. Same message.                                                                                                                                                                                                                                           |
| Secret file deleted or corrupt         | Same message.                                                                                                                                                                                                                                                                |
| Provider revoked or changed the login  | The provider answers 401, 403 or a login error. The source is marked "login rejected". Last-known-good data is kept. Same "run enroll again" next step.                                                                                                                      |

Plain message for every case (host only): `The saved login for https://tv.example.invalid is missing, unreadable or was rejected. Run the enroll command again for this source.` The message never says which of those it was beyond a short category, because "unreadable" and "rejected" need different fixes but neither needs a URL.

## 4. Enrollment flow without any UI

A script, for example `scripts\Enroll-ChannelForgeRemoteSource.ps1`. No browser page. UI is Milestone 3.

### How the user gives the link

The script offers two ways. Both use a prompt that does not echo.

1. Paste the full link: `Read-Host -AsSecureString 'Paste the full link (nothing will show)'`.
2. Enter parts (host, username, password, each at a no-echo prompt) is not in v1. See owner decision 5.

The link never comes from a command-line argument, an environment variable or a file the user must save first. The script refuses `-Url` and `-Password` parameters on purpose. The secure string is converted to plain text only inside one function, as a `char[]` or `byte[]` that is cleared in a `finally` block. `[INFERENCE]` PowerShell strings cannot be reliably wiped; the aim is a short lifetime, not a guarantee. See threats.

### How the link is split

1. Parse as an absolute URI. Reject if not `https`, port not 443 or empty, host empty, or a fragment is present.
2. Reject a link with user info (`user:pass@host`) in v1. See section 7: sending it needs an `Authorization` header, and ADR-0014 does not allow that yet. The message says so in plain words.
3. Check the host with the existing `Test-ChannelForgeSafeHostAddress` rules (the same checks as today).
4. Keep `DisplayHost` = scheme + host. Everything after the host (path and query) is the secret part, together with the whole link as stored.
5. The secret is saved to the DPAPI file. Only then is the source-set record written, with `CredentialRef` and `DisplayHost`.

### What is checked before saving

- The link passes the rules above.
- Dry-run probe (below) succeeds, unless the user passes `-SkipProbe` (offline use). Skipping is printed plainly.
- The text shown to the user contains no secret (see threats).
- The secret file was written and read back once.

If any check fails, nothing is saved: no secret file, no record. Honest outcome only. No "saved" message after a partial failure. If the secret file is written but the record write fails, the script deletes the secret file it just created (it created it, so it may delete it) and says so.

### Dry-run

`-DryRun` does everything above except the final save. It runs the existing bounded acquisition (`Invoke-ChannelForgePinnedHttpM3UAcquisition` or the XMLTV one, as `Get-ChannelForgeSourceReachabilityFinding` does) and reads at most 4096 bytes. Output is host-only:

```text
Source: https://tv.example.invalid/...
Login test: PASS. The provider answered and the first 4096 bytes were readable.
Not tested: the full download, and whether the whole account is active.
```

On failure it prints the failure category only (for example `RedirectRejected`, `HttpStatusRejected`, `Timeout`), never the link, the `Location` header or the response body.

## 5. How the scheduled refresh gets the secret

The scheduled task runs `scripts\Invoke-ChannelForgeScheduledRefreshRun.ps1` as the installing user with `LogonType Interactive` and `RunLevel Limited`.

At run time, for each source that has a `CredentialRef`:

1. Read and decrypt the file in memory.
2. Pass the link to the existing pinned transport in memory only. It is never written to disk, an argument list, a log or an environment variable.
3. Drop the reference as soon as the request is finished.

### PC locked, or no one logged in

- Locked screen, user still logged on: the task runs and DPAPI works, because the user's profile is loaded.
- Nobody logged on: an `Interactive` task does not run at all. That is the existing behavior and this design keeps it. `StartWhenAvailable` runs it after the next login. The refresh report says the run was late, as it does today.
- No fallback that stores the secret in a machine-wide place so a "run whether logged on or not" task could read it. That would weaken the protection (any local admin could read it) and would need a stored Windows password for the task. Not in scope. See owner decision 4.

If decryption fails the source is skipped with the plain message from section 3. Other sources still refresh. The run result is not "success" for that source.

## 6. Threats and mitigations

| Threat                                            | Mitigation                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shoulder surfing while pasting                    | `-AsSecureString` prompt: nothing is echoed. The script never prints the secret back, not even masked with a prefix or suffix.                                                                                                                                                                                                                                                                                                                                                                                                  |
| Logs and reports                                  | Every message about a remote source uses `DisplayHost` only. A test with a fake login scans every file the code writes and every output stream for the fake secret.                                                                                                                                                                                                                                                                                                                                                             |
| Crash dumps and PowerShell transcripts            | `[INFERENCE]` In-memory text cannot be fully wiped by PowerShell. Keep lifetime short, clear arrays, avoid variables that outlive the function. Tell the user in plain words not to run `Start-Transcript` around the enroll command. Residual risk is listed for the owner.                                                                                                                                                                                                                                                    |
| PSReadLine history                                | The user never types the secret on a command line, only into the prompt. PSReadLine does not save prompt input from `Read-Host`. `[INFERENCE]` verify on the supported runtime.                                                                                                                                                                                                                                                                                                                                                 |
| Error messages that contain URLs                  | Failures from the transport already carry a category (`ChannelForgeFailureCategory`) and no URL. The new code catches all exceptions at one boundary and rethrows a category-only message. The `Location` header is never emitted (ADR-0014).                                                                                                                                                                                                                                                                                   |
| Redirect to another host leaks the secret         | All redirects are rejected by the transport. The secret is only ever sent to the host the user enrolled. No cross-host forwarding exists to leak it.                                                                                                                                                                                                                                                                                                                                                                            |
| Provider returns the secret inside the playlist   | Many providers write the login into every stream link (`http://host/live/demo/demo-not-real/1.ts`). That would put the secret in the managed-source snapshot and the output playlist. The enroll probe and the refresh run check the bytes they hold for the secret values. This is allowed (owner decision 1): the saved snapshot and the output playlist are private files and may carry the login in stream links. The checks only stop the login from reaching reports, logs, Doctor output, error text or anything shared. |
| Backups                                           | Secret is outside the repository and the `state` folder. The DPAPI file is useless off the original user and PC. The state folder and repository backups never contain it.                                                                                                                                                                                                                                                                                                                                                      |
| Someone copies the state folder                   | The folder holds `CredentialRef` and `DisplayHost` only. The ref is a random id, not a hash of the secret, so there is nothing to crack offline.                                                                                                                                                                                                                                                                                                                                                                                |
| Someone copies the DPAPI file                     | Useless without the same Windows user on the same install. Malware running as the same user can read it. That is the limit of DPAPI. Stated plainly to the user.                                                                                                                                                                                                                                                                                                                                                                |
| Secret in the source id or any hash               | Today `Get-ChannelForgeSourceSetSourceId` hashes a `SourceKey`. For credentialed sources the key must use `DisplayHost` plus the `CredentialRef`, never the link. A hash of a low-entropy login can be guessed. This is a hard rule for slice 4.                                                                                                                                                                                                                                                                                |
| Leak through `source-enrollment.json` hash fields | `EnrollmentHash` covers all properties. The new fields hold no secret, so the hash is safe.                                                                                                                                                                                                                                                                                                                                                                                                                                     |

## 7. Frozen contracts touched

None are intended. Checked against the list:

| Contract                                              | Touched? | Why                                                                                                                                                   |
| ----------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Guide-id contract v1.0                                | No       | Guide ids come from guide content, not from where it was fetched. The `guide: null` marker stays. No channel is dropped.                              |
| Raw digest projections                                | No       | No change to digest inputs.                                                                                                                           |
| M3U entry byte format                                 | No       | Entries are copied as today. If a provider writes the login in stream links the source is refused (above), so the format is never altered to hide it. |
| `BuildIdentityInput`                                  | No       | Credentials are not part of identity.                                                                                                                 |
| blocker-2-contract v7, v8, v10                        | No       | No change to publish or candidate shapes.                                                                                                             |
| accepted-state, candidate-manifest, decision-manifest | No       | Not edited. A credentialed source still produces the same candidate shapes after download.                                                            |

### Source-set schema

`schemas\source-enrollment.schema.json` source items have `Url` as `string` or `null` already. The design needs two new optional fields on a source item: `CredentialRef` (string, 32 lowercase hex) and `DisplayHost` (string). `[INFERENCE]` The version string `source-enrollment/v2` does not need to change if the item schema allows extra properties, because records without the fields stay valid and keep their exact hash. Slice 4 must first check whether the item schema sets `additionalProperties: false` and whether `Get-ChannelForgeSourceEnrollmentHash` hashes every property (it does: it copies all properties except the two hash fields). If extra properties are not allowed, add the two fields to the schema as optional. That is an additive change and is allowed. A new `source-enrollment/v3` is not needed and is not allowed without owner approval.

Hash effect: records with the new fields hash differently from records without them. That is correct and expected, because they are different records. Old records do not change.

### Transport (ADR-0014)

- Links with the login in the query or path need no transport change. The transport already accepts them; only the enrollment layer rejects them today. Slice 4 relaxes that rule for credentialed sources only, and only through the new enroll command.
- Links with user info (`user:pass@host`) need an `Authorization: Basic` header. ADR-0014 rejects user info and says any future header support must be a separate decision, never logged and never forwarded. That is an ADR amendment, not a code-only change. It is not allowed in this plan without the owner's decision (owner decision 3). Default: not in v1.

## 8. Slices

Each slice is about 100 to 300 changed lines including tests. All tests use fake credentials (`demo`, `demo-not-real`) and `example.invalid` hosts. No test uses the network; the transport call is replaced by a test double.

| Slice | What                                                                                                                                                                                   | Files (new unless noted)                                                                                                                | Tests                                                                                                                                                                                           | Depends on | Parallel with |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ------------- |
| 1     | Secret store. Save, read, delete a DPAPI file by ref id. Random ref id. Tight folder access. Prove `ConvertFrom-SecureString` is DPAPI on the runtime.                                 | `Private\Save-ChannelForgeSourceSecret.ps1`, `Read-...`, `Remove-...` (one function each)                                               | Round trip with a fake secret. File text does not contain the secret. Missing file gives the plain category. Delete removes only the named file.                                                | none       | 2, 4          |
| 2     | Link splitter and validator. Returns `DisplayHost` and the secret link, or a category failure. Rejects user info, fragment, non-443, unsafe host.                                      | `Private\Split-ChannelForgeSecretSourceLink.ps1`                                                                                        | Good query link splits. User info link refused with plain message. Message never contains the fake login.                                                                                       | none       | 1, 4          |
| 3     | Enroll script with no-echo prompt, dry-run, 4096-byte probe, echo scan, rollback of the secret file if the record write fails.                                                         | `scripts\Enroll-ChannelForgeRemoteSource.ps1`                                                                                           | Dry-run saves nothing. Failed probe saves nothing. Login inside stream links is allowed; the probe output still shows host only. Output and error streams never contain the fake login.         | 1, 2, 4    | none          |
| 4     | Source-set record fields (`CredentialRef`, `DisplayHost`), schema optional fields, source id from host + ref, credentialed sources allowed past the URL gate only via the enroll path. | edit `schemas\source-enrollment.schema.json`, `Edit-ChannelForgeSourceSet.ps1`, `Write-ChannelForgeSourceSet.ps1` (small edits)         | Old record still validates with an identical hash. New record validates. `state\source-enrollment.json` has no fake login. Plain link still rejected outside the enroll path.                   | 2 (shape)  | 1             |
| 5     | Refresh path. Read secret at run time, pass in memory, fail closed with the plain message, skip one source without stopping the others, scan received bytes for the secret.            | edit `Invoke-ChannelForgeWebSourceRefresh.ps1`, `Get-ChannelForgeSourceRefreshPlan.ps1`, `scripts\Invoke-ChannelForgeSourceRefresh.ps1` | Missing secret: source skipped, last-known-good kept, message host-only. Revoked login (fake 401): same. Login inside stream links: allowed, but never shown in reports, logs or Doctor output. | 1, 4       | 6             |
| 6     | Doctor and redaction. Doctor reads secret through the store for credentialed sources and prints host-only. Add one shared error scrubber used at the new boundaries.                   | edit `Get-ChannelForgeSourceReachabilityFinding.ps1` (Doctor) plus one small helper                                                     | Doctor output for a fake credentialed source has host only. A thrown error with a link in its text is scrubbed.                                                                                 | 1, 4       | 5             |
| 7     | Docs. Update `docs\user\CURRENT_LIMITATIONS.md` (the "not in alpha.1" line), a short user guide, and the ADR-0014 amendment text if the owner approves user info links.                | docs only                                                                                                                               | Markdown hygiene and link checks.                                                                                                                                                               | 3, 5, 6    | none          |

Order: 1, 2 and 4 in parallel; then 3, 5 and 6 (5 and 6 in parallel; 3 any time after 1, 2, 4); then 7. If the owner approves user info links, add slice 8 (ADR-0014 amendment plus a transport header option, about 250 lines, its own review). It is not in the plan above.

Reuse (do not duplicate): `Get-ChannelForgeRedactedSourceHost`, `Test-ChannelForgeSafeHostAddress`, `Test-ChannelForgeSourceUrl` (shape rules), `Invoke-ChannelForgePinnedHttpM3UAcquisition`, `Invoke-ChannelForgePinnedHttpXmltvAcquisition`, `Assert-ChannelForgeSourceEnrollmentPath`, `Get-ChannelForgeSourceEnrollmentHash`, `New-ChannelForgePreflightFinding`.

## 9. Owner decisions

| #   | Decision                                                                                                                           | Recommended default                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --- | ---------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Providers that write the login into every stream link: refuse, or allow with a warning? This is the biggest question in this note. | DECIDED by the owner (Nov 22): allow. The first draft recommended refusing. That would exclude most providers, because an IPTV player needs the stream links, and many providers put the login in them; the output playlist then has to carry them, as the user's own downloaded file already does today. A better default to decide: allow, and treat the downloaded playlist snapshot and the output playlist as private files that never go into the repository, reports, logs or Doctor output (host-only display everywhere else). Keep refusing only a login echoed into places that are shown or shared. Slice 5 treats the downloaded snapshot and the output playlist as private and scans only the places that are shown or shared. |
| 2   | Secret store: DPAPI file or Windows Credential Manager.                                                                            | DPAPI file in `LOCALAPPDATA` (section 3).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 3   | Allow `user:pass@host` links (needs an ADR-0014 amendment for an `Authorization` header)?                                          | No in v1. Support query and path links first. Revisit after hand testing shows how many providers need it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 4   | Refresh when nobody is logged on?                                                                                                  | No. Keep the existing interactive task. Refresh runs after the next login.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 5   | Is a "paste parts" option (host, username, password) wanted, or paste-the-link only?                                               | Paste-the-link only in v1.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 6   | One credential per source, or may two sources share one saved login?                                                               | One per source. Simpler delete and no shared-failure surprises.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 7   | Allow `-SkipProbe` for offline enrollment?                                                                                         | Yes, with a plain printed warning that the login was not tested.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

### What the owner must test by hand at the end

1. Enroll a real credentialed link. Confirm nothing was shown while pasting.
2. Search the repository, the `state` folder, `output` and the Doctor and refresh reports for the login. Expect no match.
3. Run the Doctor and a manual refresh. Expect host-only text.
4. Run the scheduled task once. Expect success while logged on, locked or not.
5. Delete the credential file. Run refresh. Expect the plain "run enroll again" message and the last-known-good data kept.
6. Change the password at the provider (or enroll a wrong one). Expect the "login rejected" message, no crash and no saved snapshot.
7. Copy the state folder to a second PC. Expect refresh to fail closed there.
8. Use a provider that writes the login into stream links. Expect refusal with a plain message.

## 10. What stays out

- Any UI, including a browser enrollment page (Milestone 3).
- Non-Windows secret storage (macOS Keychain, Linux secret service).
- Xtream API login flows beyond a plain link (no API calls, no account info pages, no token exchange).
- Paid services, cloud secret vaults and any network service for secrets.
- Redirect support, proxies and any weakening of ADR-0014 limits.
- A "run whether logged on or not" scheduled task.

## Not verified

- That `ConvertFrom-SecureString` without a key uses DPAPI on the supported PowerShell 7.6 runtime. Slice 1 proves it.
- Whether `schemas\source-enrollment.schema.json` source items allow extra properties.
- That PSReadLine does not record `Read-Host` input.
- What fraction of real providers write the login into stream links.
- That `Get-ChannelForgeSourceSetSourceId` callers can accept a host-plus-ref key without side effects.
