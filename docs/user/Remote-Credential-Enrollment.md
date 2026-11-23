# Remote Credential Enrollment

> **Status:** built and waiting for the owner's hand test. It is **not** part of alpha.1. It is planned for the next release.

## What it is

Many IPTV providers give you a link that has your login inside it. The link might look like this:

```text
https://tv.example.invalid/get.php?username=demo&password=demo-not-real&type=m3u_plus
```

That login is your paid account. If someone else gets it, they can use your account, and the provider may block it.

Remote credential enrollment lets ChannelForge save that whole link in a protected file. Refresh uses the saved login, so you do not paste the link again.

## Who it is for

Use it if your provider's playlist or guide link has the login in it, and the normal "add a web link" step refuses the link.

If your link is a plain public link with no login, you do not need this. Use the normal steps in [Build Your First Lineup](Build-Your-First-Lineup.md).

## How to save a login

Open PowerShell 7 in the ChannelForge folder and run:

```powershell
pwsh -File .\scripts\Enroll-ChannelForgeRemoteSource.ps1
```

ChannelForge asks you to paste the full link. **Nothing shows while you paste.** That is on purpose. Paste the link, then press Enter.

Rules:

- Paste the link at the hidden prompt only.
- **Never** type the link on the command line. The command has no place for it, and a command line can be saved in your history.
- Do not run the command under `Start-Transcript` or any tool that records the screen or the keys.

### Choose the kind of source

The default is a playlist (M3U). For a guide (XMLTV), add `-Kind XMLTV`:

```powershell
pwsh -File .\scripts\Enroll-ChannelForgeRemoteSource.ps1 -Kind XMLTV
```

You can also give the source a name with `-Label`:

```powershell
pwsh -File .\scripts\Enroll-ChannelForgeRemoteSource.ps1 -Label "My provider"
```

### Try it first: `-DryRun`

`-DryRun` checks the link and asks the provider for a small piece of the file. It saves nothing.

```powershell
pwsh -File .\scripts\Enroll-ChannelForgeRemoteSource.ps1 -DryRun
```

You will see the host and a PASS or FAIL for the login test. The test does not check the full download, and it does not prove your whole account is active.

### No internet right now: `-SkipProbe`

Normally ChannelForge tests the login before it saves anything. If you are offline, add `-SkipProbe` to save without the test:

```powershell
pwsh -File .\scripts\Enroll-ChannelForgeRemoteSource.ps1 -SkipProbe
```

ChannelForge prints a warning that the login was not tested. If the login is wrong, you will find out at the next refresh.

## What ChannelForge keeps, and where

- **The saved link (the login):** a protected file in your Windows user profile. It holds the full link, encrypted. Only your Windows user, on this PC, can read it.
- **The source record:** a random reference to the protected file, and the host (for example `tv.example.invalid`). No login.

The protected file is not in the repository and does not travel with a copy of the state folder. If you copy ChannelForge to another PC or another Windows user, the saved login does not work there. Enroll again on that PC.

Reports, logs, and Doctor output show the host only. They never show the full link.

If saving fails part of the way, ChannelForge removes the protected file it just made and tells you nothing was enrolled.

## When the login is missing, wrong, or changed

You may see a message like this:

```text
The saved login for https://tv.example.invalid is missing, unreadable or was rejected. Run the enroll command again for this source.
```

This can happen if:

- the protected file was deleted;
- you moved to a new PC, a new Windows user, or a fresh Windows install;
- the provider changed your password or turned off the account.

The fix is always the same: **run the enroll command again** and paste the new link. ChannelForge keeps your last good copy of the playlist while the login is wrong.

## Private files

Some providers write your login into every stream link inside the playlist. That is allowed. It also means two files may hold your login in plain text:

- the downloaded snapshot of the playlist;
- the output playlist ChannelForge builds.

Treat both as **private**. Never share them, never post them in a bug report, and never put them in the repository. Reports, logs, and Doctor output show the host only, so those are safe to share.

## What is not supported yet

- Links written as `https://user:pass@host/...` (the login before the `@`). ChannelForge refuses them and says so.
- Refresh when nobody is logged on to Windows. The scheduled refresh runs as you, so it runs after you log on.
- Any screen or button for this. It is a command only.
- Other operating systems. The protected file uses Windows.
- Typing the host, user name, and password as separate parts. Paste the full link.

## See also

- [Current Limitations](CURRENT_LIMITATIONS.md)
- [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)
- [Troubleshooting](TROUBLESHOOTING.md)
