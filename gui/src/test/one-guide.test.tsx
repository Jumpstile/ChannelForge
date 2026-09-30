import { describe, expect, it, vi } from 'vitest'
import { fetchLiveNow, fetchLiveNowItem } from '../app/oneGuide'
import type { OneGuideItem } from '../app/oneGuide'

function item(id: string, itemId = id.repeat(64)): OneGuideItem {
  return {
    ItemId: itemId, Kind: 'Programme', Title: `Programme ${id}`, Subtitle: null, Description: null,
    StartUtc: '2026-09-30T10:00:00Z', StopUtc: '2026-09-30T11:00:00Z', Status: 'Live', CategoryKeys: ['live-now'],
    Offerings: [{ SourceLabel: 'Accepted guide', Availability: 'GuideOnly', Launch: { Kind: 'Channel', ChannelReference: 'cf-' + 'd'.repeat(64) } }],
    OfferingCount: 1, OfferingsTruncated: false,
  }
}

function page(items: OneGuideItem[], offset: number, totalCount: number, query: 'LiveNow' | 'Details' = 'LiveNow') {
  return { Version: 'one-guide/v1', EvaluationTimeUtc: '2026-09-30T10:30:00Z', Query: query, Offset: offset, MaximumItems: 100, TotalCount: totalCount, ItemsTruncated: false, Items: items }
}

describe('Live Now API client', () => {
  it('follows bounded offsets until every API page is loaded', async () => {
    const firstPage = Array.from({ length: 100 }, (_, index) => item(String(index + 1), (index + 1).toString(16).padStart(64, '0')))
    const request = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify(page(firstPage, 0, 101))))
      .mockResolvedValueOnce(new Response(JSON.stringify(page([item('b')], 100, 101))))

    const result = await fetchLiveNow(request)

    expect(result).toHaveLength(101)
    expect(result?.[0].Title).toBe('Programme 1')
    expect(result?.[100].Title).toBe('Programme b')
    expect(request.mock.calls.map(([url]) => url)).toEqual([
      '/api/one-guide/live-now?limit=100&offset=0',
      '/api/one-guide/live-now?limit=100&offset=100',
    ])
  })

  it('fails closed when a page sequence is inconsistent or the API is unavailable', async () => {
    const firstPage = Array.from({ length: 100 }, (_, index) => item(String(index + 1), (index + 1).toString(16).padStart(64, '0')))
    const changedCount = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify(page(firstPage, 0, 101))))
      .mockResolvedValueOnce(new Response(JSON.stringify(page([item('b')], 100, 102))))
    const unavailable = vi.fn().mockResolvedValue(new Response('{}', { status: 503 }))

    await expect(fetchLiveNow(changedCount)).resolves.toBeNull()
    await expect(fetchLiveNow(unavailable)).resolves.toBeNull()
  })
  it('rejects a page sequence that does not cover the advertised result count', async () => {
    const firstPage = Array.from({ length: 99 }, (_, index) => item(String(index + 1), (index + 1).toString(16).padStart(64, '0')))
    const request = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify(page(firstPage, 0, 101))))
      .mockResolvedValueOnce(new Response(JSON.stringify(page([item('b')], 100, 101))))

    await expect(fetchLiveNow(request)).resolves.toBeNull()
    expect(request).toHaveBeenCalledTimes(2)
  })


  it('rejects a valid-version response for a different query', async () => {
    const wrongQuery = vi.fn().mockResolvedValue(new Response(JSON.stringify(page([item('a')], 0, 1, 'Details'))))

    await expect(fetchLiveNow(wrongQuery)).resolves.toBeNull()
    expect(wrongQuery).toHaveBeenCalledTimes(1)
  })


  it('requests the bounded details route and rejects unsafe identifiers', async () => {
    const id = 'a'.repeat(64)
    const request = vi.fn().mockResolvedValue(new Response(JSON.stringify(page([item('a')], 0, 1, 'Details'))))

    await expect(fetchLiveNowItem(id, request)).resolves.toMatchObject({ Title: 'Programme a' })
    expect(request).toHaveBeenCalledWith(`/api/one-guide/items/${id}`, expect.objectContaining({ method: 'GET' }))
    expect(await fetchLiveNowItem('../private', request)).toBeNull()
    expect(request).toHaveBeenCalledTimes(1)
  })
})
