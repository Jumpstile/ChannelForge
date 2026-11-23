# Design note: timeline grid and printable summary (issue #43)

Design note only. No code and no tests. Written Nov 23, 2026. Nothing was run.

Owner decision (Nov 23, 2026): build BOTH a printable summary AND a timeline grid.

Both are review tools for the person who builds the lineup. They read the accepted generation and write nothing. Neither shows stream URLs, tokens, or file paths.

## Part 1: Timeline grid

### Layout

- Rows are channels. Columns are time. Each event is a block as wide as its length.
- Channel name stays fixed on the left while the grid scrolls sideways. Time header stays fixed on top.
- Default window: 3 hours, 30-minute marks. A "now" line shows the current time.
- A channel with `guide: null` is shown as a row with the text "No guide". It is never hidden.
- Event text is plain: title and start-end time. Details open on selection.

### Date and time navigation

- Buttons: Earlier, Later, Now, and a date picker.
- Window size choices: 2, 3, 6, 12 hours. Default 3.
- The browser asks the engine for one window at a time (start, length, page of channels). It never loads a whole guide.

### Time zones and DST

- Data is stored in UTC. The grid shows one chosen zone, named on screen.
- Default zone: the computer's zone. Owner decision needed: allow picking another zone? Option A: computer zone only. Option B: pick any zone. Recommendation: A first.
- Spring gap hour (clock skips): that local hour does not exist. The grid shows a marked jump; events keep true length.
- Fall overlap hour (clock repeats): that local hour happens twice. The grid shows both, labeled first and second, in true order. It never merges or drops an event.
- An event is placed by its UTC start. Local time is only a label.
- Day boundary: a window that crosses midnight shows the date at the crossing.

### Long events

- Event longer than the window: clipped at the edge, with an arrow showing it continues.
- Event longer than 24 hours: shown, flagged "very long", never cut from the data.
- Zero or negative length: shown as a thin marker with a warning, never dropped.
- Overlapping events on one channel: stacked in sub-rows. None hidden.

### Keyboard

- Arrow keys move between events. Page Up and Page Down move the window by its size. Home goes to Now.
- Enter opens details. Escape closes them.
- Tab order: toolbar, grid, details. Focus is always visible. Meets ADR-0006 (recognition, progressive disclosure).

### Large-list limits

- Server pages channels: at most 50 rows per request (same cursor style as lineup workspace).
- Window length capped at 12 hours.
- Draw only visible rows and columns.
- If limits cut the view, the screen says so and shows the total.

## Part 2: Printable summary

### What it contains

- Title, lineup name, date made, the zone used.
- Counts: channels, groups, channels with no guide, channels with no logo.
- Per group: channel number and name, one line each.
- A "needs a look" list: the same reasons the view shows.
- Optional: one day of events per channel (off by default).

### Page and format

- Default Letter (US); A4 offered. Portrait. Browser print dialog. No new PDF tool.
- A print style sheet hides buttons and navigation. Black text on white.
- Page numbers and the date in the footer.

### What is left out

- Stream URLs, playlist or guide URLs, credentials, file paths, logos as images, event descriptions, internal ids.

Owner decision needed: paper size default. Option A: Letter. Option B: follow the computer's locale. Recommendation: B, with Letter as fallback.

## Order

1. Printable summary (small, needs only the lineup list route).
2. Timeline grid (needs a guide window route).

## Not verified

- No code read. Whether the engine keeps per-event times in accepted state, or only a guide file reference.
- Whether a guide window route exists.
- Print behavior in any browser.
