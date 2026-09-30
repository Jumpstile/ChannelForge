import validateOneGuideProjection from './oneGuideProjectionValidator.generated.js'

import type { OneGuideItem, OneGuidePage } from './oneGuideProjection.generated'

export type { OneGuideCategory, OneGuideItem, OneGuideOffering, OneGuidePage } from './oneGuideProjection.generated'

export type OneGuideFetcher = () => Promise<OneGuideItem[] | null>


function parsePage(value: unknown): OneGuidePage | null {
  return validateOneGuideProjection(value) ? value : null
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
      const page = parsePage(await response.json())
      if (page === null || page.Query !== 'LiveNow' || page.Offset !== offset || page.MaximumItems !== 100 ||
          page.Items.length > 100 || !Number.isSafeInteger(page.TotalCount) ||
          !Number.isSafeInteger(offset + page.Items.length) ||
          page.ItemsTruncated !== (offset + page.Items.length < page.TotalCount)) return null
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
    const page = parsePage(await response.json())
    return page !== null && page.Query === 'Details' && page.Offset === 0 && page.MaximumItems === 100 &&
      page.TotalCount === 1 && !page.ItemsTruncated && page.Items.length === 1 &&
      page.Items[0].ItemId === itemId ? page.Items[0] : null
  } catch {
    return null
  }
}
