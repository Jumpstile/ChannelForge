import { describe, expect, it } from 'vitest'
import {
  applySetupSelectionResult,
  createInitialGuideContentState,
  createInitialPlaylistContentState,
  createInitialPlaylistGuideMatchState,
  guideContentStateFromResult,
  playlistContentStateFromResult,
  playlistGuideMatchStateFromResult,
  safeMatchMessage,
  setPlaylistGuideMatchChecking,
  setSetupSelectionChecking,
  setupSelectionStates,
} from '../app/setupSelection'
describe('display-safe setup selection contract', () => {
  it('starts each setup item with truthful unselected and unchecked states', () => {
    expect(Object.keys(setupSelectionStates)).toEqual(['workspace', 'playlist', 'guide'])

    for (const kind of ['workspace', 'playlist', 'guide'] as const) {
      expect(setupSelectionStates[kind]).toEqual({
        kind,
        status: 'not-selected',
        validationStatus: 'not-checked',
        displayLabel: 'Not selected',
        validationLabel: 'Not checked',
        detail: `No ${kind} is selected.`,
      })
    }
  })

  it('records a ready-to-inspect selection without exposing native values', () => {
    const states = applySetupSelectionResult(setupSelectionStates, {
      kind: 'workspace',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
    })

    expect(states.workspace).toMatchObject({
      status: 'selected',
      validationStatus: 'ready-to-inspect',
      displayLabel: 'Selected',
      validationLabel: 'Ready to inspect',
      detail: 'Workspace is ready to inspect.',
    })
    expect(JSON.stringify(states)).not.toMatch(/[A-Za-z]:[\\/]|\\\\|https?:\/\//i)
    expect(JSON.stringify(states)).not.toMatch(/(?:token|password|secret|credential)/i)
  })

  it('maps only the playlist content summary into fixed display-safe copy', () => {
    const checked = playlistContentStateFromResult({
      kind: 'playlist',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
      playlistContent: {
        contentStatus: 'checked',
        entryCount: 4,
        reasonCode: null,
      },
    })
    const attention = playlistContentStateFromResult({
      kind: 'playlist',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
      playlistContent: {
        contentStatus: 'needs-attention',
        entryCount: null,
        reasonCode: 'orphan-stream-line',
      },
    })

    expect(createInitialPlaylistContentState()).toEqual({
      status: 'not-checked',
      label: 'Not checked',
      detail: 'Playlist content has not been checked.',
      entryCount: null,
    })
    expect(checked).toEqual({
      status: 'checked',
      label: 'Checked',
      detail: 'Playlist content checked. 4 channel entries found.',
      entryCount: 4,
    })
    expect(attention).toMatchObject({
      status: 'needs-attention',
      label: 'Needs attention',
      detail: 'Playlist content needs attention. The file contains an unexpected stream line.',
      entryCount: null,
    })
  })

  it('maps only the guide content summary into fixed display-safe copy', () => {
    const checked = guideContentStateFromResult({
      kind: 'guide',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
      guideContent: {
        contentStatus: 'checked',
        channelCount: 2,
        programmeCount: 4,
        reasonCode: null,
      },
    })
    const attention = guideContentStateFromResult({
      kind: 'guide',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
      guideContent: {
        contentStatus: 'needs-attention',
        channelCount: null,
        programmeCount: null,
        reasonCode: 'malformed-xml',
      },
    })

    expect(createInitialGuideContentState()).toEqual({
      status: 'not-checked',
      label: 'Not checked',
      detail: 'Guide content has not been checked.',
      channelCount: null,
      programmeCount: null,
    })
    expect(checked).toEqual({
      status: 'checked',
      label: 'Checked',
      detail: 'Guide content checked. 2 channels and 4 programmes found.',
      channelCount: 2,
      programmeCount: 4,
    })
    expect(attention).toMatchObject({
      status: 'needs-attention',
      label: 'Needs attention',
      detail: 'Guide content needs attention. The file is not a valid XMLTV document.',
      channelCount: null,
      programmeCount: null,
    })
  })

  it('represents an in-flight check without changing selection identity', () => {
    const selected = applySetupSelectionResult(setupSelectionStates, {
      kind: 'workspace',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
    })
    const checking = setSetupSelectionChecking(selected, 'workspace')

    expect(checking.workspace).toMatchObject({
      status: 'selected',
      validationStatus: 'checking',
      displayLabel: 'Selected',
      validationLabel: 'Checking',
      detail: 'Checking workspace...',
    })
  })

  it('contains no path, URL, or credential-shaped display state', () => {
    const displayState = JSON.stringify(setupSelectionStates)

    expect(displayState).not.toMatch(/[A-Za-z]:[\\/]/)
    expect(displayState).not.toMatch(/\\\\/)
    expect(displayState).not.toMatch(/https?:\/\//i)
    expect(displayState).not.toMatch(/(?:token|password|secret|credential)/i)
  })
  it('maps aggregate matching states without exposing source values', () => {
    expect(createInitialPlaylistGuideMatchState()).toMatchObject({
      status: 'not-checked',
      label: 'Not checked',
      matchedCount: null,
      requiresReview: false,
    })
    expect(setPlaylistGuideMatchChecking()).toMatchObject({
      status: 'checking',
      label: 'Checking',
      matchedCount: null,
    })

    const review = playlistGuideMatchStateFromResult({
      matchStatus: 'review-needed',
      playlistEntryCount: 4,
      guideChannelCount: 4,
      matchedCount: 1,
      unmatchedPlaylistCount: 1,
      ambiguousCount: 2,
      guideOnlyCount: 1,
      requiresReview: true,
      reasonCode: 'ambiguous-identity',
    })

    expect(review).toEqual({
      status: 'review-needed',
      label: 'Review needed',
      detail: 'Review needed. 2 playlist channel entries need review.',
      playlistEntryCount: 4,
      guideChannelCount: 4,
      matchedCount: 1,
      unmatchedPlaylistCount: 1,
      ambiguousCount: 2,
      guideOnlyCount: 1,
      requiresReview: true,
    })
    expect(JSON.stringify(review)).not.toMatch(
      /(?:channel-id|hidden|title|https?:\/\/|[A-Za-z]:[\\/]|token|password|secret|credential)/i,
    )
  })

  it.each([
    ['missing-playlist', 'Choose and check both files before checking their match.'],
    ['missing-guide', 'Choose and check both files before checking their match.'],
    ['playlist-not-ready', 'Choose and check both files before checking their match.'],
    ['guide-not-ready', 'Choose and check both files before checking their match.'],
    ['playlist-content-invalid', 'The playlist or guide content needs attention before matching.'],
    ['guide-content-invalid', 'The playlist or guide content needs attention before matching.'],
    ['playlist-unavailable', 'The selected playlist or guide cannot be opened.'],
    ['guide-unavailable', 'The selected playlist or guide cannot be opened.'],
    ['unsupported-format', 'The guide format cannot be checked. Choose a supported XMLTV guide.'],
    ['too-large', 'The selected file is too large to check safely.'],
    ['stale-selection', 'The selected files changed. Check the playlist and guide again.'],
    ['unmatched-identity', 'The match could not be checked. Try again.'],
    ['ambiguous-identity', 'The match could not be checked. Try again.'],
    ['check-unavailable', 'The match could not be checked. Try again.'],
  ] as const)('maps the %s reason to fixed copy', (reasonCode, expected) => {
    expect(
      safeMatchMessage({
        matchStatus: 'blocked',
        playlistEntryCount: null,
        guideChannelCount: null,
        matchedCount: null,
        unmatchedPlaylistCount: null,
        ambiguousCount: null,
        guideOnlyCount: null,
        requiresReview: false,
        reasonCode,
      }),
    ).toBe(expected)
  })
})
