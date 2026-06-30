# Safe Local Configuration

This page answers: **how do I give ChannelForge my real provider data without ever risking it ending up in Git?**

## The one rule

**Never edit a tracked file with real values — especially never `data/providers/mybunny.json`.** Tracked files are public/shared by definition; anything real you put in one can end up committed, pushed, and exposed. ChannelForge has a dedicated local-only workflow instead, and `scripts/Build-Lineup.ps1` uses it automatically — there is no scenario where editing a tracked file is the right move.

## Step by step

1. Copy the template:

   ```powershell
   Copy-Item data/providers/provider.example.json data/providers/provider.local.json
   ```

2. Edit `data/providers/provider.local.json` with your real source name(s), URL(s), and (if you're following [Build Your First Lineup](Build-Your-First-Lineup.md)) a `local_playlist` path for each source.
3. That's it. `Build-Lineup.ps1` automatically discovers and uses a single `data/providers/*.local.json` file in place of the tracked example. No flag, no edit to anything tracked, nothing to remember to undo afterward.

`provider.local.json` is already covered by `.gitignore`, so it can't be accidentally committed. Never rename it to drop the `.local.` segment, and never `git add` it.

## Why `example.invalid`?

Anywhere you see a URL like `https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports` in a tracked repository file, it's a deliberate placeholder. `.invalid` is a domain reserved by standard specifically so it can never resolve to a real host — it's used precisely so a tracked example can show the *shape* of a provider URL without being mistaken for a real one. Your real provider URL belongs only in your own `provider.local.json`, never in a tracked file, an issue, a commit, or a chat message.

## How to avoid exposing credentials

- Real provider/EPG URLs, account IDs, and tokens go in `provider.local.json` (or `epg_sources.local.json`) only — never in a tracked file.
- Never paste a real URL into a GitHub issue, pull request, commit message, or chat, even temporarily "to show someone the problem." Redact it first.
- **The `provider` label and each source's `name` are display fields, not secrets, and they *do* appear in build reports** (`output/reports/build-summary.json` and `lineup-plan.md`). Only the `url` field is stripped from those reports. Use a plain label like `my-provider`, never a token, account ID, or other secret-shaped value, in `provider` or `name`.
- A real local M3U playlist file (see [Build Your First Lineup](Build-Your-First-Lineup.md)) contains real stream URLs and is exactly as sensitive — keep it under `data/playlists/` with a `.local.m3u` filename, same rule.

## If you have more than one local file

If `data/providers/` ever contains more than one `*.local.json` file, the build refuses to guess which one you meant and fails with a clear error naming both files. Keep exactly one, or use the explicit override below.

## Advanced: pointing at a specific file

For scripted or CI use, `scripts/Build-Lineup.ps1` accepts an explicit `-ProviderPath` parameter that takes precedence over auto-discovery (and skips the multiple-file check entirely, since you've already said exactly which file to use):

```powershell
pwsh -File scripts/Build-Lineup.ps1 -ProviderPath provider.local.json
```

The path is still confined to `data/providers/` — an absolute path, a UNC path, `..` traversal, a directory, or a non-`.json` file is rejected, not silently accepted.

## Where to go next

- For the exact precedence rules and how this is implemented and tested, see [DEVELOPER_GUIDE.md](../developer/DEVELOPER_GUIDE.md#provider-config-resolution-issue-20) and [SECURITY.md](../reference/SECURITY.md) — this page intentionally summarizes rather than repeats those.
- Ready to run a real build? → [Build Your First Lineup](Build-Your-First-Lineup.md)
