import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'
import type { OneGuideItem } from '../../app/oneGuide'

const generation = '7'.repeat(64)
const evaluationTimeUtc = '2026-10-02T10:30:00Z'

function item(index: number, title: string, status: OneGuideItem['Status'], start: string, stop: string): OneGuideItem {
  return {
    ItemId: (index + 1).toString(16).padStart(64, '0'), Kind: 'Programme', Title: title, Subtitle: null,
    Description: 'Safe fixture detail.', EpisodeNumber: null, StartUtc: start, StopUtc: stop, Status: status,
    CategoryKeys: status === 'Live' ? ['live-now', 'wrestling'] : status === 'StartingSoon' ? ['starting-soon', 'wrestling'] : ['wrestling'],
    Sport: 'Wrestling', League: null, HomeParticipant: null, AwayParticipant: null, Promotion: null,
    Offerings: [{
      OfferingId: 'b'.repeat(64), SourceId: 'cf-' + 'c'.repeat(64), SourceLabel: 'Accepted guide',
      Availability: 'GuideOnly', Entitlement: 'Unknown', Launch: { Kind: 'Channel', ChannelReference: 'cf-' + 'd'.repeat(64) },
      DvrSupported: null, TimeshiftSupported: null,
    }],
    OfferingCount: 1, OfferingsTruncated: false, FreshnessState: 'Unknown', ConfidenceState: 'Unknown', ConfidenceScore: null,
  }
}

const items = [
  item(0, 'Live Wrestling', 'Live', '2026-10-02T10:00:00Z', '2026-10-02T11:00:00Z'),
  item(1, 'Soon Wrestling', 'StartingSoon', '2026-10-02T11:00:00Z', '2026-10-02T12:00:00Z'),
  item(2, 'Upcoming Wrestling', 'Upcoming', '2026-10-02T14:00:00Z', '2026-10-02T15:00:00Z'),
]

function projectionPage(items: OneGuideItem[], offset: number, query: 'Category' | 'Details') {
  return {
    Version: 'one-guide/v1', EvaluationTimeUtc: evaluationTimeUtc, Query: query, Offset: offset, MaximumItems: 100,
    TotalCount: items.length, ItemsTruncated: false, Items: items,
    ...(query === 'Category' ? { CategoryKey: 'wrestling' } : {}),
  }
}

test('opens the read-only Wrestling hub and navigates its status sections with the remote contract', async ({ page }) => {
  const apiRequests: string[] = []
  await page.route('**/api/**', async (route) => {
    const request = route.request()
    const url = new URL(request.url())
    apiRequests.push(`${request.method()} ${url.pathname}${url.search}`)
    if (url.pathname === '/api/status') {
      await route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify({ Service: 'ChannelForge', Status: 'ok', Message: 'ChannelForge is running', ReadOnly: true, LineupStatus: 'not-accepted' }),
      })
      return
    }
    if (url.pathname === '/api/one-guide/category/wrestling') {
      expect(url.searchParams.get('window')).toBe('active')
      expect(url.searchParams.get('limit')).toBe('100')
      expect(url.searchParams.get('offset')).toBe('0')
      await route.fulfill({
        contentType: 'application/json',
        headers: { 'X-ChannelForge-Generation': generation },
        body: JSON.stringify(projectionPage(items, 0, 'Category')),
      })
      return
    }

    const match = /^\/api\/one-guide\/items\/([a-f0-9]{64})$/.exec(url.pathname)
    expect(match).not.toBeNull()
    await route.fulfill({ contentType: 'application/json', body: JSON.stringify(projectionPage([items[1]], 0, 'Details')) })
  })

  await page.goto('/')
  await expect(page.getByRole('button', { name: 'Workbench' })).toBeVisible()
  await page.keyboard.press('ArrowDown')
  const workbenchNav = page.getByRole('button', { name: 'Workbench' })
  await expect(workbenchNav).toBeFocused()
  await page.keyboard.press('ArrowDown')
  await page.keyboard.press('ArrowDown')
  const wrestlingNav = page.getByRole('button', { name: 'Wrestling' })
  await expect(wrestlingNav).toBeFocused()
  await page.keyboard.press('Enter')

  await expect(page.getByRole('heading', { level: 1, name: 'Wrestling' })).toBeVisible()
  const live = page.getByRole('list', { name: 'On Now' }).getByRole('button', { name: /Live Wrestling/ })
  const soon = page.getByRole('list', { name: 'Starting Soon' }).getByRole('button', { name: /Soon Wrestling/ })
  const upcoming = page.getByRole('list', { name: 'Coming Up' }).getByRole('button', { name: /Upcoming Wrestling/ })
  await expect(live).toBeVisible()
  await expect(soon).toBeVisible()
  await expect(upcoming).toBeVisible()
  expect(await page.locator('body').innerText()).not.toContain('0'.repeat(64))
  expect(await page.locator('body').innerText()).not.toContain('cf-')
  expect(await page.locator('.main-content').innerText()).not.toMatch(/\b(watch|play|launch)\b/i)
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([])

  await page.keyboard.press('ArrowRight')
  await expect(live).toBeFocused()
  await page.keyboard.press('ArrowDown')
  await expect(soon).toBeFocused()
  await page.keyboard.press('Enter')
  const detail = page.getByRole('dialog', { name: 'Soon Wrestling' })
  await expect(detail).toBeVisible()
  await expect(detail).toContainText('Guide information only. Playback is not available here.')
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([])
  await page.keyboard.press('Escape')
  await expect(soon).toBeFocused()

  expect(new Set(apiRequests)).toEqual(new Set([
    'GET /api/status',
    'GET /api/one-guide/category/wrestling?limit=100&offset=0&window=active',
    `GET /api/one-guide/items/${items[1].ItemId}`,
  ]))
})
