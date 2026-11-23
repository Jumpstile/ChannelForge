import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { applyTextSize, readTextSize, textSizeStorageKey } from '../app/textSize'
import { TextSizeControl } from '../components/TextSizeControl'
import tokensCss from '../styles/tokens.css?raw'

let store: Map<string, string>

beforeEach(() => {
  store = new Map<string, string>()
  vi.stubGlobal('localStorage', {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
  })
  document.documentElement.removeAttribute('data-text-size')
})

afterEach(() => vi.unstubAllGlobals())

const size = () => document.documentElement.dataset.textSize

describe('text size', () => {
  it('defaults to Normal', () => {
    render(<TextSizeControl />)
    expect(screen.getByRole('group', { name: 'Text size' })).toBeInTheDocument()
    expect(screen.getByLabelText('Normal')).toBeChecked()
    expect(readTextSize()).toBe('normal')
  })

  it('applies the choice, saves it, and it survives reload', () => {
    render(<TextSizeControl />)
    fireEvent.click(screen.getByLabelText('Extra large'))
    expect(size()).toBe('extra-large')
    expect(store.get(textSizeStorageKey)).toBe('extra-large')
    expect(readTextSize()).toBe('extra-large')
    applyTextSize(readTextSize())
    expect(size()).toBe('extra-large')
  })

  it('falls back to Normal when the stored value is not a choice', () => {
    store.set(textSizeStorageKey, 'huge')
    expect(readTextSize()).toBe('normal')
    render(<TextSizeControl />)
    expect(screen.getByLabelText('Normal')).toBeChecked()
  })

  it('falls back to Normal when storage is blocked', () => {
    const blocked = () => { throw new Error('blocked') }
    vi.stubGlobal('localStorage', { getItem: blocked, setItem: blocked })
    expect(readTextSize()).toBe('normal')
    render(<TextSizeControl />)
    fireEvent.click(screen.getByLabelText('Large'))
    expect(size()).toBe('large')
  })

  it('defines the focus ring in both themes and larger text steps', () => {
    const light = /:root\s*\{([^}]*)\}/.exec(tokensCss)?.[1] ?? ''
    const dark = /\[data-theme="dark"\]\s*\{([^}]*)\}/.exec(tokensCss)?.[1] ?? ''
    expect(light).toMatch(/--cf-color-focus:\s*#[0-9a-f]{6}/)
    expect(dark).toMatch(/--cf-color-focus:\s*#[0-9a-f]{6}/)
    expect(tokensCss).toMatch(/\[data-text-size="large"\]/)
    expect(tokensCss).toMatch(/\[data-text-size="extra-large"\]/)
  })
})
