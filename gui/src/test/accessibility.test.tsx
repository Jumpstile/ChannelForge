import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import App from '../App'
import tokensCss from '../styles/tokens.css?raw'
describe('shell accessibility scaffolding', () => {
  it('provides landmark regions, a named workflow navigation, and a main heading', () => {
    render(<App />)

    expect(screen.getByRole('navigation', { name: 'Workflow pages' })).toBeInTheDocument()
    expect(screen.getByRole('main')).toBeInTheDocument()
    expect(screen.getByRole('contentinfo')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
  })

  it('provides a named Guided Setup step region', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Guided setup steps' })).toBeInTheDocument()
  })

  it('names browser source controls and explicit no-guide state', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))

    expect(screen.getByRole('status', { name: 'Workspace status' })).toHaveTextContent('Server-owned')
    expect(screen.getByRole('heading', { name: 'Workspace ready' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Choose workspace' })).not.toBeInTheDocument()
    expect(screen.getByText('No guide selected')).toBeInTheDocument()
    expect(screen.getByLabelText('Choose playlist')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add another playlist' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeInTheDocument()
  })
})

function darkTokens(): Record<string, string> {
  const block = /\[data-theme="dark"\]\s*\{([^}]*)\}/.exec(tokensCss)?.[1] ?? ''
  return Object.fromEntries([...block.matchAll(/(--cf-[\w-]+):\s*(#[0-9a-f]{6})\s*;/g)].map((m) => [m[1], m[2]]))
}

function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

describe('dark theme tokens', () => {
  const t = darkTokens()
  const status = ['ready', 'info', 'warning', 'review', 'error', 'disabled']

  it.each(status)('keeps %s text readable on its own surface and on the page', (name) => {
    expect(contrast(t[`--cf-color-${name}`], t[`--cf-color-${name}-surface`])).toBeGreaterThanOrEqual(4.5)
    expect(contrast(t[`--cf-color-${name}`], t['--cf-color-surface']) ).toBeGreaterThanOrEqual(4.5)
  })

  it.each([
    ['--cf-color-ink', '--cf-color-canvas'],
    ['--cf-color-ink', '--cf-color-surface'],
    ['--cf-color-ink-muted', '--cf-color-surface'],
    ['--cf-color-ink-subtle', '--cf-color-surface'],
    ['--cf-color-brand', '--cf-color-surface'],
    ['--cf-color-brand', '--cf-color-brand-wash-strong'],
    ['--cf-color-on-brand', '--cf-color-brand'],
    ['--cf-color-on-brand', '--cf-color-brand-hover'],
    ['--cf-color-ink-inverse', '--cf-color-ink'],
    ['--cf-color-ink-muted', '--cf-color-nav'],
    ['--cf-color-nav-disabled', '--cf-color-nav'],
  ])('keeps %s readable on %s', (fg, bg) => {
    expect(contrast(t[fg], t[bg])).toBeGreaterThanOrEqual(4.5)
  })

  it('keeps the focus ring visible against the page and cards', () => {
    expect(contrast(t['--cf-color-focus'], t['--cf-color-canvas'])).toBeGreaterThanOrEqual(3)
    expect(contrast(t['--cf-color-focus'], t['--cf-color-surface'])).toBeGreaterThanOrEqual(3)
  })
})
