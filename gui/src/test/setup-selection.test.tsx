import { describe, expect, it } from 'vitest'
import {
  applySetupSelectionResult,
  createInitialPlaylistContentState,
  playlistContentStateFromResult,
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
})
