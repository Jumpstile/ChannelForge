import { describe, expect, it } from 'vitest'
import { applySetupSelectionResult, setupSelectionStates } from '../app/setupSelection'

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

  it('records selected status without changing validation or exposing native values', () => {
    const states = applySetupSelectionResult(setupSelectionStates, {
      kind: 'workspace',
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'not-checked',
      errorCode: null,
    })

    expect(states.workspace).toMatchObject({
      status: 'selected',
      validationStatus: 'not-checked',
      displayLabel: 'Selected',
      validationLabel: 'Not checked',
      detail: 'Workspace selected.',
    })
    expect(JSON.stringify(states)).not.toMatch(/[A-Za-z]:[\\/]|\\\\|https?:\/\//i)
    expect(JSON.stringify(states)).not.toMatch(/(?:token|password|secret|credential)/i)
  })

  it('contains no path, URL, or credential-shaped display state', () => {
    const displayState = JSON.stringify(setupSelectionStates)

    expect(displayState).not.toMatch(/[A-Za-z]:[\\/]/)
    expect(displayState).not.toMatch(/\\\\/)
    expect(displayState).not.toMatch(/https?:\/\//i)
    expect(displayState).not.toMatch(/(?:token|password|secret|credential)/i)
  })
})
