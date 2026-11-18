# Build the Windows package from an exact commit

This page shows how to build the Windows package from one exact, known-good commit on your own computer. Use it when you need to prove which source produced a ZIP.

**This never creates a release or a tag.** It only makes a ZIP and an evidence file on your disk. Only the owner says go for a release.

You need PowerShell 7, git, and Node.js (for the GUI build). Run everything from the repository root.

1. Pick the commit. Write down its full 40-character SHA (`git rev-parse <branch-or-commit>`).
2. Check that CI is green on that exact SHA. Open the GitHub Actions runs for that commit and confirm every required check passed. If any check is red or missing, stop. Do not build.
3. Make a clean checkout at that SHA. Use a fresh clone or `git worktree`, then `git checkout --detach <SHA>`. Run `git status --porcelain` and confirm it prints nothing.
4. Build the GUI, because the package script needs `gui/dist`:

   ```powershell
   Push-Location .\gui
   npm ci
   npm run build
   Pop-Location
   ```

   `gui/dist` is not tracked by git, so this does not make the tree dirty.

5. Build the package. Pass the SHA so the script stops if `HEAD` is anything else:

   ```powershell
   ./scripts/Build-ChannelForgeWindowsPackage.ps1 -SourceCommitSha <40-character-SHA>
   ```

   - `-SourceCommitSha` must be the full 40-character lowercase SHA and must equal `HEAD`.
   - Do not use `-AllowDirty`. It is for local development only, and the script refuses a dirty tree without it.
   - `-OutputRoot` changes where the files go. The default is `output/packages/`.
   - The script downloads the pinned PowerShell runtime (or use `-PowerShellRuntimeZipPath` with a ZIP you already have) and checks its SHA-256.

6. Record the results. The script prints `PackageSha256` and `PackageSourceCommitSha`. Copy both into your notes, with the ZIP filename (`ChannelForge-v<VERSION>-alpha.1-windows-x64.zip`).
7. Find the evidence file. It is next to the ZIP: `output/packages/<ZIP filename>.evidence.json`. It holds `PackageSha256`, `PackageSourceCommitSha`, `PackageManifestSha256`, the bundled PowerShell hashes, and `FileCount`. Check that `PackageSourceCommitSha` equals your SHA.
8. Check the ZIP yourself:

   ```powershell
   (Get-FileHash -LiteralPath .\output\packages\<ZIP filename> -Algorithm SHA256).Hash.ToLowerInvariant()
   ```

   The result must equal `PackageSha256` in the evidence file.

Keep the ZIP and the evidence file together. Do not upload them or tag the commit. For what the script does inside, see [WINDOWS_PACKAGING.md](WINDOWS_PACKAGING.md).
