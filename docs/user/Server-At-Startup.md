# Run the ChannelForge server at Windows start-up

This page is for the person who runs ChannelForge as a server on a Windows computer. The server starts by itself when Windows starts. Nobody has to sign in to Windows first. See `Server-Sign-In.md` for what sign-in does.

The scripts make a Windows scheduled task. The task runs as the built-in `NT AUTHORITY\LOCAL SERVICE` account. That account has no password, so ChannelForge stores none. The files were written, but not yet tried on a real machine.

## Install

1. Put the ChannelForge folder in `C:\Program Files\ChannelForge`. Regular users can read it there but cannot change it. That matters, because the start-up account runs the scripts in it. The script stops if regular users can change the folder. A folder under `C:\Users` does not work. PowerShell 7 must be installed for all users, not under `C:\Users`.
2. Open PowerShell 7 as an administrator.
3. Run `scripts\Install-ChannelForgeServerTask.ps1`.
4. The script makes the folder `C:\ProgramData\ChannelForge` and locks it. Only administrators, the system and the start-up account can open it. It holds your password record.

## First run

1. If no password is set, the script starts the server in that window. It prints a one-time setup code.
2. Open the page it shows, for example `http://127.0.0.1:47850/first-run`.
3. Type the setup code and choose your password.
4. Go back to the window and press Enter. The script stops the server, makes the start-up task and starts it.

If you press Enter before you set a password, nothing is installed. Run the script again.

## Open the page

Open `http://127.0.0.1:47850` in a browser on the same computer. Sign in with your password. To use another port, add `-Port <number>`.

## Network access

By default only this computer can open the server. To let other devices in:

1. Finish first run first. Network access needs a password.
2. Run the script again with `-BindAddress 0.0.0.0 -AllowedHost <name>`. Use the name or address you will type in the browser, for example `192.168.1.20`.
3. The script reserves that address for the start-up account. It adds one firewall rule for that port. The rule is only for Private and Domain networks, never Public.

The server speaks plain HTTP. Anyone on the network can read what you type. Put a reverse proxy with HTTPS in front of it.

## Get a new setup code

1. Open an administrator window and stop the task: `Stop-ScheduledTask -TaskPath \ChannelForge\ -TaskName ChannelForgeServer`.
2. Run `scripts\Start-ChannelForgeServer.ps1 -ConfigRoot C:\ProgramData\ChannelForge`. It prints the code.
3. Finish setup, then press Ctrl+C.
4. Start the task: `Start-ScheduledTask -TaskPath \ChannelForge\ -TaskName ChannelForgeServer`.

## Forgot the password

1. Open an administrator window and stop the task as above.
2. Run `Reset-ChannelForgeAdminPassword -ConfigRoot C:\ProgramData\ChannelForge`.
3. Run `scripts\Start-ChannelForgeServer.ps1 -ConfigRoot C:\ProgramData\ChannelForge` once. Type the new code on the first-run page and set a new password. Press Ctrl+C.
4. Start the task as above.

## Uninstall

1. Open PowerShell 7 as an administrator.
2. Run `scripts\Uninstall-ChannelForgeServerTask.ps1`.
3. It removes the task, the address reservation and the firewall rule it made. It keeps your password and settings. Installing again later keeps them too.
4. To erase them as well, add `-RemoveData`. It asks you to type DELETE. `-Force` skips the question.
