# Sign-in for the ChannelForge server

This page is for the person who runs ChannelForge as a server. If you use the portable Windows bundle, you do not need it. See the last section.

## What sign-in protects

A server can be reached by other devices. Sign-in keeps people on your network from changing your lineup, your sources or your settings. You choose one password. Everyone who knows it is an admin.

## Not built yet

- Named users and roles. There is one shared admin password.
- Email recovery. There is no "forgot password" email.
- Sessions that survive a restart. When the server restarts, everyone signs in again.
- HTTPS inside ChannelForge. Use a reverse proxy for HTTPS.
- A graphical Windows server installer. Scripts that start the server at Windows start-up are written but not yet tried on a real machine; see `Server-At-Startup.md`. A Docker image can be built from the repository; see `Server-Docker.md`.

## First start and the one-time setup code

1. Open PowerShell in the ChannelForge folder.
2. Run `scripts\Start-ChannelForgeServer.ps1 -ConfigRoot <folder>`. Pick a folder to keep your settings in. The program makes it if it is missing. Sign-in is always on with this script.
3. To let other devices reach the server, add `-BindAddress 0.0.0.0` and `-AllowedHost <address>`. Use the name or address you will type in the browser, for example `-AllowedHost 192.168.1.20`. The server refuses any other name. On Windows, listening on the network needs an administrator window. Add `-Port <number>` to change the port. The default port is 47850.
4. Look at the console. It prints a one-time setup code and the first-run page address.
5. Open the first-run page.
6. Type the setup code. It works once. It stops working after 15 minutes.
7. Choose your password and type it twice.
8. If the code stopped working, stop the script and run it again. It prints a new code.

The script stops if you leave out `-ConfigRoot`. The server also refuses a network address unless sign-in is on and a config folder is set.

To run the server in Docker, see `Server-Docker.md`.
To run the server at Windows start-up, see `Server-At-Startup.md`.

The setup code only proves that you can reach the server machine. Keep the console private until setup is done.

## Choosing a password

1. Use at least 12 characters.
2. Do not use a very common password. ChannelForge refuses those.
3. Write it down somewhere safe. There is no email reset.

## HTTP warning and HTTPS

Plain HTTP can be read by anyone on the network. A password typed over plain HTTP can be seen. Put a reverse proxy with HTTPS in front of ChannelForge. Keep ChannelForge sign-in on behind it. The first-run page warns you when you open it from another computer over plain HTTP.

## Changing the password

1. Sign in. Press "Change password" at the top of the page.
2. Type your current password.
3. Type your new password twice. It must have at least 12 characters, and easy common passwords are refused.
4. Press "Change password".

Every other browser that was signed in is signed out. The browser you used stays signed in. If you type the current password wrong too many times, the program asks you to wait before the next try.

You sign out with the "Sign out" button at the top of the page. If you open ChannelForge over plain HTTP from another computer, the page shows a warning.

## Forgot the password

You need access to the server machine. There is no way to do this from another device.

1. Open an administrator window on the server machine.
2. Run `Reset-ChannelForgeAdminPassword -ConfigRoot <the same config folder>`.
3. Confirm when it asks.
4. Restart the server. It prints a new setup code.
5. Do the first-start steps again.

The reset removes only the sign-in files (`users.json` and the old `admin-password.json`). Your lineups, accepted state and outputs are not touched. A leftover `admin-password.json.migrated` file is not touched; see the next section.

## Where the password is kept

The program keeps the sign-in data in one file, `users.json`, in your config folder. At first it holds one user, named `admin`, and a hash of the password. An Admin can add more users later; each one has a hash too. It never holds a password itself. Do not edit it by hand. If the file is damaged, the server refuses to start and does not change the file.

If you used an older version, the program upgrades by itself the first time the server starts or someone signs in. It copies your password to `users.json`, so your current password keeps working and you do nothing. Then it renames the old file to `admin-password.json.migrated`. Keep that file as a safety copy, or delete it once you are happy. If both files exist, `users.json` is used and the old file is ignored.

## Wrong tries and the slow-down

After 5 wrong passwords in a row, the server makes you wait before the next try. The wait doubles each time, up to 15 minutes. Then it stops growing. You are never locked out for good. The right password works once the wait is over. The message is always the same, so it never tells a stranger what was wrong.

Each user name also has its own count. After 5 wrong passwords for one name, that name waits 60 seconds, whatever address the tries come from, and even the right password is refused until the 60 seconds end. A name that does not exist is counted the same way and gets the same answer, so nobody can tell which names exist. This wait is kept in memory only. It lasts 60 seconds at most and a restart clears it, so wrong tries can never lock out the last Admin for good. A right sign-in after the wait clears that name's count.

## Audit trail

When sign-in is on, the server writes one line per event to `audit.jsonl` in your config folder: sign-ins (right and wrong), sign-outs, password changes, and every change to users. Each line says when, who, what, from which address, and whether it worked. It never holds a password, setup code or session. The file keeps the last 12 months or the newest 5,000 lines, whichever is smaller. If the file cannot be written, the server shows one warning and carries on. An Admin can read it at `/api/audit`, newest first. A screen for it comes later.

## Backups

A backup of the config folder contains the password hash in `users.json` (and in `admin-password.json.migrated` after an upgrade). The hash is not the password, but protect the backup like the server.

## The portable Windows bundle

The portable bundle listens on `127.0.0.1` only. Only that computer can open it. It has no sign-in. This has not changed.
