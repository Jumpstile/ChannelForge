# Sources

This page answers: **what does ChannelForge mean by a "source"?**

A **source** is one entry in your provider configuration — typically one category of channels from your provider, like "Sports" or "Movies". Each source has:

- A `name` and `group` label (display only — see [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#how-to-avoid-exposing-credentials) for why these aren't secret-safe).
- A `url` (the provider URL for this category — treated as a secret).
- An `enabled` flag.
- An optional `local_playlist` path, pointing at an `.m3u` file already saved to disk. When present, it is authoritative over the URL.

## Which sources participate in a build today

A source is included in `output/merged.m3u` when it is `enabled: true` and has either a safe local playlist path or a supported remote URL. A local playlist is authoritative when both are present. An enabled source with neither a usable local path nor a supported remote URL fails closed; it is never silently skipped. Remote acquisition is bounded HTTPS on port 443 and uses the same streaming parser as local input.

`output/reports/lineup-plan.md`'s "Provider M3U Sources" section lists every configured source and its enabled/playlist state, so you can always see why a source was or wasn't included.

## EPG sources are separate

Your provider's M3U sources (above) are a different list from EPG sources (`data/epg/epg_sources.json` or a local equivalent), which describe guide-data inputs rather than channel playlists. Enabled local XMLTV path entries and supported remote HTTPS XMLTV entries use the XMLTV pipeline; M3U and XMLTV remain separate source types. See [XMLTV](XMLTV.md) for the current boundary.

## Guide evidence and source relationships

ChannelForge keeps guide evidence read-only until the normal candidate → review → explicit acceptance → immutable generation path runs. Evidence can come from provider display text, provider M3U metadata, XMLTV, a documented AED-derived XMLTV/M3U export, a future schedule source, or existing accepted ChannelForge knowledge.

Every evidence record carries a confidence state and source relationship. **Confirmed** means the available evidence is coherent; **safe candidate** means it is useful but provisional; **needs review** means a person must decide; **unresolved** means required identity or timing evidence is missing; **contradiction** means sources disagree; **stale source** means freshness has expired; and **source unavailable** means the source could not provide usable evidence. A mirror is not independent confirmation.

These states are evidence about a guide, not permission to overwrite an accepted lineup. Stale or unavailable evidence preserves accepted state and last-known-good output.

## Native pattern inference over sources

`Invoke-ChannelForgeGuidePatternInference` can analyze plain representative display names or an array of Stage A evidence records. Plain examples receive the caller's source scope; evidence inputs retain their source ID, source family, evidence type, channel reference, freshness, confidence, and relationship. The result is a structured candidate with semantic field candidates and a per-example preview, not an accepted mapping.

Independent sources may provide agreement or contradiction for the same channel reference. A mirror source is retained for provenance but is not counted as independent confirmation. Missing, stale, unavailable, ambiguous, or contradictory evidence produces review/degraded state and never removes a channel or replaces accepted knowledge. Passing an existing candidate rule enables deterministic drift comparison; a changed naming grammar is reported with adoption left `NotApplied`.
The beginner review surface turns that candidate into a plain-language report:

```powershell
Get-ChannelForgeGuidePatternReview -InferenceResult $pattern -OutputFormat Markdown
```

The report is review evidence, not an accepted mapping. It identifies the detected channel fields, representative event values, confidence, source relationships, freshness, and drift. JSON is available with `-OutputFormat Json`; both formats omit raw examples and sensitive provider data. Contradictions, stale sources, and unavailable sources remain blocked rather than being resolved by guesswork.

### Beginner event-pattern preview

The Guided Setup / Beginner Workflow can analyze representative provider display names for volatile event-channel groups without turning those names into an accepted source rule. Run `scripts/Build-My-Lineup.ps1 -EventPatternPreview` with at least three examples, and include `-EventPatternType` for categories such as fights, PPV, temporary events, leagues, single-team channels, streaming events, or sports. The workflow calls native semantic inference and the beginner review projection; it does not require regular expressions.

The preview writes deterministic, redacted JSON, Markdown, and text reports under `output/reports/`. The report preserves review state, confidence, provenance, freshness/drift, and safe next action. `Confirmed` and `SafeCandidate` are still provisional; `NeedsReview`, `Unresolved`, `Contradiction`, `StaleSource`, and `SourceUnavailable` are blocked. The preview is candidate-only, cannot be combined with `-Accept`, never publishes XMLTV or another guide, and never changes provider, downstream, or accepted state.

### Future acceptance planning

`Get-ChannelForgeGuidePatternAcceptancePlan` consumes the Stage B candidate or
Stage C/D review and explains what explicit acceptance would require later.
Confirmed and SafeCandidate results are future-eligible only; review,
contradiction, stale, unavailable, insufficient-example, and drift results stay
blocked or review-only with a reason. Stable title/time/pattern identity is
separate from volatile enrichment. Statistics, game summaries, standings, and
roster/player facts are eligible as current only when freshness TTL, timestamps,
season/competition context, subject identity, provenance, confidence, and
contradiction checks prove them; otherwise they are omitted or marked for
review. The plan is deterministic and redacted, returns distinct Markdown and
plain-text renderings, and remains `CandidateOnly` with no adoption or provider,
downstream, guide, or accepted-state mutation.

## Where to go next

- Setting up your real sources? → [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md)
- Full schema for a source entry → [Configuration Reference](../Reference/Configuration-Reference.md)
