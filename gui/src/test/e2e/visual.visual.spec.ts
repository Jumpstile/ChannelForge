import { expect, test } from '@playwright/test'

test('workbench visual baseline', async ({ page }) => {
  await page.goto('/')
  await expect(page).toHaveScreenshot('workbench.png', { animations: 'disabled', fullPage: true })
})

test('state gallery visual baseline', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: /view state gallery/i }).last().click()
  await expect(page).toHaveScreenshot('state-gallery.png', { animations: 'disabled', fullPage: true })
})

test('guided setup visual baseline', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await expect(page).toHaveScreenshot('guided-setup.png', { animations: 'disabled', fullPage: true })
})
