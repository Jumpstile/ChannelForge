import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { applyAppearance, readAppearance, watchSystemAppearance } from '../app/appearance'
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
