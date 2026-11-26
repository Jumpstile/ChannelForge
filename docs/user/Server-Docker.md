# Run the ChannelForge server in Docker

This page is for the person who runs ChannelForge as a server in a Docker container. The image files are in the `docker` folder. The image is not published anywhere. You build it yourself. Sign-in is always on. See `Server-Sign-In.md` for what sign-in does.

## Steps

1. Open a terminal in the ChannelForge folder.
2. Build the image: `docker build -f docker/Dockerfile -t channelforge .`
3. Pick a name or address you will type in the browser, for example `192.168.1.20`.
4. Run the container with a `/data` volume, the port published, and that name as the allowed host: `docker run -d --name channelforge -v channelforge-data:/data -p 47850:47850 -e CHANNELFORGE_ALLOWED_HOST=192.168.1.20 channelforge`. Separate several names with commas. The server refuses any other name.
5. Read the one-time setup code: `docker logs channelforge`.
6. Open `http://192.168.1.20:47850` in a browser, type the setup code, and choose your password.

If the container stops at once and says it cannot write to the data folder, the folder you mounted at `/data` is read-only or belongs to someone else. Mount a folder the container user can write to.

## Plain HTTP

The container speaks plain HTTP. Anyone on the network can read what you type. The page only shows a warning. Put a reverse proxy with HTTPS in front of it, and keep ChannelForge sign-in on.

## Backup

1. Stop the container: `docker stop channelforge`.
2. Copy the whole `/data` folder (the volume). Restoring is copying it back.

The backup contains the password hash. Protect it like the server.

## Upgrade

1. Get the new ChannelForge files and build the image again with the same command.
2. Stop and remove the old container: `docker rm -f channelforge`. The volume stays.
3. Run the container again with the same `-v channelforge-data:/data`.
