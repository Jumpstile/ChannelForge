import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'

test('renders the guided workbench shell without operational controls', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Workflow pages' })).toBeVisible()
  await expect(page.getByText('root-7a91…d42c')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Coming next' })).toBeDisabled()
  await expect(page.locator('body')).not.toContainText('C:\\')
  await expect(page.locator('body')).not.toContainText('https://')
})

test('passes the axe accessibility scan on the workbench', async ({ page }) => {
  await page.goto('/')
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations).toEqual([])
})

test('passes the axe accessibility scan on the state gallery', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: /view state gallery/i }).last().click()
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations).toEqual([])
})

test('renders all synthetic state gallery cards', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: /view state gallery/i }).last().click()
  const gallery = page.getByRole('region', { name: 'ChannelForge status states' })
  await expect(gallery).toBeVisible()
  for (const state of ['Not configured', 'Not checked', 'Running', 'Ready', 'Warning', 'Review needed', 'Blocked', 'Failed', 'Success', 'Disabled']) {
    await expect(gallery.getByText(state, { exact: true })).toBeVisible()
  }
  await expect(page.getByText('Synthetic data only')).toBeVisible()
})
