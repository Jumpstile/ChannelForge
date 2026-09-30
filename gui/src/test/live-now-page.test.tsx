import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { LiveNowPage } from '../pages/LiveNowPage'
import type { OneGuideFetcher, OneGuideItem } from '../app/oneGuide'

const first: OneGuideItem = {
  ItemId: 'a'.repeat(64), Kind: 'Programme', Title: 'Evening News', Subtitle: 'Local edition', Description: 'Top stories',
  StartUtc: '2026-09-30T10:00:00Z', StopUtc: '2026-09-30T11:00:00Z', Status: 'Live', CategoryKeys: ['live-now', 'news'],
  Offerings: [{ SourceLabel: 'Accepted guide', Availability: 'GuideOnly', Launch: { Kind: 'Channel', ChannelReference: 'cf-' + 'b'.repeat(64) } }],
  OfferingCount: 1, OfferingsTruncated: false,
}
const second = { ...first, ItemId: 'c'.repeat(64), Title: 'Afternoon Film', CategoryKeys: ['live-now', 'movies'] }

function detailsResponse(item: OneGuideItem) {
  return new Response(JSON.stringify({ Version: 'one-guide/v1', EvaluationTimeUtc: '2026-09-30T10:30:00Z', Query: 'Details', Offset: 0, MaximumItems: 100, TotalCount: 1, ItemsTruncated: false, Items: [item] }))
}

describe('Live Now page', () => {
  beforeEach(() => vi.restoreAllMocks())

  it('shows a useful loading, populated, and real empty state', async () => {
    const { promise, resolve } = Promise.withResolvers<OneGuideItem[]>()
    const loadingFetcher: OneGuideFetcher = () => promise
    const loading = render(<LiveNowPage fetchItems={loadingFetcher} />)
    expect(screen.getByRole('status')).toHaveTextContent('Loading Live Now')
    resolve([first])
    expect(await screen.findByRole('button', { name: /Evening News/ })).toBeVisible()
    expect(screen.getByText('Accepted guide · news')).toBeVisible()
    loading.unmount()

    render(<LiveNowPage fetchItems={async () => []} />)
    expect(await screen.findByText('Nothing is on right now')).toBeVisible()
  })

  it('supports arrow navigation, Enter details, Escape, and opener focus restoration', async () => {
    const user = userEvent.setup()
    const fetchItems: OneGuideFetcher = async () => [first, second]
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(detailsResponse(first))
    render(<LiveNowPage fetchItems={fetchItems} />)

    const firstCard = await screen.findByRole('button', { name: /Evening News/ })
    const secondCard = await screen.findByRole('button', { name: /Afternoon Film/ })
    firstCard.focus()
    await user.keyboard('{ArrowRight}')
    expect(secondCard).toHaveFocus()
    await user.keyboard('{ArrowLeft}{Enter}')

    const dialog = await screen.findByRole('dialog', { name: 'Evening News' })
    expect(dialog).toHaveTextContent('Top stories')
    expect(dialog).toHaveTextContent('Playback is not available')
    expect(dialog.textContent).not.toContain(first.ItemId)
    await user.keyboard('{Escape}')
    await waitFor(() => expect(firstCard).toHaveFocus())
  })

  it('shows retry on API failure and recovers when the accepted guide becomes available', async () => {
    const user = userEvent.setup()
    const fetchItems = vi.fn<OneGuideFetcher>().mockResolvedValueOnce(null).mockResolvedValueOnce([first])
    render(<LiveNowPage fetchItems={fetchItems} />)

    expect(await screen.findByRole('alert')).toHaveTextContent('Live Now is unavailable')
    await user.click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByRole('button', { name: /Evening News/ })).toBeVisible()
    expect(fetchItems).toHaveBeenCalledTimes(2)
  })
})
