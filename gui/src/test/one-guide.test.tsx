import { describe, expect, it, vi } from 'vitest'
import { fetchLiveNow, fetchLiveNowItem } from '../app/oneGuide'
import type { OneGuideItem } from '../app/oneGuide'

function item(id: string, itemId = id.repeat(64)): OneGuideItem {
  return {
    ItemId: itemId, Kind: 'Programme', Title: `Programme ${id}`, Subtitle: null, Description: null, EpisodeNumber: null,
    StartUtc: '2026-09-30T10:00:00Z', StopUtc: '2026-09-30T11:00:00Z', Status: 'Live', CategoryKeys: ['live-now'],
    Sport: null, League: null, HomeParticipant: null, AwayParticipant: null, Promotion: null,
    Offerings: [{
      OfferingId: 'e'.repeat(64), SourceId: 'cf-' + 'c'.repeat(64), SourceLabel: 'Accepted guide',
      Availability: 'GuideOnly', Entitlement: 'Unknown',
      Launch: { Kind: 'Channel', ChannelReference: 'cf-' + 'd'.repeat(64) },
      DvrSupported: null, TimeshiftSupported: null,
    }],
    OfferingCount: 1, OfferingsTruncated: false, FreshnessState: 'Unknown', ConfidenceState: 'Unknown', ConfidenceScore: null,
  }
}

function page(items: unknown[], offset: number, totalCount: number, query: 'LiveNow' | 'Details' = 'LiveNow') {
  return {
    Version: 'one-guide/v1', EvaluationTimeUtc: '2026-09-30T10:30:00Z', Query: query, Offset: offset, MaximumItems: 100,
    TotalCount: totalCount, ItemsTruncated: offset + items.length < totalCount, Items: items,
  }
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


  it('fails closed on malformed nullable, enum, count, and nested offering fields', async () => {
    const valid = item('a')
    const offering = valid.Offerings[0]
    const malformedItems: Record<string, unknown>[] = [
      { Subtitle: {} },
      { Description: [] },
      { EpisodeNumber: false },
      { Kind: 'Unknown' },
      { Status: 'Unknown' },
      { CategoryKeys: ['unregistered'] },
      { Sport: [] },
      { League: 7 },
      { HomeParticipant: {} },
      { AwayParticipant: false },
      { Promotion: { Id: 'not-an-opaque-id', Name: 'Source' } },
      { Offerings: [{ ...offering, Availability: 'Playable' }] },
      { Offerings: [{ ...offering, SourceLabel: null }] },
      { Offerings: [{ ...offering, Launch: { Kind: 'Channel', ChannelReference: {} } }] },
      { Offerings: [{ ...offering, DvrSupported: 'false' }] },
      { Offerings: [{ ...offering, TimeshiftSupported: 0 }] },
      { OfferingCount: '1' },
      { OfferingsTruncated: 'false' },
      { FreshnessState: 'Fresh' },
      { ConfidenceState: 'Certain' },
      { ConfidenceScore: 101 },
      { UnexpectedField: 'not-in-the-schema' },
    ]

    for (const malformed of malformedItems) {
      const response = vi.fn().mockResolvedValue(new Response(JSON.stringify(page([{ ...valid, ...malformed }], 0, 1))))
      await expect(fetchLiveNow(response)).resolves.toBeNull()
    }
  })

  it('fails closed on malformed page metadata and unsupported date-time values', async () => {
    const validPage = page([item('a')], 0, 1)
    const malformedPages = [
      { ...validPage, EvaluationTimeUtc: 'not-a-date' },
      { ...validPage, Offset: -1 },
      { ...validPage, MaximumItems: 101 },
      { ...validPage, TotalCount: -1 },
      { ...validPage, ItemsTruncated: true },
      { ...validPage, CategoryKey: 'unregistered' },
      { ...validPage, Items: null },
      { ...validPage, UnexpectedField: true },
    ]

    for (const malformed of malformedPages) {
      const response = vi.fn().mockResolvedValue(new Response(JSON.stringify(malformed)))
      await expect(fetchLiveNow(response)).resolves.toBeNull()
    }
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
