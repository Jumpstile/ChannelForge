import { describe, expect, it } from 'vitest'
import { setupSelectionStates } from '../app/setupSelection'

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

  it('contains no path, URL, or credential-shaped display state', () => {
    const displayState = JSON.stringify(setupSelectionStates)

    expect(displayState).not.toMatch(/[A-Za-z]:[\\/]/)
    expect(displayState).not.toMatch(/\\\\/)
    expect(displayState).not.toMatch(/https?:\/\//i)
    expect(displayState).not.toMatch(/(?:token|password|secret|credential)/i)
  })
})
