export type OneGuideOffering = {
  SourceLabel: string
  Availability: 'GuideOnly'
  Launch: { Kind: 'Channel'; ChannelReference: string }
}

export type OneGuideItem = {
  ItemId: string
  Kind: 'Programme' | 'Event' | 'Movie' | 'SeriesEpisode' | 'Other'
  Title: string
  Subtitle: string | null
  Description: string | null
  StartUtc: string
  StopUtc: string
  Status: 'Live' | 'StartingSoon' | 'Upcoming' | 'Past'
  CategoryKeys: string[]
  Offerings: OneGuideOffering[]
  OfferingCount: number
  OfferingsTruncated: boolean
}

type OneGuidePage = {
  Version: 'one-guide/v1'
  Query: 'LiveNow' | 'Details'
  Offset: number
  MaximumItems: number
  TotalCount: number
  ItemsTruncated: boolean
  Items: OneGuideItem[]
}

export type OneGuideFetcher = () => Promise<OneGuideItem[] | null>

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function isOneGuideItem(value: unknown): value is OneGuideItem {
  if (!isRecord(value)) return false
  return typeof value.ItemId === 'string' && /^[a-f0-9]{64}$/.test(value.ItemId) &&
    typeof value.Title === 'string' && value.Title.length > 0 &&
    typeof value.StartUtc === 'string' && Number.isFinite(Date.parse(value.StartUtc)) &&
    typeof value.StopUtc === 'string' && Number.isFinite(Date.parse(value.StopUtc)) &&
    ['Live', 'StartingSoon', 'Upcoming', 'Past'].includes(String(value.Status)) &&
    Array.isArray(value.CategoryKeys) && value.CategoryKeys.every((key) => typeof key === 'string') &&
    Array.isArray(value.Offerings) && value.Offerings.length > 0 &&
    value.Offerings.every((offering) => isRecord(offering) && typeof offering.SourceLabel === 'string')
}

function parsePage(value: unknown, expectedQuery: OneGuidePage['Query']): OneGuidePage | null {
  if (!isRecord(value) || value.Version !== 'one-guide/v1' || value.Query !== expectedQuery ||
      !Number.isInteger(value.Offset) || !Number.isInteger(value.MaximumItems) ||
      !Number.isInteger(value.TotalCount) || (value.TotalCount as number) < 0 ||
      !Array.isArray(value.Items) || !value.Items.every(isOneGuideItem)) return null
  return value as unknown as OneGuidePage
}

export async function fetchLiveNow(request: typeof fetch = fetch): Promise<OneGuideItem[] | null> {
  const items: OneGuideItem[] = []
  let totalCount: number | undefined
  try {
    for (let offset = 0; totalCount === undefined || offset < totalCount; offset += 100) {
      const response = await request(`/api/one-guide/live-now?limit=100&offset=${offset}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
      })
      if (response.status !== 200) return null
      const page = parsePage(await response.json(), 'LiveNow')
      if (page === null || page.Offset !== offset || page.MaximumItems !== 100 || page.Items.length > 100) return null
      if (totalCount !== undefined && page.TotalCount !== totalCount) return null
      totalCount = page.TotalCount
      items.push(...page.Items)
      if (items.length > totalCount) return null
      if (page.Items.length === 0 && offset < totalCount) return null
    }
    return items.length === totalCount ? items : null
  } catch {
    return null
  }
}

export async function fetchLiveNowItem(itemId: string, request: typeof fetch = fetch): Promise<OneGuideItem | null> {
  if (!/^[a-f0-9]{64}$/.test(itemId)) return null
  try {
    const response = await request(`/api/one-guide/items/${itemId}`, { method: 'GET', headers: { Accept: 'application/json' } })
    if (response.status !== 200) return null
    const page = parsePage(await response.json(), 'Details')
    return page?.Items.length === 1 && page.Items[0].ItemId === itemId ? page.Items[0] : null
  } catch {
    return null
  }
}
