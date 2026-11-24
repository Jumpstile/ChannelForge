import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { TimelineGridPage } from '../pages/TimelineGridPage'
import { fetchLineupPage } from '../app/lineup'
import type { LineupChannel, LineupWindowFetcher } from '../app/lineup'

const now = () => new Date('2026-06-01T10:00:30Z')

const channel = (n: number, over: Partial<LineupChannel> = {}): LineupChannel =>
  ({ id: `id-${n}`, number: n, name: `Test Channel ${n}`, group: '', logoStatus: 'present', guideState: 'bound', attention: [], current: null, next: null, programmes: [], ...over })

const early = { title: 'Early Show', startUtc: '2026-06-01T09:30:00Z', stopUtc: '2026-06-01T10:30:00Z' }
const late = { title: 'Late Show', startUtc: '2026-06-01T12:00:00Z', stopUtc: '2026-06-01T14:00:00Z' }

describe('Timeline page', () => {
  it('asks for the next three hours in UTC and labels the times as UTC', async () => {
    const fetchPage = vi.fn<LineupWindowFetcher>(async () => ({ generation: 'g', total: 1, items: [channel(5, { programmes: [early] })] }))
    render(<TimelineGridPage fetchPage={fetchPage} now={now} />)
    expect(await screen.findByText(/Showing 10:00–13:00/)).toHaveTextContent('UTC')
    expect(fetchPage).toHaveBeenCalledWith(0, null, { from: '2026-06-01T10:00:00Z', to: '2026-06-01T13:00:00Z' })
  })

  it('places programs by start and stop and cuts them at the window edges', async () => {
    render(<TimelineGridPage fetchPage={async () => ({ generation: 'g', total: 1, items: [channel(5, { programmes: [early, late] })] })} now={now} />)
    const track = await screen.findByRole('list', { name: 'Programs on 5 Test Channel 5' })
    const [first, second] = within(track).getAllByRole('listitem')
    // Early Show started at 09:30, before the window, so it is cut to 10:00-10:30: left 0, width 30 of 180 minutes.
    expect(first).toHaveStyle({ left: '0%' })
    expect(first.style.width).toMatch(/^16\.6/)
    expect(first).toHaveTextContent('Early Show')
    expect(first).toHaveTextContent('09:30–10:30 UTC')
    // Late Show runs 12:00-14:00 and is cut at 13:00: starts 2/3 across, one third wide.
    expect(second.style.left).toMatch(/^66\.6/)
    expect(second.style.width).toMatch(/^33\.3/)
  })

  it('offers the same programs as an ordered list with full times, and says when a channel has none', async () => {
    const user = userEvent.setup()
    render(<TimelineGridPage fetchPage={async () => ({ generation: 'g', total: 2, items: [channel(5, { programmes: [early, late] }), channel(6)] })} now={now} />)
    const list = await screen.findByRole('button', { name: 'List' })
    await user.click(list)
    expect(list).toHaveAttribute('aria-pressed', 'true')
    const section = screen.getByRole('region', { name: '5 Test Channel 5' })
    const items = within(section).getAllByRole('listitem')
    expect(items.map((item) => item.textContent)).toEqual(['09:30–10:30 UTC Early Show', '12:00–14:00 UTC Late Show'])
    expect(within(screen.getByRole('region', { name: '6 Test Channel 6' })).getByText('No programs in this window')).toBeVisible()
  })

  it('shows plain words with Details when loading fails, and tries again', async () => {
    const user = userEvent.setup()
    const fetchPage = vi.fn<LineupWindowFetcher>().mockResolvedValueOnce(null).mockResolvedValue({ generation: 'g', total: 1, items: [channel(5)] })
    render(<TimelineGridPage fetchPage={fetchPage} now={now} />)
    expect(await screen.findByText('ChannelForge could not load the timeline')).toBeVisible()
    expect(screen.queryByText('timeline-load-failed')).toBeNull()
    await user.click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('timeline-load-failed')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Showing 1 of 1 channels')).toBeVisible()
  })

  it('keeps the same window and generation for more channels, and starts over if the lineup changed', async () => {
    const user = userEvent.setup()
    const fetchPage = vi.fn<LineupWindowFetcher>()
      .mockResolvedValueOnce({ generation: 'g1', total: 2, items: [channel(1)] })
      .mockResolvedValueOnce('changed')
      .mockResolvedValueOnce({ generation: 'g2', total: 1, items: [channel(9)] })
    render(<TimelineGridPage fetchPage={fetchPage} now={now} />)
    await user.click(await screen.findByRole('button', { name: 'Show more channels' }))
    expect(fetchPage).toHaveBeenNthCalledWith(2, 1, 'g1', { from: '2026-06-01T10:00:00Z', to: '2026-06-01T13:00:00Z' })
    expect(await screen.findByText('Showing 1 of 1 channels')).toBeVisible()
    expect(screen.getByText('9 Test Channel 9')).toBeVisible()
    expect(screen.queryByText('1 Test Channel 1')).toBeNull()
  })
})

describe('fetchLineupPage with a window', () => {
  const window = { from: '2026-06-01T10:00:00Z', to: '2026-06-01T13:00:00Z' }
  const body = (items: unknown[]) => new Response(JSON.stringify({ generation: 'g', total: items.length, items }))

  it('sends the window and reads programs; the default request has no window', async () => {
    const request = vi.fn(async () => body([{ id: 'a', name: 'A', number: 1, logoStatus: 'present', guideState: 'bound', attention: [], programmes: [early] }]))
    const page = await fetchLineupPage(0, null, request as unknown as typeof fetch, window)
    expect(request).toHaveBeenCalledWith('/api/lineup/channels?limit=100&from=2026-06-01T10%3A00%3A00Z&to=2026-06-01T13%3A00%3A00Z', expect.anything())
    expect(page).toMatchObject({ items: [{ programmes: [early] }] })
    const plain = vi.fn(async () => body([]))
    await fetchLineupPage(0, null, plain as unknown as typeof fetch)
    expect(plain).toHaveBeenCalledWith('/api/lineup/channels?limit=100', expect.anything())
  })

  it('fails instead of hiding a program it cannot read', async () => {
    const request = async () => body([{ id: 'a', name: 'A', programmes: [{ title: 'No times' }] }])
    expect(await fetchLineupPage(0, null, request as unknown as typeof fetch, window)).toEqual({ loadFailure: 'not-understood' })
  })

  it('tells apart a server that is not running, a server error and a value it does not know', async () => {
    const down = async () => { throw new TypeError('Failed to fetch') }
    expect(await fetchLineupPage(0, null, down as unknown as typeof fetch)).toEqual({ loadFailure: 'unreachable' })
    const broken = async () => new Response('', { status: 500 })
    expect(await fetchLineupPage(0, null, broken as unknown as typeof fetch)).toEqual({ loadFailure: 'server-error' })
    const newer = async () => body([{ id: 'a', name: 'A', number: 1, logoStatus: 'blurry', guideState: 'bound', attention: [] }])
    expect(await fetchLineupPage(0, null, newer as unknown as typeof fetch)).toEqual({ loadFailure: 'not-understood' })
  })
})

describe('Timeline load failure order', () => {
  it('shows the notice before the Try again button', async () => {
    render(<TimelineGridPage fetchPage={async () => null} now={now} />)
    const notice = await screen.findByRole('alert')
    const retry = screen.getByRole('button', { name: 'Try again' })
    expect(notice.compareDocumentPosition(retry) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })
})
