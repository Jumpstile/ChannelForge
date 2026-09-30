import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'
import type { OneGuideItem } from '../../app/oneGuide'

function item(index: number): OneGuideItem {
  return {
    ItemId: index.toString(16).padStart(64, '0'),
    Kind: 'Programme',
    Title: index === 0 ? 'Evening News' : `Local programme ${index}`,
    Subtitle: index === 0 ? 'Local edition' : null,
    Description: index === 0 ? 'Top stories from the region.' : null,
    StartUtc: '2026-09-30T10:00:00Z',
    StopUtc: '2026-09-30T11:00:00Z',
    Status: 'Live',
    CategoryKeys: ['live-now', 'news'],
    Offerings: [{ SourceLabel: 'Accepted guide', Availability: 'GuideOnly', Launch: { Kind: 'Channel', ChannelReference: `cf-${'a'.repeat(64)}` } }],
    OfferingCount: 1,
    OfferingsTruncated: false,
  }
}

function response(query: 'LiveNow' | 'Details', offset: number, items: OneGuideItem[], totalCount: number) {
  return {
    Version: 'one-guide/v1',
    EvaluationTimeUtc: '2026-09-30T10:30:00Z',
    Query: query,
    Offset: offset,
    MaximumItems: 100,
    TotalCount: totalCount,
    ItemsTruncated: false,
    Items: items,
  }
}

test('renders the paged Live Now view, supports keyboard details, and stays read-only', async ({ page }) => {
  const apiRequests: string[] = []
  await page.route('**/api/**', async (route) => {
    const request = route.request()
    const url = new URL(request.url())
    apiRequests.push(`${request.method()} ${url.pathname}${url.search}`)
    expect(request.method()).toBe('GET')

    if (url.pathname === '/api/status') {
      await route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify({ Service: 'ChannelForge', Status: 'ok', Message: 'ChannelForge is running', ReadOnly: true, LineupStatus: 'not-accepted' }),
      })
      return
    }

    if (url.pathname === '/api/one-guide/live-now') {
      const offset = Number(url.searchParams.get('offset'))
      expect(url.searchParams.get('limit')).toBe('100')
      const items = Array.from({ length: 101 }, (_, index) => item(index))
      const pageItems = items.slice(offset, offset + 100)
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify(response('LiveNow', offset, pageItems, items.length)) })
      return
    }

    const match = /^\/api\/one-guide\/items\/([a-f0-9]{64})$/.exec(url.pathname)
    expect(match).not.toBeNull()
    await route.fulfill({ contentType: 'application/json', body: JSON.stringify(response('Details', 0, [item(0)], 1)) })
  })

  await page.goto('/')
  await page.evaluate(() => performance.mark('live-now-navigation-start'))
  await page.getByRole('button', { name: 'Live Now' }).click()
  const firstCard = page.getByRole('button', { name: /Evening News/ })
  await expect(firstCard).toBeVisible()
  await expect(firstCard).toContainText('10:00–11:00 UTC')
  await page.evaluate(() => performance.mark('live-now-first-visible'))
  await expect(page.getByRole('listitem')).toHaveCount(101)
  await page.evaluate(() => performance.mark('live-now-render-complete'))
  const timings = await page.evaluate(() => ({
    firstVisibleMs: performance.measure('live-now-first-visible', 'live-now-navigation-start', 'live-now-first-visible').duration,
    completeRenderMs: performance.measure('live-now-render', 'live-now-navigation-start', 'live-now-render-complete').duration,
    apiDurationsMs: performance.getEntriesByType('resource')
      .filter((entry) => entry.name.includes('/api/one-guide/'))
      .map((entry) => entry.duration),
  }))
  console.log(`Live Now fixture timing: 101 programmes, ${timings.apiDurationsMs.length} bounded API reads, first visible ${timings.firstVisibleMs.toFixed(1)} ms, complete render ${timings.completeRenderMs.toFixed(1)} ms, API durations ${timings.apiDurationsMs.map((duration) => duration.toFixed(1)).join(', ')} ms`)

  expect(await page.locator('body').innerText()).not.toContain('0'.repeat(64))
  expect(await page.locator('body').innerText()).not.toContain('cf-')
  const listA11y = await new AxeBuilder({ page }).analyze()
  expect(listA11y.violations).toEqual([])

  await firstCard.focus()
  await page.keyboard.press('ArrowDown')
  await expect(page.getByRole('listitem').nth(2).getByRole('button')).toBeFocused()
  await page.keyboard.press('ArrowUp')
  await expect(firstCard).toBeFocused()
  await page.keyboard.press('Enter')
  const detail = page.getByRole('dialog', { name: 'Evening News' })
  await expect(detail).toBeVisible()
  await expect(detail).toContainText('Top stories from the region.')
  await expect(detail).toContainText('Playback is not available')
  expect(await detail.innerText()).not.toContain('0'.repeat(64))
  const detailA11y = await new AxeBuilder({ page }).analyze()
  expect(detailA11y.violations).toEqual([])
  await page.keyboard.press('Escape')
  await expect(firstCard).toBeFocused()
  const expectedGuideReads = [
    'GET /api/one-guide/live-now?limit=100&offset=0',
    'GET /api/one-guide/live-now?limit=100&offset=100',
    `GET /api/one-guide/items/${item(0).ItemId}`,
  ]
  expect(new Set(apiRequests.filter((request) => request !== 'GET /api/status'))).toEqual(new Set(expectedGuideReads))
  expect(apiRequests.every((request) => request === 'GET /api/status' || expectedGuideReads.includes(request))).toBe(true)
  expect(new Set(apiRequests.filter((request) => request === 'GET /api/status'))).toEqual(new Set(['GET /api/status']))
})
