import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../App'
import { appearanceStorageKey } from '../app/appearance'

const storageData: Record<string, string> = {}
const localStorageMock = {
  getItem: (key: string) => storageData[key] ?? null,
  setItem: (key: string, value: string) => {
    storageData[key] = value
  },
  removeItem: (key: string) => {
    delete storageData[key]
  },
  clear: () => {
    Object.keys(storageData).forEach((key) => delete storageData[key])
  },
} as Storage
type MockPreference = {
  setMatches: (matches: boolean) => void
}

function mockSystemPreference(matches: boolean): MockPreference {
  const listeners = new Set<(event: MediaQueryListEvent) => void>()
  let currentMatches = matches

  vi.stubGlobal('matchMedia', (query: string) => ({
    matches: currentMatches,
    media: query,
    addEventListener: (_event: string, listener: (event: MediaQueryListEvent) => void) => listeners.add(listener),
    removeEventListener: (_event: string, listener: (event: MediaQueryListEvent) => void) => listeners.delete(listener),
  }))

  return {
    setMatches(nextMatches) {
      currentMatches = nextMatches
      listeners.forEach((listener) => listener({ matches: nextMatches } as MediaQueryListEvent))
    },
  }
}

function renderApp(fetchStatus = vi.fn().mockResolvedValue(null)) {
  return render(<App fetchStatus={fetchStatus} />)
}

describe('appearance mode', () => {
  beforeEach(() => {
    Object.defineProperty(window, 'localStorage', { configurable: true, value: localStorageMock })
    window.localStorage.clear()
    document.documentElement.removeAttribute('data-appearance-mode')
    document.documentElement.removeAttribute('data-theme')
    document.documentElement.style.removeProperty('color-scheme')
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    window.localStorage.clear()
  })

  it('defaults to System and explains what System means', () => {
    mockSystemPreference(false)
    renderApp()

    expect(screen.getByRole('combobox', { name: 'Appearance' })).toHaveValue('system')
    expect(screen.getByText('System follows your device setting.')).toBeInTheDocument()
    expect(document.documentElement.dataset.appearanceMode).toBe('system')
  })

  it.each(['light', 'dark'] as const)('applies the %s appearance mode', async (mode) => {
    mockSystemPreference(false)
    const user = userEvent.setup()
    renderApp()

    await user.selectOptions(screen.getByRole('combobox', { name: 'Appearance' }), mode)

    await waitFor(() => expect(document.documentElement.dataset.theme).toBe(mode))
    expect(document.documentElement.dataset.appearanceMode).toBe(mode)
  })

  it('follows a changed system preference while System is selected', async () => {
    const preference = mockSystemPreference(false)
    renderApp()

    expect(document.documentElement.dataset.theme).toBe('light')
    preference.setMatches(true)

    await waitFor(() => expect(document.documentElement.dataset.theme).toBe('dark'))
  })

  it('persists the selected mode across an app remount', async () => {
    mockSystemPreference(false)
    const user = userEvent.setup()
    const firstRender = renderApp()

    await user.selectOptions(screen.getByRole('combobox', { name: 'Appearance' }), 'dark')
    await waitFor(() => expect(window.localStorage.getItem(appearanceStorageKey)).toBe('dark'))
    firstRender.unmount()

    renderApp()

    expect(screen.getByRole('combobox', { name: 'Appearance' })).toHaveValue('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
  })

  it.each(['light', 'dark', 'system'] as const)('keeps the ready dashboard readable in %s mode', async (mode) => {
    mockSystemPreference(false)
    const user = userEvent.setup()
    renderApp(vi.fn().mockResolvedValue({ lineupAccepted: false }))

    await user.selectOptions(screen.getByRole('combobox', { name: 'Appearance' }), mode)
    expect(await screen.findByRole('heading', { name: 'ChannelForge is running' })).toBeInTheDocument()
    expect(screen.getByText('No lineup has been accepted yet.')).toBeInTheDocument()
    expect(screen.getByText('Your lineup workbench')).toBeInTheDocument()
  })

  it.each(['light', 'dark', 'system'] as const)('keeps the unavailable dashboard readable in %s mode', async (mode) => {
    mockSystemPreference(false)
    const user = userEvent.setup()
    renderApp()

    await user.selectOptions(screen.getByRole('combobox', { name: 'Appearance' }), mode)
    expect(await screen.findByRole('heading', { name: 'ChannelForge status is unavailable' })).toBeInTheDocument()
    expect(screen.getByText('Read-only status.')).toBeInTheDocument()
    expect(screen.getByText('Your lineup workbench')).toBeInTheDocument()
  })
})
