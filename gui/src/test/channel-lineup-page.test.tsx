import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import App from '../App'
import { loadFailure } from '../app/friendlyError'
import { ChannelLineupPage } from '../pages/ChannelLineupPage'
import { fetchLineupPage } from '../app/lineup'
import type { LineupChannel, LineupFetcher, LineupResult } from '../app/lineup'
import css from '../styles/global.css?raw'

const channel = (n: number, over: Partial<LineupChannel> = {}): LineupChannel =>
  ({ id: `id-${n}`, number: n, name: `Test Channel ${n}`, group: 'Test Group', logoStatus: 'present', guideState: 'bound', attention: [], current: null, next: null, ...over })

describe('Channel lineup page', () => {
  it('explains a missing logo and missing guide and points to Guided Setup', async () => {
    const user = userEvent.setup()
    const onOpenSetup = vi.fn()
    const bad = channel(3, { logoStatus: 'missing', guideState: 'none', attention: ['no-guide', 'no-logo'] })
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 1, items: [bad] })} onOpenSetup={onOpenSetup} />)
    const row = await screen.findByRole('listitem')
    expect(row).toHaveTextContent('Logo missing')
    expect(row).toHaveTextContent('No program guide linked')
    await user.click(screen.getByRole('button', { name: 'Fix in Guided Setup' }))
    expect(onOpenSetup).toHaveBeenCalledOnce()
  })

  it('shows no warnings for a healthy channel', async () => {
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 1, items: [channel(1)] })} onOpenSetup={() => {}} />)
    const row = await screen.findByRole('listitem')
    expect(row).not.toHaveTextContent('Logo missing')
    expect(row).not.toHaveTextContent('No program guide linked')
    expect(screen.queryByRole('button', { name: 'Fix in Guided Setup' })).not.toBeInTheDocument()
  })

  it('shows a pinned logo in plain words and does not treat it as a problem', async () => {
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 1, items: [channel(2, { logoStatus: 'pinned' })] })} onOpenSetup={() => {}} />)
    const row = await screen.findByRole('listitem')
    expect(row).toHaveTextContent('Logo pinned (will not be replaced)')
    expect(screen.getByText('Details')).toBeInTheDocument()
    expect(row).not.toHaveTextContent('Logo missing')
    expect(screen.queryByRole('button', { name: 'Fix in Guided Setup' })).not.toBeInTheDocument()
  })

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
    expect(await screen.findByRole('alert')).toHaveTextContent('ChannelForge could not load your saved lineup')
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Test Channel 1')).toBeVisible()
  })

  it.each([
    [loadFailure('not-understood'), 'does not understand', 'update ChannelForge'],
    [loadFailure('unreachable'), 'most likely not running', 'Start ChannelForge'],
    ['changed' as const, 'saved lineup changed while ChannelForge was loading it', 'Try again'],
  ])('says why the saved lineup could not load (%j)', async (result, why, next) => {
    render(<ChannelLineupPage fetchPage={async () => result} onOpenSetup={() => {}} />)
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(why)
    expect(alert).toHaveTextContent(next)
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
    await user.tab()
    await user.tab()
    expect(screen.getByRole('button', { name: 'Show more channels' })).toHaveFocus()
    await user.keyboard('{Enter}')
    expect(await screen.findByText('Test Channel 2')).toBeVisible()
    expect(fetchPage).toHaveBeenLastCalledWith(1, 'g')
    expect(screen.queryByRole('button', { name: 'Show more channels' })).not.toBeInTheDocument()
  })

  describe('search and group picker', () => {
    const named = (n: number, name: string, group: string) => channel(n, { name, group })
    const page = (items: LineupChannel[], total = items.length): LineupFetcher => async () => ({ generation: 'g', total, items })
    const lineup = [named(1, 'Sports One', 'Sports'), named(2, 'Sports Two', 'Sports'), named(3, 'Movie Night', 'Movies')]

    it('finds channels by name, ignoring case and extra spaces', async () => {
      const user = userEvent.setup()
      render(<ChannelLineupPage fetchPage={page(lineup)} onOpenSetup={() => {}} />)
      await screen.findByText('Movie Night')
      await user.type(screen.getByRole('searchbox', { name: 'Search by channel name' }), '  SPORTS   two ')
      expect(screen.getByText('Sports Two')).toBeVisible()
      expect(screen.queryByText('Sports One')).not.toBeInTheDocument()
      expect(screen.queryByText('Movie Night')).not.toBeInTheDocument()
    })

    it('says nothing matches and clears the search', async () => {
      const user = userEvent.setup()
      render(<ChannelLineupPage fetchPage={page(lineup)} onOpenSetup={() => {}} />)
      await screen.findByText('Movie Night')
      await user.type(screen.getByRole('searchbox'), 'zzz')
      expect(screen.getByText('No channels match')).toBeVisible()
      await user.click(screen.getByRole('button', { name: 'Clear search and group' }))
      expect(screen.getByText('Movie Night')).toBeVisible()
      expect(screen.getByText('Sports One')).toBeVisible()
    })

    it('shows one group from the picker, with counts, using the keyboard', async () => {
      const user = userEvent.setup()
      render(<ChannelLineupPage fetchPage={page(lineup)} onOpenSetup={() => {}} />)
      await screen.findByText('Movie Night')
      expect(screen.getByRole('option', { name: 'Sports (2)' })).toBeInTheDocument()
      await user.tab()
      await user.tab()
      expect(screen.getByRole('combobox', { name: 'Group' })).toHaveFocus()
      await user.selectOptions(screen.getByRole('combobox', { name: 'Group' }), 'Movies')
      expect(screen.getByText('Movie Night')).toBeVisible()
      expect(screen.queryByText('Sports One')).not.toBeInTheDocument()
      await user.selectOptions(screen.getByRole('combobox', { name: 'Group' }), '')
      expect(screen.getByText('Sports One')).toBeVisible()
    })

    it('says when not all channels are loaded and offers Show more channels', async () => {
      const user = userEvent.setup()
      render(<ChannelLineupPage fetchPage={page(lineup, 5)} onOpenSetup={() => {}} />)
      await screen.findByText('Movie Night')
      expect(screen.queryByText(/Not all channels are loaded yet/)).not.toBeInTheDocument()
      await user.type(screen.getByRole('searchbox'), 'night')
      expect(screen.getByText(/Not all channels are loaded yet \(3 of 5\)/)).toBeVisible()
      expect(screen.getByRole('button', { name: 'Show more channels' })).toBeEnabled()
    })
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

describe('Channel lineup page description', () => {
  it('explains what a Group is', () => {
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 0, items: [] })} onOpenSetup={() => {}} />)
    expect(screen.getByText(/Group is the heading it is filed under in the playlist/)).toBeVisible()
  })
})

describe('Channel lineup page saved date and failure order', () => {
  const page = (savedAtUtc?: unknown) => async () => ({ generation: 'g', total: 1, items: [channel(1)], savedAtUtc } as LineupResult)

  it('says when the lineup was saved', async () => {
    render(<ChannelLineupPage fetchPage={page('2026-11-24T15:00:00Z')} onOpenSetup={() => {}} />)
    await screen.findByText('Test Channel 1')
    expect(document.body).toHaveTextContent(/Saved on November 2[345], 2026\./)
  })

  it.each([[null], [undefined], ['not a date']])('shows no date when the saved time is %j', async (value) => {
    render(<ChannelLineupPage fetchPage={page(value)} onOpenSetup={() => {}} />)
    await screen.findByText('Test Channel 1')
    expect(document.body).not.toHaveTextContent('Saved on')
  })

  it.each([[42, null], ['2026-11-24T15:00:00Z', '2026-11-24T15:00:00Z'], [undefined, null]])('reads the saved time %j as %j and still loads', async (sent, read) => {
    const body = { generation: 'g', total: 1, items: [], savedAtUtc: sent }
    const result = await fetchLineupPage(0, null, async () => new Response(JSON.stringify(body)))
    expect(result).toMatchObject({ total: 1, savedAtUtc: read })
  })

  it('shows the notice before the Try again button', async () => {
    render(<ChannelLineupPage fetchPage={async () => null} onOpenSetup={() => {}} />)
    const notice = await screen.findByRole('alert')
    const retry = screen.getByRole('button', { name: 'Try again' })
    expect(notice.compareDocumentPosition(retry) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })
})

describe('Saved match reason', () => {
  const evidence = (reasonCode: string, over: Partial<NonNullable<LineupChannel['matchEvidence']>> = {}) => ({ reasonCode, status: 'ExactBound', guideId: 'espn.us', guideSourceId: 'main-guide', ...over })
  const show = (items: LineupChannel[]) => render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: items.length, items })} onOpenSetup={() => {}} />)

  it.each([
    ['ExactOrdinalMatch', "Guide: Matched. This channel's guide ID was found exactly once in your guide file, so its programs are shown."],
    ['MissingM3UId', 'Guide: No guide found. The playlist gave this channel no guide ID, so it has no program list.'],
    ['NoXMLTVMatch', "Guide: No guide found. This channel's guide ID is not in your guide file, so it has no program list."],
    ['AmbiguousXMLTVCandidates', 'Guide: Needs a choice. More than one guide channel looked right, so ChannelForge did not guess.'],
    ['DuplicateXMLTVId', 'Guide: Needs a choice. More than one guide channel looked right, so ChannelForge did not guess.'],
    ['M3UIdentityCollision', 'Guide: Needs a choice. More than one guide channel looked right, so ChannelForge did not guess.'],
    ['ConflictingIdentity', 'Guide: Needs a choice. More than one guide channel looked right, so ChannelForge did not guess.'],
    ['SomethingNewLater', 'No explanation saved for this channel.'],
    ['toString', 'No explanation saved for this channel.'],
  ])('says %s in plain words', async (code, sentence) => {
    show([channel(1, { matchEvidence: evidence(code) })])
    const row = await screen.findByRole('listitem')
    expect(row).toHaveTextContent(sentence)
    expect(screen.queryByText(/Match details are not available/)).not.toBeInTheDocument()
  })

  it('shows one calm page note, not one per channel, when no channel has match details', async () => {
    show([channel(1), channel(2)])
    await screen.findByText('Test Channel 1')
    expect(screen.getAllByText('Match details are not available for this lineup. Your lineup and guide are not affected.')).toHaveLength(1)
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(document.body).not.toHaveTextContent('Guide: ')
  })

  it('keeps the technical values in a Details fold and shows provider text as plain text, cut when long', async () => {
    const longId = `<b>tricky</b>${'x'.repeat(300)}`
    show([channel(1, { matchEvidence: evidence('ExactOrdinalMatch', { guideId: longId, guideSourceId: 'Main guide' }) })])
    const row = await screen.findByRole('listitem')
    expect(row.querySelector('details > summary')).toHaveTextContent('Details')
    const details = row.querySelector('details') as HTMLElement
    expect(details).toHaveTextContent('Reason: ExactOrdinalMatch')
    expect(details).toHaveTextContent('Guide source: Main guide')
    expect(details.querySelector('b')).toBeNull()
    expect(details).toHaveTextContent(/Guide ID: <b>tricky<\/b>x+…/)
    expect(details.textContent).not.toContain('x'.repeat(100))
  })

  it('says none for a missing guide ID and source, and still explains a channel that has no saved details when others do', async () => {
    show([channel(1, { matchEvidence: evidence('MissingM3UId', { guideId: null, guideSourceId: null }) }), channel(2)])
    const rows = await screen.findAllByRole('listitem')
    expect(rows[0]).toHaveTextContent('Guide ID: none')
    expect(rows[0]).toHaveTextContent('Guide source: none')
    expect(rows[1]).toHaveTextContent('No explanation saved for this channel.')
    expect(rows[1].querySelector('details')).toBeNull()
  })

  it('reads match details from the server and never fails the page on odd ones', async () => {
    const item = (id: string, matchEvidence: unknown) => ({ id, number: 1, name: id, group: '', logoStatus: 'present', guideState: 'bound', attention: [], current: null, next: null, ...(matchEvidence === undefined ? {} : { matchEvidence }) })
    const body = {
      generation: 'g', total: 5,
      items: [
        item('a', { reasonCode: 'ExactOrdinalMatch', status: 'ExactBound', guideId: 'one', guideSourceId: 's', futureField: 1 }),
        item('b', { reasonCode: 'BrandNewCode', guideId: 7 }),
        item('c', 'text'),
        item('d', { status: 'ExactBound' }),
        item('e', undefined),
      ],
    }
    const result = await fetchLineupPage(0, null, async () => new Response(JSON.stringify(body)))
    expect(result).toMatchObject({ total: 5 })
    const items = (result as { items: LineupChannel[] }).items
    expect(items[0].matchEvidence).toEqual({ reasonCode: 'ExactOrdinalMatch', status: 'ExactBound', guideId: 'one', guideSourceId: 's' })
    expect(items[1].matchEvidence).toEqual({ reasonCode: 'BrandNewCode', status: '', guideId: null, guideSourceId: null })
    expect(items.slice(2).map((entry) => entry.matchEvidence)).toEqual([undefined, undefined, undefined])
  })
})
