# ChannelForge Project Guide

## Mission

ChannelForge is a source-of-truth television lineup builder.

It stores provider sources, EPG sources, numbering rules, channel categories, aliases, and deployment rules in clear configuration files, then generates outputs for tools such as IPTVBoss, Dispatcharr, and Plex.

## Motto

One source. Many outputs. Zero guesswork.

## User experience standard

ChannelForge must be usable by a careful beginner.

Documentation should assume the reader has never used Docker, Git, PowerShell, IPTV tools, M3U playlists, XMLTV guides, IPTVBoss, Dispatcharr, or Plex before.

Instructions must be exact, sequential, and easy to verify.

## Code standard

Code should be easy to understand before it is clever.

Public functions must be clearly commented. Non-obvious logic must explain why it exists. Anything that touches production data must be explicit about what it changes.

## Safety standard

ChannelForge must fail safely.

Generated output should be previewed before deployment. Production files must not be overwritten without explicit approval.

## Architecture standard

The domain model is independent of IPTVBoss, Dispatcharr, Plex, or any specific output system.

IPTVBoss is an output target, not the core model.

## Backup standard

Nothing that modifies production data may run without backups.

Required backup points:

1. Before starting any production-changing operation.

2. After completing the operation successfully.

Backups must be clearly named, timestamped, and stored outside the working output folder.

## Testing and release standard

No code may be committed, tagged, or pushed until:

- Relevant tests pass locally.

- Full test suite passes locally.

- CI passes after push.

- Any production-impacting logic has been reviewed.

- A bug and regression sweep has been completed.

- A security review has been completed.

## Security standard

Security is a primary project requirement.

ChannelForge must:

- Never commit secrets.

- Never expose provider tokens in logs or reports.

- Never overwrite production data without confirmation.

- Validate paths before writing files.

- Prefer safe defaults.

- Treat generated playlists, XMLTV files, logs, databases, and backups as sensitive.

## Documentation standard

Every major feature must include beginner-friendly documentation.

Good documentation explains:

1. What this does.

2. Why it matters.

3. Exactly how to use it.

4. What success looks like.

5. What to do if something fails.

## Definition of Done

The authoritative definition of done is in [CONSTITUTION.md](CONSTITUTION.md).
