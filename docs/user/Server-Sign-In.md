# Sign-in for the ChannelForge server

This page is for the person who runs ChannelForge as a server. If you use the portable Windows bundle, you do not need it. See the last section.

## What sign-in protects

A server can be reached by other devices. Sign-in keeps people on your network from changing your lineup, your sources or your settings. Each person has their own name and password. Each person has one role. The role says what that person can do.

## What each role can do

| Role   | Can do                                                                                       |
| ------ | -------------------------------------------------------------------------------------------- |
| Viewer | Look at the status, the lineup and the guide. Change their own look (light or dark).         |
| Editor | Everything a Viewer can. Also run Guided Setup and refresh or remove sources.                |
| Admin  | Everything an Editor can. Also manage people, change server settings and read the audit log. |

Every person has exactly one role. There are no other roles. The server checks the role on every request. If you change a role or turn a person off, it takes effect on that person's next request.

## Not built yet

- The Users screen and the Audit screen. Today an Admin adds and changes people through the Users API (see "Adding a person" below). The program does not show them in the page yet.
- Making a person change a temporary password. The program marks the account, but it does not force the change yet. Ask the person to press "Change password" right away.
- Choosing your user name on the first-run page. The first user is always named `admin`. An Admin can rename it later through the Users API.
- Email recovery. There is no "forgot password" email.
- Sessions that survive a restart. When the server restarts, everyone signs in again.
- HTTPS inside ChannelForge. Use a reverse proxy for HTTPS. A setting for a trusted reverse proxy is not built and has not been tested, so sign-in behind a proxy may not work yet.
- The Requester role (asking for a channel).
- A graphical Windows server installer. Scripts that start the server at Windows start-up are written but not yet tried on a real machine; see `Server-At-Startup.md`. A Docker image can be built from the repository; see `Server-Docker.md`.

## First start and the one-time setup code

1. Open PowerShell in the ChannelForge folder.
2. Run `scripts\Start-ChannelForgeServer.ps1 -ConfigRoot <folder>`. Pick a folder to keep your settings in. The program makes it if it is missing. Sign-in is always on with this script.
3. To let other devices reach the server, add `-BindAddress 0.0.0.0` and `-AllowedHost <address>`. Use the name or address you will type in the browser, for example `-AllowedHost 192.168.1.20`. The server refuses any other name. On Windows, listening on the network needs an administrator window. Add `-Port <number>` to change the port. The default port is 47850.
4. Look at the console. It prints a one-time setup code and the first-run page address.
5. Open the first-run page.
6. Type the setup code. It works once. It stops working after 15 minutes.
7. Choose your password and type it twice. You become the first Admin. Your name is `admin`.
8. If the code stopped working, stop the script and run it again. It prints a new code.

The script stops if you leave out `-ConfigRoot`. The server also refuses a network address unless sign-in is on and a config folder is set.

To run the server in Docker, see `Server-Docker.md`.
To run the server at Windows start-up, see `Server-At-Startup.md`.

The setup code only proves that you can reach the server machine. Keep the console private until setup is done.

If you used an older version with one shared password, you do nothing. See "Where the files are" below.

## Choosing a password

1. Use at least 12 characters.
2. Do not use a very common password. ChannelForge refuses those.
3. Write it down somewhere safe. There is no email reset.

## Adding a person

Only an Admin can add people. The Users screen is not built yet, so today you use the Users API. It is a web address on your server that takes a small JSON message. Use PowerShell 7. You must be signed in, and you must type your own Admin password again for each add, delete or reset. This keeps a browser that someone left open from being enough.

Change `$base` to the address you type in the browser. It must be one of your `-AllowedHost` names. Use the same name in both lines.

```powershell
$base = 'http://127.0.0.1:47850'
$options = @{ ContentType = 'application/json'; Headers = @{ Origin = $base } }
$mine = Read-Host 'Your Admin password' -MaskInput
$first = Read-Host 'First password for the new person' -MaskInput

# Sign in. This keeps your session in $session.
$null = Invoke-RestMethod "$base/api/auth/sign-in" -Method Post @options -SessionVariable session -Body (@{ name = 'admin'; password = $mine } | ConvertTo-Json)

# Add a Viewer named alex.
Invoke-RestMethod "$base/api/users" -Method Post @options -WebSession $session -Body (@{ name = 'alex'; role = 'viewer'; temporaryPassword = $first; adminPassword = $mine } | ConvertTo-Json)
```

The role is `admin`, `editor` or `viewer`. The name has 3 to 32 letters, numbers, dots, dashes or underscores. The first password follows the same rules as any password: at least 12 characters, not a very common one. The answer shows the new person, with an `Id`. It never shows a password.

Give the first password to the person yourself, by voice or on paper. Ask them to sign in and press "Change password" at once.

Other things an Admin can do with the same `$options` and `$session`. Each person is found by their `Id`.

- See everyone: `Invoke-RestMethod "$base/api/users" -WebSession $session`
- Turn a person off or on, change a role or rename: `PUT $base/api/users/<Id>` with a body such as `{ "disabled": true }`, `{ "role": "editor" }` or `{ "name": "alex2" }`.
- Delete a person: `DELETE $base/api/users/<Id>` with a body of `{ "adminPassword": "..." }`.
- Reset a password: `POST $base/api/users/<Id>/reset-password` with a body of `{ "temporaryPassword": "...", "adminPassword": "..." }`.
- Read the audit log, newest first: `Invoke-RestMethod "$base/api/audit?limit=50" -WebSession $session`

The server always keeps at least one enabled Admin. It refuses to delete, turn off or demote the last one, and says why. When you turn a person off, delete them or reset their password, they are signed out on their next request.

## Changing your own password

1. Sign in. Press "Change password" at the top of the page.
2. Type your current password.
3. Type your new password twice. It must have at least 12 characters, and easy common passwords are refused.
4. Press "Change password".

Every other browser that was signed in as you is signed out. The browser you used stays signed in. If you type the current password wrong too many times, the program asks you to wait before the next try.

You sign out with the "Sign out" button at the top of the page.

## Forgot the password

There are two ways. Pick the first if another Admin can sign in.

### Way 1: another Admin resets it

The other Admin uses the reset line in "Adding a person". It sets a temporary password. The old password stops working at once. The person signs in with the temporary password and presses "Change password".

### Way 2: on the server machine

You need access to the server machine. There is no way to do this from another device.

1. Open an administrator window on the server machine.
2. Run `Reset-ChannelForgeAdminPassword -ConfigRoot <the same config folder> -Name <the Admin name>`. With only one Admin you can leave out `-Name`. With several Admins the command stops and lists their names; run it again with one of them.
3. Confirm when it asks.
4. The command shows a temporary password once. Write it down; it is not saved anywhere.
5. Open ChannelForge in the browser and sign in with that name and the temporary password. Then press "Change password". You do not need to restart the server.

This changes only that Admin. If the Admin was turned off, it is turned on again, and any browser that was signed in as that Admin is signed out. Other users, lineups, accepted state and outputs are not touched.

To remove every user and start over, run `Reset-ChannelForgeAdminPassword -ConfigRoot <the same config folder> -RemoveAllSignInData`, confirm, and restart the server. It prints a new setup code and you do the first-start steps again. This removes only `users.json`, `admin-password.json` and `admin-password.json.migrated`. Settings, lineups, accepted state and outputs are not touched.

## Wrong tries and the wait

The server slows down people who guess. You are never locked out for good. The message is always the same, so it never tells a stranger what was wrong.

| What happens                                     | How long you wait                                                                        |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| 5 wrong passwords in a row from one address      | The wait starts at 1 second and doubles with each wrong try, up to 15 minutes.           |
| 5 wrong passwords for one user name, any address | That name waits 60 seconds. Even the right password is refused until the 60 seconds end. |
| 50 wrong tries from all addresses together       | Everyone waits up to 30 seconds.                                                         |

A name that does not exist is counted the same way, so nobody can tell which names exist. The waits are kept in memory only. A restart clears them, and 15 quiet minutes clear them too. A right sign-in clears that address and that name. Typing your own Admin password wrong when adding, deleting or resetting a person counts as a wrong try for your address.

## Where the files are

All of these are in your config folder. Do not edit them by hand.

| File                           | What it holds                                                                                            |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `users.json`                   | Every person: name, role, on or off, and a hash of the password. It never holds a password.              |
| `user-settings.json`           | Each person's own look (light, dark or system). Kept apart so a problem here cannot touch the passwords. |
| `audit.jsonl`                  | One line for each event: sign-ins, changes to people and more.                                           |
| `admin-password.json.migrated` | Only after an upgrade from an older version. A safety copy of the old file.                              |

If `users.json` is damaged, the server refuses to start and does not change the file. If `user-settings.json` is damaged, ChannelForge uses the shared look and moves the file aside when it next saves a look.

If you used an older version with one shared password, the program upgrades by itself the first time the server starts or someone signs in. It copies your password to `users.json` as the user `admin` with the Admin role. Your current password keeps working and you do nothing. Then it renames the old file to `admin-password.json.migrated`. Keep that file as a safety copy, or delete it once you are happy. If both files exist, `users.json` is used and the old file is ignored.

The audit file holds, for each event: when, who, what, to whom, from which address and whether it worked. It never holds a password, a setup code or a session. It keeps the last 12 months or the newest 5,000 lines, whichever is smaller. Only an Admin can read it, through `/api/audit`. If the file cannot be written, the server shows one warning and carries on.

Sessions are kept in memory only. They are not in any file.

## HTTP warning and HTTPS

Plain HTTP can be read by anyone on the network. A password typed over plain HTTP can be seen. Put a reverse proxy with HTTPS in front of ChannelForge. Keep ChannelForge sign-in on behind it. The first-run page warns you when you open it from another computer over plain HTTP.

## Backups

A backup of the config folder contains every person's password hash in `users.json` (and in `admin-password.json.migrated` after an upgrade). It also contains the audit log. A hash is not the password, but protect the backup like the server.

## The portable Windows bundle

The portable bundle listens on `127.0.0.1` only. Only that computer can open it. It has no sign-in. This has not changed.
