import validateOneGuideProjection from './oneGuideProjectionValidator.generated.js'

import type { OneGuideCategory, OneGuideItem, OneGuidePage } from './oneGuideProjection.generated'

export type { OneGuideCategory, OneGuideItem, OneGuideOffering, OneGuidePage } from './oneGuideProjection.generated'

export type OneGuideFetcher = () => Promise<OneGuideItem[] | null>


function parsePage(value: unknown): OneGuidePage | null {
  return validateOneGuideProjection(value) ? value : null
}

const generationPattern = /^[a-f0-9]{64}$/

// Every page after the first pins the initial evaluation time and accepted generation;
// a changed generation restarts the listing so all sections share one guide snapshot.
async function fetchOneGuideList(
  path: string,
  query: 'LiveNow' | 'Category',
  request: typeof fetch,
  categoryKey?: OneGuideCategory,
  currentAndUpcomingOnly = false,
): Promise<OneGuideItem[] | null> {
  try {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const items: OneGuideItem[] = []
      let snapshot: { totalCount: number; evaluationTimeUtc: string; generation: string } | undefined
      let generationChanged = false
      for (let offset = 0; snapshot === undefined || offset < snapshot.totalCount; offset += 100) {
        const pin = snapshot === undefined ? '' : `&at=${Date.parse(snapshot.evaluationTimeUtc)}&generation=${snapshot.generation}`
        const windowQuery = currentAndUpcomingOnly ? '&window=active' : ''
        const response = await request(`${path}?limit=100&offset=${offset}${pin}${windowQuery}`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
        })
        if (response.status === 409 && snapshot !== undefined) {
          generationChanged = true
          break
        }
        if (response.status !== 200) return null
        const generation = response.headers.get('X-ChannelForge-Generation') ?? ''
        const page = parsePage(await response.json())
        if (page === null || page.Query !== query || page.Offset !== offset || page.MaximumItems !== 100 ||
            page.Items.length > 100 || !Number.isSafeInteger(page.TotalCount) ||
            !Number.isSafeInteger(offset + page.Items.length) || !generationPattern.test(generation) ||
            !Number.isSafeInteger(Date.parse(page.EvaluationTimeUtc)) ||
            page.ItemsTruncated !== (offset + page.Items.length < page.TotalCount) ||
            (query === 'Category' ? page.CategoryKey !== categoryKey : page.CategoryKey !== undefined)) return null
        if (snapshot === undefined) {
          snapshot = { totalCount: page.TotalCount, evaluationTimeUtc: page.EvaluationTimeUtc, generation }
        } else if (page.TotalCount !== snapshot.totalCount || generation !== snapshot.generation ||
            Date.parse(page.EvaluationTimeUtc) !== Date.parse(snapshot.evaluationTimeUtc)) {
          return null
        }
        items.push(...page.Items)
        if (items.length > snapshot.totalCount) return null
        if (page.Items.length === 0 && offset < snapshot.totalCount) return null
      }
      if (generationChanged) continue
      return snapshot !== undefined && items.length === snapshot.totalCount ? items : null
    }
    return null
  } catch {
    return null
  }
}

export function fetchLiveNow(request: typeof fetch = fetch): Promise<OneGuideItem[] | null> {
  return fetchOneGuideList('/api/one-guide/live-now', 'LiveNow', request)
}

export function fetchOneGuideCategory(categoryKey: OneGuideCategory, request: typeof fetch = fetch): Promise<OneGuideItem[] | null> {
  return fetchOneGuideList(`/api/one-guide/category/${categoryKey}`, 'Category', request, categoryKey, true)
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
