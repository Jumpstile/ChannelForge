\# ChannelForge Style Guide



\## Motto



One source. Many outputs. Zero guesswork.



\## Commenting standards



\- Code must be commented for intent, not noise.

\- Every public function must explain what it does.

\- Any non-obvious logic must include a short comment explaining why it exists.

\- Any code that touches production files must clearly document what it changes.

\- Avoid clever one-liners when a clear multi-line version is easier to understand.

\- Comments should help a future maintainer understand the decision, not restate the command.



\## Documentation standards



\- Documentation must be written for beginners.

\- Do not assume the reader knows Docker, Git, PowerShell, IPTV, XMLTV, M3U, IPTVBoss, Dispatcharr, or Plex.

\- Every procedure must include:

&#x20; - what the step does

&#x20; - where to click or what command to run

&#x20; - what success looks like

&#x20; - what to do if it fails

\- Prefer exact commands over vague descriptions.

\- Avoid unexplained acronyms.

\- Keep instructions clear, direct, and sequential.## Design principles



\- Optimize for maintainability over cleverness.

\- Prefer obvious, testable code over compact code.

\- Domain objects must not reference infrastructure-specific systems.

\- Generated files are disposable artifacts.

\- Source data is the authority.

\- Every important decision should be explainable.



\## PowerShell standards



\- Target PowerShell 7+.

\- Public functions use approved verbs.

\- Public functions live in `src/ChannelForge/Public`.

\- Private helpers live in `src/ChannelForge/Private`.

\- Classes live in `src/ChannelForge/Classes`.

\- Tests live in `tests/unit`.

\- Avoid global state.

\- Avoid hidden filesystem side effects.

\- Throw terminating errors for invalid required input.

\- Return objects, not formatted strings.



\## Function rules



\- One function should do one job.

\- Prefer explicit parameters.

\- Use `\\\[CmdletBinding()]` for public functions.

\- Validate required file paths before reading.

\- Do not write production files unless explicitly requested.

\- Do not silently ignore malformed input.



\## Testing rules



\- New public functions require Pester tests.

\- Bug fixes require regression tests.

\- Parser tests should include malformed and edge-case fixtures.

\- CI must remain green.



\## Logging rules



\- Avoid random `Write-Host` in engine code.

\- Build/report functions may write human-readable output.

\- Future logging should flow through a central ChannelForge logger.



\## Security rules



\- Do not commit real provider credentials.

\- Do not commit tokenized provider URLs to public repositories.

\- Keep local secrets in ignored `\\\*.local.json` files.

\- Do not commit generated playlists, XMLTV files, H2 databases, or backups.

