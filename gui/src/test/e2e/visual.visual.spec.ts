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

test('lineup review visual baseline', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'isTauri', { configurable: true, value: true })
    const selected = (kind) => ({
      kind,
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
      ...(kind === 'playlist'
        ? { playlistContent: { contentStatus: 'checked', entryCount: 2, reasonCode: null } }
        : kind === 'guide'
          ? { guideContent: { contentStatus: 'checked', channelCount: 2, programmeCount: 4, reasonCode: null } }
          : {}),
    })
    Object.defineProperty(window, '__TAURI_INTERNALS__', {
      configurable: true,
      value: {
        invoke: async (command, args) => {
          if (command === 'choose_setup_item') return selected(args.kind)
          if (command === 'check_playlist_guide_match') {
            return {
              matchStatus: 'needs-attention',
              playlistEntryCount: 2,
              guideChannelCount: 2,
              matchedCount: 1,
              unmatchedPlaylistCount: 1,
              ambiguousCount: 0,
              guideOnlyCount: 0,
              requiresReview: false,
              reasonCode: 'unmatched-identity',
            }
          }
          throw new Error(`Unexpected command: ${command}`)
        },
      },
    })
  })
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await page.getByRole('button', { name: 'Choose workspace' }).click()
  await page.getByRole('button', { name: 'Add playlist' }).click()
  await page.getByRole('button', { name: 'Add guide' }).click()
  await page.getByRole('button', { name: 'Check playlist and guide' }).click()
  await page.getByRole('button', { name: 'Open lineup review' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Review playlist and guide coverage' })).toBeVisible()
  await expect(page).toHaveScreenshot('lineup-review.png', { animations: 'disabled', fullPage: true })
})

test('saved-lineup confirmation visual baseline', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'isTauri', { configurable: true, value: true })
    const selected = (kind) => ({
      kind,
      outcome: 'selected',
      selectionStatus: 'selected',
      validationStatus: 'ready-to-inspect',
      reasonCode: null,
      ...(kind === 'playlist'
        ? { playlistContent: { contentStatus: 'checked', entryCount: 2, reasonCode: null } }
        : kind === 'guide'
          ? { guideContent: { contentStatus: 'checked', channelCount: 2, programmeCount: 4, reasonCode: null } }
          : {}),
    })
    Object.defineProperty(window, '__TAURI_INTERNALS__', {
      configurable: true,
      value: {
        invoke: async (command, args) => {
          if (command === 'choose_setup_item') return selected(args.kind)
          if (command === 'check_playlist_guide_match') {
            return {
              matchStatus: 'checked',
              playlistEntryCount: 2,
              guideChannelCount: 2,
              matchedCount: 2,
              unmatchedPlaylistCount: 0,
              ambiguousCount: 0,
              guideOnlyCount: 0,
              requiresReview: false,
              reasonCode: null,
            }
          }
          if (command === 'prepare_saved_lineup_plan') {
            return {
              planStatus: 'ready',
              playlistEntryCount: 2,
              guideChannelCount: 2,
              matchedCount: 2,
              unmatchedPlaylistCount: 0,
              ambiguousCount: 0,
              guideOnlyCount: 0,
              requiresReview: false,
              acceptedLineupStatus: 'none',
              candidateFreshness: 'current',
              acceptedEntryCount: null,
            }
          }
          throw new Error(`Unexpected command: ${command}`)
        },
      },
    })
  })
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await page.getByRole('button', { name: 'Choose workspace' }).click()
  await page.getByRole('button', { name: 'Add playlist' }).click()
  await page.getByRole('button', { name: 'Add guide' }).click()
  await page.getByRole('button', { name: 'Check playlist and guide' }).click()
  await page.getByRole('button', { name: 'Open lineup review' }).click()
  await page.getByRole('button', { name: 'Prepare save preview' }).click()
  await page.getByRole('button', { name: 'Save lineup' }).click()
  await expect(page.getByRole('dialog')).toBeVisible()
  await expect(page).toHaveScreenshot('saved-lineup-dialog.png', { animations: 'disabled', fullPage: true })
})
