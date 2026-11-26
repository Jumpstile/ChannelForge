import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { applyAppearance, readAppearance, syncAppearance, watchSystemAppearance } from '../app/appearance'
import { AppearanceControl } from '../components/AppearanceControl'

let prefersDark = false
let listeners: Array<() => void> = []

beforeEach(() => {
  prefersDark = false
  listeners = []
  const store = new Map<string, string>()
  vi.stubGlobal('localStorage', {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  })
  document.documentElement.removeAttribute('data-theme')
  vi.stubGlobal('matchMedia', () => ({
    get matches() { return prefersDark },
    addEventListener: (_: string, fn: () => void) => listeners.push(fn),
    removeEventListener: (_: string, fn: () => void) => { listeners = listeners.filter((l) => l !== fn) },
  }))
})

afterEach(() => vi.unstubAllGlobals())

const theme = () => document.documentElement.dataset.theme

describe('appearance', () => {
  it('defaults to System and follows the system setting', () => {
    expect(readAppearance()).toBe('system')
    applyAppearance('system')
    expect(theme()).toBe('light')
    prefersDark = true
    applyAppearance('system')
    expect(theme()).toBe('dark')
  })

  it('re-applies when the system setting changes', () => {
    const stop = watchSystemAppearance()
    prefersDark = true
    listeners.forEach((fn) => fn())
    expect(theme()).toBe('dark')
    stop()
    expect(listeners).toHaveLength(0)
  })

  it('control switches Light/Dark, saves the choice, and it survives reload', () => {
    prefersDark = true
    render(<AppearanceControl />)
    expect(screen.getByLabelText('System')).toBeChecked()
    fireEvent.click(screen.getByLabelText('Light'))
    expect(theme()).toBe('light')
    fireEvent.click(screen.getByLabelText('Dark'))
    expect(theme()).toBe('dark')
    expect(readAppearance()).toBe('dark')
  })

  it('falls back to System when storage is blocked', () => {
    const blocked = () => { throw new Error('blocked') }
    vi.stubGlobal('localStorage', { getItem: blocked, setItem: blocked })
    render(<AppearanceControl />)
    fireEvent.click(screen.getByLabelText('Dark'))
    expect(theme()).toBe('dark')
    expect(readAppearance()).toBe('system')
  })
})

function reply(status: number, body: unknown = {}) {
  return { status, json: vi.fn().mockResolvedValue(body) } as unknown as Response
}

describe('appearance on the server', () => {
  it('sends a valid local value once when the server has none', async () => {
    window.localStorage.setItem('channelforge.appearance', 'dark')
    const request = vi.fn().mockResolvedValueOnce(reply(200, { appearance: 'system', saved: false })).mockResolvedValueOnce(reply(200, {}))
    await expect(syncAppearance(request as unknown as typeof fetch)).resolves.toBe('dark')
    expect(request).toHaveBeenCalledTimes(2)
    expect(request.mock.calls[1][0]).toBe('/api/settings')
    expect(request.mock.calls[1][1]).toMatchObject({ method: 'PUT', body: JSON.stringify({ appearance: 'dark' }) })
  })

  it('sends nothing when the server has none and the browser has no valid value', async () => {
    window.localStorage.setItem('channelforge.appearance', 'purple')
    const request = vi.fn().mockResolvedValue(reply(200, { appearance: 'system', saved: false }))
    await expect(syncAppearance(request as unknown as typeof fetch)).resolves.toBe('system')
    expect(request).toHaveBeenCalledTimes(1)
  })

  it('lets the server value win and keeps the local value only as a cache', async () => {
    window.localStorage.setItem('channelforge.appearance', 'light')
    const request = vi.fn().mockResolvedValue(reply(200, { appearance: 'dark', saved: true }))
    await expect(syncAppearance(request as unknown as typeof fetch)).resolves.toBe('dark')
    expect(request).toHaveBeenCalledTimes(1)
    expect(readAppearance()).toBe('dark')
  })

  it('uses the local value when the server cannot be reached or does not answer well', async () => {
    window.localStorage.setItem('channelforge.appearance', 'light')
    await expect(syncAppearance(vi.fn().mockRejectedValue(new Error('down')) as unknown as typeof fetch)).resolves.toBe('light')
    await expect(syncAppearance(vi.fn().mockResolvedValue(reply(401)) as unknown as typeof fetch)).resolves.toBe('light')
    window.localStorage.removeItem('channelforge.appearance')
    await expect(syncAppearance(vi.fn().mockRejectedValue(new Error('down')) as unknown as typeof fetch)).resolves.toBe('system')
  })

  it('applies the server value on load and saves a pick to the server', async () => {
    const request = vi.fn().mockResolvedValueOnce(reply(200, { appearance: 'dark', saved: true })).mockResolvedValue(reply(200, {}))
    vi.stubGlobal('fetch', request)
    render(<AppearanceControl />)
    await waitFor(() => expect(screen.getByLabelText('Dark')).toBeChecked())
    expect(theme()).toBe('dark')
    fireEvent.click(screen.getByLabelText('Light'))
    await waitFor(() => expect(request).toHaveBeenCalledWith('/api/settings', expect.objectContaining({ method: 'PUT', body: JSON.stringify({ appearance: 'light' }) })))
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('tells the user plainly when saving fails, and the pick still applies here', async () => {
    const request = vi.fn().mockResolvedValueOnce(reply(200, { appearance: 'system', saved: true })).mockResolvedValue(reply(500))
    vi.stubGlobal('fetch', request)
    render(<AppearanceControl />)
    await waitFor(() => expect(request).toHaveBeenCalledTimes(1))
    fireEvent.click(screen.getByLabelText('Dark'))
    expect(await screen.findByRole('alert')).toHaveTextContent('could not save your look choice')
    expect(theme()).toBe('dark')
  })
})
