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
test('browser acceptance visual states', async ({ page }) => {
  await page.route('**/api/guided-setup/proposal', async (route) => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        Version: 'guided-setup/proposal/v1',
        Status: 'PROPOSAL_READY',
        Proposal: {
          ProposalId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ChannelCount: 1,
          ExactGuideMatchCount: 0,
          AmbiguityCount: 0,
          UnmatchedPlaylistCount: 1,
          GuideOnlyCount: 0,
          GuideStatus: 'NO_GUIDE_SELECTED',
          CanAccept: true,
          BlockingReasons: [],
        },
        Warnings: [{ Code: 'unmatched-playlist-entry', Message: 'Some playlist entries have no exact guide match.' }],
        Safety: {
          PublicationState: 'CandidateOnly',
          AcceptedStateMutation: 'none',
          ProviderMutation: 'none',
          DownstreamMutation: 'none',
          GuidePublication: 'none',
          CanPublish: false,
          CanAccept: true,
        },
      }),
    })
  })
  await page.route('**/api/guided-setup/accept', async (route) => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        Version: 'guided-setup/acceptance/v1',
        Status: 'ACCEPTED',
        Proposal: { ChannelCount: 1, GuideStatus: 'NO_GUIDE_SELECTED' },
        Safety: { AcceptedStateMutation: 'accepted-lineup', ProviderMutation: 'none', DownstreamMutation: 'none', SchedulerMutation: 'none' },
      }),
    })
  })
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await page.getByLabel('Choose playlist').setInputFiles({ name: 'channels.m3u', mimeType: 'audio/x-mpegurl', buffer: Buffer.from('#EXTM3U\\n#EXTINF:-1,One\\nhttps://example.invalid/one\\n') })
  await expect(page).toHaveScreenshot('guided-browser-file-proposal.png', { animations: 'disabled', fullPage: true })
  await page.getByRole('button', { name: 'Analyze proposal' }).click()
  await expect(page.getByText('Review ready. Nothing has been accepted yet.')).toBeVisible()
  await expect(page).toHaveScreenshot('guided-browser-ready.png', { animations: 'disabled', fullPage: true })
  await page.getByLabel(/I reviewed these results/).check()
  await page.getByRole('button', { name: 'Accept reviewed proposal' }).click()
  await expect(page.getByText('Accepted lineup confirmed.')).toBeVisible()
  await expect(page).toHaveScreenshot('guided-browser-accepted.png', { animations: 'disabled', fullPage: true })
})
