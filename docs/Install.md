# Install Notes

## Current confirmed paths

IPTVBoss persistent data:

`/srv/dev-disk-by-uuid-4d39f891-6950-43f3-9ac1-ba3dd583c8e8/appdata/iptvboss/data`

IPTVBoss output:

`/srv/dev-disk-by-uuid-4d39f891-6950-43f3-9ac1-ba3dd583c8e8/appdata/iptvboss/output`

Builder project:

`/srv/dev-disk-by-uuid-4d39f891-6950-43f3-9ac1-ba3dd583c8e8/appdata/iptvboss-builder`

## IPTVBoss first-run bug/workaround

IPTVBoss 3.10.5 crashes if a layout is created before at least one user exists.

Correct order:

1. Open IPTVBoss.
2. Sources -> Manage Users.
3. Create user `USER1`.
4. Then create layout `Plex`.
5. Save layout output settings.
