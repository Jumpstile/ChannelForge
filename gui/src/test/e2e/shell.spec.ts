import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'

test('renders the guided workbench shell and links to setup', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Workflow pages' })).toBeVisible()
  await expect(page.getByText('root-7a91…d42c')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Open Guided Setup' })).toBeEnabled()
  await expect(page.locator('body')).not.toContainText('C:\\')
  await expect(page.locator('body')).not.toContainText('https://')
})

test('renders the preview-only Guided Setup selection contract', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeVisible()
  await expect(page.getByRole('region', { name: 'Guided setup steps' })).toBeVisible()
  await expect(page.getByText('Your playlist tells ChannelForge what channels you have.')).toBeVisible()
  await expect(page.getByText('Your guide tells ChannelForge what is on those channels.')).toBeVisible()
  await expect(page.getByText('No workspace, playlist, or guide is selected or checked. These controls do not open files or save changes yet.')).toBeVisible()
  await expect(page.getByText('Preview only. Playlist content is not checked here.')).toBeVisible()
  await expect(page.getByText('Preview only. Guide content is not checked here.')).toBeVisible()
  const setupRegion = page.getByRole('region', { name: 'Guided setup steps' })
  await expect(setupRegion.getByText('Not selected', { exact: true })).toHaveCount(3)
  await expect(setupRegion.getByText('Not checked', { exact: true })).toHaveCount(5)
  await expect(page.getByText('No workspace is selected.')).toBeVisible()
  await expect(page.getByText('No playlist is selected.')).toBeVisible()
  await expect(page.getByText('No guide is selected.')).toBeVisible()
  for (const label of ['Choose workspace', 'Add playlist', 'Add guide']) {
    await expect(page.getByRole('button', { name: label })).toBeDisabled()
  }
  await expect(page.getByText('Preview only', { exact: true })).toHaveCount(5)
  await expect(page.locator('body')).not.toContainText('C:\\')
  await expect(page.locator('body')).not.toContainText('C:/')
  await expect(page.locator('body')).not.toContainText('https://')
  await expect(page.locator('body')).not.toContainText('file://')
})

test('passes the axe accessibility scan on the workbench', async ({ page }) => {
  await page.goto('/')
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations).toEqual([])
})

test('passes the axe accessibility scan on Guided Setup', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
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
