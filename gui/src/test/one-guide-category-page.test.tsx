import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { OneGuideCategoryPage } from '../pages/OneGuideCategoryPage'
import type { OneGuideFetcher, OneGuideItem } from '../app/oneGuide'

function item(id: string, title: string, status: OneGuideItem['Status'], start: string, stop: string): OneGuideItem {
  return {
    ItemId: id.repeat(64), Kind: 'Programme', Title: title, Subtitle: null, Description: 'Fixture details', EpisodeNumber: null,
    StartUtc: start, StopUtc: stop, Status: status,
    CategoryKeys: status === 'Live' ? ['live-now', 'wrestling'] : status === 'StartingSoon' ? ['starting-soon', 'wrestling'] : ['wrestling'],
    Sport: 'Wrestling', League: 'WWE', HomeParticipant: null, AwayParticipant: null,
    Promotion: { Id: 'cf-' + 'd'.repeat(64), Name: 'WWE' },
    Offerings: [{
      OfferingId: 'b'.repeat(64), SourceId: 'cf-' + 'c'.repeat(64), SourceLabel: 'Accepted guide',
      Availability: 'GuideOnly', Entitlement: 'Unknown', Launch: { Kind: 'Channel', ChannelReference: 'cf-' + 'e'.repeat(64) },
      DvrSupported: null, TimeshiftSupported: null,
    }],
    OfferingCount: 1, OfferingsTruncated: false, FreshnessState: 'Unknown', ConfidenceState: 'Unknown', ConfidenceScore: null,
  }
}

const now = item('a', 'Wrestling Now', 'Live', '2026-10-02T10:00:00Z', '2026-10-02T11:00:00Z')
const soon = item('b', 'Wrestling Soon', 'StartingSoon', '2026-10-02T11:00:00Z', '2026-10-02T12:00:00Z')
const upcoming = item('c', 'Wrestling Later', 'Upcoming', '2026-10-02T14:00:00Z', '2026-10-02T15:00:00Z')
const past = item('f', 'Old Wrestling', 'Past', '2026-10-02T08:00:00Z', '2026-10-02T09:00:00Z')

function detailsResponse(value: OneGuideItem) {
  return new Response(JSON.stringify({
    Version: 'one-guide/v1', EvaluationTimeUtc: '2026-10-02T10:30:00Z', Query: 'Details', Offset: 0,
    MaximumItems: 100, TotalCount: 1, ItemsTruncated: false, Items: [value],
  }))
}

describe('Wrestling category page', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('uses canonical statuses for On Now, Starting Soon, and Coming Up and omits past programmes', async () => {
    const fetchItems: OneGuideFetcher = async () => [now, soon, upcoming, past]
    render(<OneGuideCategoryPage fetchItems={fetchItems} />)

    expect(await screen.findByRole('heading', { level: 1, name: 'Wrestling' })).toBeVisible()
    expect(within(screen.getByRole('list', { name: 'On Now' })).getByText('Wrestling Now')).toBeVisible()
    expect(within(screen.getByRole('list', { name: 'Starting Soon' })).getByText('Wrestling Soon')).toBeVisible()
    expect(within(screen.getByRole('list', { name: 'Coming Up' })).getByText('Wrestling Later')).toBeVisible()
    expect(screen.queryByText('Old Wrestling')).toBeNull()
    expect(screen.queryByRole('button', { name: /watch|play|launch/i })).toBeNull()
  })

  it('shows a true empty guide and a plain-language unavailable state with retry', async () => {
    const emptyFetcher: OneGuideFetcher = async () => []
    const empty = render(<OneGuideCategoryPage fetchItems={emptyFetcher} />)
    expect(await screen.findByRole('heading', { name: 'No wrestling programmes are coming up' })).toBeVisible()
    empty.unmount()

    const fetchItems = vi.fn<OneGuideFetcher>().mockResolvedValueOnce(null).mockResolvedValueOnce([now])
    render(<OneGuideCategoryPage fetchItems={fetchItems} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Wrestling is unavailable')
    await userEvent.setup().click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByRole('button', { name: /Wrestling Now/ })).toBeVisible()
    expect(fetchItems).toHaveBeenCalledTimes(2)
  })

  it('supports D-pad movement, Enter details, and Back restoring focus without a playback action', async () => {
    const user = userEvent.setup()
    const fetchItems: OneGuideFetcher = async () => [now, soon, upcoming]
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(detailsResponse(soon))
    render(<OneGuideCategoryPage fetchItems={fetchItems} />)

    const firstCard = await screen.findByRole('button', { name: /Wrestling Now/ })
    const secondCard = screen.getByRole('button', { name: /Wrestling Soon/ })
    firstCard.focus()
    await user.keyboard('{ArrowDown}')
    expect(secondCard).toHaveFocus()
    await user.keyboard('{Enter}')
    expect(await screen.findByRole('dialog', { name: 'Wrestling Soon' })).toBeVisible()
    expect(screen.getByText('Guide information only. Playback is not available here.')).toBeVisible()
    expect(screen.queryByRole('button', { name: /watch|play|launch/i })).toBeNull()

    await user.keyboard('{Escape}')
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    await waitFor(() => expect(secondCard).toHaveFocus())
  })
})
