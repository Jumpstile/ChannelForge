import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { LiveNowPage } from '../pages/LiveNowPage'
import { OneGuideCategoryPage } from '../pages/OneGuideCategoryPage'
import { TimelineGridPage } from '../pages/TimelineGridPage'
import { StatusDashboard } from '../components/StatusDashboard'
import { loadFailure } from '../app/friendlyError'
import type { OneGuideFetcher, OneGuideItem } from '../app/oneGuide'
import type { WebStatusSnapshot } from '../app/webStatus'
import type { LineupChannel, LineupWindowFetcher } from '../app/lineup'

const guideItem = {
  ItemId: 'a'.repeat(64), Kind: 'Programme', Title: 'Evening News', Subtitle: null, Description: 'Top stories', EpisodeNumber: null,
  StartUtc: '2026-10-02T10:00:00Z', StopUtc: '2026-10-02T11:00:00Z', Status: 'Live', CategoryKeys: ['live-now', 'wrestling'],
  Sport: null, League: null, HomeParticipant: null, AwayParticipant: null, Promotion: null, Offerings: [], OfferingCount: 0,
  OfferingsTruncated: false, FreshnessState: 'Unknown', ConfidenceState: 'Unknown', ConfidenceScore: null,
} as unknown as OneGuideItem

const channel = (n: number): LineupChannel =>
  ({ id: `id-${n}`, number: n, name: `Test Channel ${n}`, group: '', logoStatus: 'present', guideState: 'bound', attention: [], current: null, next: null, programmes: [] })

const server503 = loadFailure('server-error', 'HTTP status 503')

async function expectReasonAndRaw(why: RegExp, raw: string) {
  const alert = await screen.findByRole('alert')
  expect(alert).toHaveTextContent(why)
  expect(alert).not.toHaveTextContent(raw)
  await userEvent.setup().click(screen.getByRole('button', { name: 'Details' }))
  expect(screen.getByText(raw)).toBeVisible()
}

beforeEach(() => vi.restoreAllMocks())

describe.each([
  ['Live Now', (fetchItems: OneGuideFetcher) => <LiveNowPage fetchItems={fetchItems} />],
  ['Wrestling', (fetchItems: OneGuideFetcher) => <OneGuideCategoryPage fetchItems={fetchItems} />],
])('%s failure reasons', (_name, renderPage) => {
  it('shows the plain reason up front and the raw error under Details', async () => {
    render(renderPage(async () => server503))
    await expectReasonAndRaw(/server reported an error/, 'HTTP status 503')
  })

  it('falls back to the plain generic text when no reason is known', async () => {
    render(renderPage(async () => null))
    expect(await screen.findByRole('alert')).toHaveTextContent('could not tell why')
  })

  it('shows the reason when the program details cannot load', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('', { status: 503 }))
    render(renderPage(async () => [guideItem]))
    await userEvent.setup().click(await screen.findByRole('button', { name: /Evening News/ }))
    await expectReasonAndRaw(/server reported an error/, 'HTTP status 503')
  })
})

describe('Timeline failure reasons', () => {
  it('shows the reason when more channels cannot load', async () => {
    const fetchPage = vi.fn<LineupWindowFetcher>()
      .mockResolvedValueOnce({ generation: 'g', total: 2, items: [channel(1)] })
      .mockResolvedValueOnce(server503)
    render(<TimelineGridPage fetchPage={fetchPage} now={() => new Date('2026-06-01T10:00:30Z')} />)
    await userEvent.setup().click(await screen.findByRole('button', { name: 'Show more channels' }))
    await expectReasonAndRaw(/server reported an error/, 'HTTP status 503')
  })
})

describe('Status failure reasons', () => {
  it('shows the reason when the status cannot load and keeps a thrown error under Details', async () => {
    const first = render(<StatusDashboard fetchStatus={async () => server503} />)
    await expectReasonAndRaw(/server reported an error/, 'HTTP status 503')
    first.unmount()
    render(<StatusDashboard fetchStatus={() => Promise.reject(new Error('socket closed'))} />)
    const alertText = await screen.findByRole('alert')
    expect(alertText).not.toHaveTextContent('could not tell why')
    await expectReasonAndRaw(/request failed before ChannelForge got a usable answer/, 'socket closed')
  })

  it('shows the reason when Refresh fails and falls back when there is none', async () => {
    const status: WebStatusSnapshot = { lineupAccepted: true, sourcesStatus: 'saved', playlistStatus: 'ready', guideStatus: 'no-guide', canRefreshSources: true }
    const user = userEvent.setup()
    const refresh = vi.fn().mockResolvedValueOnce(server503).mockResolvedValueOnce(null)
    render(<StatusDashboard fetchStatus={async () => status} refreshSources={refresh} />)
    await user.click(await screen.findByRole('button', { name: /Refresh now/ }))
    await expectReasonAndRaw(/server reported an error/, 'HTTP status 503')
    await user.click(screen.getByRole('button', { name: /Refresh now/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('could not tell why')
  })

  it('drops "could not tell why" when Refresh failed with raw text only', async () => {
    const status: WebStatusSnapshot = { lineupAccepted: true, sourcesStatus: 'saved', playlistStatus: 'ready', guideStatus: 'no-guide', canRefreshSources: true }
    render(<StatusDashboard fetchStatus={async () => status} refreshSources={vi.fn().mockResolvedValue(loadFailure('unknown', 'boom'))} />)
    await userEvent.setup().click(await screen.findByRole('button', { name: /Refresh now/ }))
    const alert = await screen.findByRole('alert')
    expect(alert).not.toHaveTextContent('could not tell why')
    await expectReasonAndRaw(/refresh request failed before ChannelForge got a usable answer/, 'boom')
  })
})
