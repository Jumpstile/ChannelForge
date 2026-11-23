import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import App from '../App'
import { ChannelLineupPage } from '../pages/ChannelLineupPage'
import type { LineupChannel, LineupFetcher } from '../app/lineup'
import css from '../styles/global.css?raw'

const channel = (n: number, over: Partial<LineupChannel> = {}): LineupChannel =>
  ({ id: `id-${n}`, number: n, name: `Test Channel ${n}`, group: 'Test Group', current: null, next: null, ...over })

describe('Channel lineup page', () => {
  it('lists channels with number, name, group, and now/next', async () => {
    const fetchPage: LineupFetcher = async () => ({
      generation: 'g', total: 1,
      items: [channel(7, { current: { title: 'Test Show', startUtc: 'a', stopUtc: 'b' }, next: { title: 'Test Film', startUtc: 'b', stopUtc: 'c' } })],
    })
    render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    const row = await screen.findByRole('listitem', { name: '7, Test Channel 7, Test Group, Now: Test Show · Next: Test Film' })
    expect(row).toHaveTextContent('Test Group')
    expect(row).toHaveTextContent('Now: Test Show')
  })

  it('shows a dash when the channel number is missing and no guide line', async () => {
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 1, items: [channel(0, { number: null })] })} onOpenSetup={() => {}} />)
    const row = await screen.findByRole('listitem', { name: 'No number, Test Channel 0, Test Group' })
    expect(row).toHaveTextContent('—')
    expect(row).not.toHaveTextContent('Now:')
  })

  it('shows an empty state with a Setup step', async () => {
    const user = userEvent.setup()
    const onOpenSetup = vi.fn()
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 0, items: [] })} onOpenSetup={onOpenSetup} />)
    expect(await screen.findByRole('heading', { name: 'No channels saved yet' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Go to Setup' }))
    expect(onOpenSetup).toHaveBeenCalledOnce()
  })

  it('shows a plain error and retries', async () => {
    const user = userEvent.setup()
    const fetchPage = vi.fn<LineupFetcher>().mockResolvedValueOnce(null).mockResolvedValueOnce({ generation: 'g', total: 1, items: [channel(1)] })
    render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('ChannelForge could not load your channels')
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Test Channel 1')).toBeVisible()
  })

  it('shows more channels with a keyboard-reachable button', async () => {
    const user = userEvent.setup()
    const fetchPage = vi.fn<LineupFetcher>()
      .mockResolvedValueOnce({ generation: 'g', total: 2, items: [channel(1)] })
      .mockResolvedValueOnce({ generation: 'g', total: 2, items: [channel(2)] })
    render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    await screen.findByText('Test Channel 1')
    expect(screen.getByRole('status')).toHaveTextContent('Showing 1 of 2 channels')
    await user.tab()
    await user.tab()
    expect(screen.getByRole('button', { name: 'Show more channels' })).toHaveFocus()
    await user.keyboard('{Enter}')
    expect(await screen.findByText('Test Channel 2')).toBeVisible()
    expect(fetchPage).toHaveBeenLastCalledWith(1, 'g')
    expect(screen.queryByRole('button', { name: 'Show more channels' })).not.toBeInTheDocument()
  })

  it('is an enabled navigation entry', async () => {
    const user = userEvent.setup()
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 503 }))
    render(<App />)
    const entry = screen.getByRole('button', { name: /Channel lineup/ })
    expect(entry).toBeEnabled()
    await user.click(entry)
    expect(screen.getByRole('heading', { level: 1, name: 'Your channel lineup' })).toBeInTheDocument()
  })

  it('has a Print summary button that opens the print dialog', async () => {
    const user = userEvent.setup()
    const print = vi.spyOn(window, 'print').mockImplementation(() => {})
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 1, items: [channel(1)] })} onOpenSetup={() => {}} />)
    await user.click(await screen.findByRole('button', { name: 'Print summary' }))
    expect(print).toHaveBeenCalledOnce()
  })

  it('renders a grouped print summary with the count and no stream details', async () => {
    const items = [channel(1, { group: 'News' }), channel(2, { group: 'Sports', name: 'Test Sports' }), channel(3, { group: '' })]
    const { container } = render(<ChannelLineupPage fetchPage={async () => ({ generation: 'abc123', total: 3, items })} onOpenSetup={() => {}} />)
    await screen.findByText('Test Channel 1')
    const print = container.querySelector('.lineup-print') as HTMLElement
    expect(print).toHaveTextContent('3 channels in your saved lineup')
    expect(print).not.toHaveTextContent('cut off')
    expect(Array.from(print.querySelectorAll('h2')).map((h) => h.textContent)).toEqual(['News', 'Sports', 'No group'])
    expect(print).toHaveTextContent('2 Test Sports')
    expect(print.textContent).not.toMatch(/https?:|\/api\/|\.m3u|[A-Za-z]:\\|abc123/i)
  })

  it('print styles hide the page chrome and show the summary', () => {
    expect(css).toMatch(/@media print\s*{[^}]*}?[\s\S]*\.side-nav, \.top-bar, \.app-footer, \.lineup-screen { display: none !important; }/)
    expect(css).toMatch(/\.lineup-print { display: none; }/)
    expect(css).toMatch(/\.lineup-print { display: block;/)
    expect(css).toMatch(/\.lineup-print li {[^}]*break-inside: avoid;/)
  })

  it('loads every page before printing and says so when some cannot be loaded', async () => {
    const user = userEvent.setup()
    const print = vi.spyOn(window, 'print').mockImplementation(() => {})
    const fetchPage = vi.fn<LineupFetcher>()
      .mockResolvedValueOnce({ generation: 'g', total: 3, items: [channel(1)] })
      .mockResolvedValueOnce({ generation: 'g', total: 3, items: [channel(2)] })
      .mockResolvedValueOnce(null)
    const { container } = render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    await user.click(await screen.findByRole('button', { name: 'Print summary' }))
    await vi.waitFor(() => expect(print).toHaveBeenCalledOnce())
    expect(fetchPage).toHaveBeenNthCalledWith(2, 1, 'g')
    const summary = container.querySelector('.lineup-print') as HTMLElement
    expect(summary).toHaveTextContent('2 Test Channel 2')
    expect(summary).toHaveTextContent('This summary is cut off. It lists 2 of 3 channels')
  })
})
