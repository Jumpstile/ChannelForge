# Sign-in for the ChannelForge server

This page is for the person who runs ChannelForge as a server. If you use the portable Windows bundle, you do not need it. See the last section.

## What sign-in protects

A server can be reached by other devices. Sign-in keeps people on your network from changing your lineup, your sources or your settings. You choose one password. Everyone who knows it is an admin.

## Not built yet

- Sign-in and change-password screens. The server has the sign-in and change-password requests, but no page sends them yet. Only the first-run page exists.
- Named users and roles. There is one shared admin password.
- Email recovery. There is no "forgot password" email.
- Sessions that survive a restart. When the server restarts, everyone signs in again.
- HTTPS inside ChannelForge. Use a reverse proxy for HTTPS.
- A Docker image and a Windows server installer. The sign-in code exists, but these are not packaged yet.

## First start and the one-time setup code

1. Start the server with sign-in turned on (`Start-ChannelForgeWebServer -RequireSignIn -ConfigRoot <folder>`).
2. Look at the server console. It prints a one-time setup code.
3. Open the first-run page that the console names.
4. Type the setup code. It works once. It stops working after 15 minutes.
5. Choose your password and type it twice.
6. If the code stopped working, restart the server. It prints a new one.

The setup code only proves that you can reach the server machine. Keep the console private until setup is done.

## Choosing a password

1. Use at least 12 characters.
2. Do not use a very common password. ChannelForge refuses those.
3. Write it down somewhere safe. There is no email reset.

## HTTP warning and HTTPS

Plain HTTP can be read by anyone on the network. A password typed over plain HTTP can be seen. Put a reverse proxy with HTTPS in front of ChannelForge. Keep ChannelForge sign-in on behind it. The first-run page warns you when you open it from another computer over plain HTTP.

## Changing the password

There is no screen for this yet. The server can do it, but no page sends the request. For now, the only way to set a new password is the reset in the next section.

When a screen is added, it will ask for your current password and a new one, and it will sign out every other browser.

## Forgot the password

You need access to the server machine. There is no way to do this from another device.

1. Open an administrator window on the server machine.
2. Run `Reset-ChannelForgeAdminPassword -ConfigRoot <the same config folder>`.
3. Confirm when it asks.
4. Restart the server. It prints a new setup code.
5. Do the first-start steps again.

The reset removes only the password file. Your lineups, accepted state and outputs are not touched.

## Wrong tries and the slow-down

After 5 wrong passwords in a row, the server makes you wait before the next try. The wait doubles each time, up to 15 minutes. Then it stops growing. You are never locked out for good. The right password works once the wait is over. The message is always the same, so it never tells a stranger what was wrong.

## Backups

A backup of the config folder contains the password hash. The hash is not the password, but protect the backup like the server.

## The portable Windows bundle

The portable bundle listens on `127.0.0.1` only. Only that computer can open it. It has no sign-in. This has not changed.
