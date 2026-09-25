import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'

test('renders the guided workbench shell and links to setup', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Workflow pages' })).toBeVisible()
  await expect(page.getByText('Demo workspace')).toBeVisible()
  await expect(page.locator('body')).not.toContainText('root-')
  await expect(page.getByRole('button', { name: 'Open Guided Setup' })).toBeEnabled()
  await expect(page.locator('body')).not.toContainText('C:\\')
  await expect(page.locator('body')).not.toContainText('https://')
})

test('renders the browser Guided Setup review and acceptance contract', async ({ page }) => {
  await page.route('**/api/guided-setup/proposal', async (route) => {
    expect(route.request().method()).toBe('POST')
    expect(route.request().postDataJSON()).toMatchObject({
      schemaVersion: 2,
      playlists: [{ sourceKey: 'playlist-1', label: 'Playlist 1', priority: 1, contentBase64: expect.any(String) }],
      guides: [],
      bindings: [],
    })
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        Version: 'guided-setup/proposal/v2',
        Status: 'PROPOSAL_READY',
        Proposal: {
          ProposalId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          PlaylistCount: 1,
          GuideCount: 0,
          BoundGuideCount: 0,
          UnboundGuideCount: 0,
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
    expect(route.request().method()).toBe('POST')
    expect(await route.request().postDataJSON()).toEqual({ schemaVersion: 2, proposalId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', acknowledged: true })
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        Version: 'guided-setup/acceptance/v2',
        Status: 'ACCEPTED',
        Proposal: { ChannelCount: 1, GuideStatus: 'NO_GUIDE_SELECTED' },
        Safety: { AcceptedStateMutation: 'accepted-lineup', ProviderMutation: 'none', DownstreamMutation: 'none', SchedulerMutation: 'none' },
      }),
    })
  })
  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Workspace ready' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Choose workspace' })).toHaveCount(0)
  await expect(page.getByText('Add at least one playlist to analyze.')).toBeVisible()
  await expect(page.getByRole('region', { name: 'Guided setup steps' })).toBeVisible()
  await expect(page.getByText('Files are read in this browser only to create a server-owned candidate. Nothing is accepted until you acknowledge the review.')).toBeVisible()
  await expect(page.getByText('Add every playlist that belongs in the source set.')).toBeVisible()
  await expect(page.getByText('No guide selected')).toBeVisible()
  await page.getByLabel('Choose playlist').setInputFiles({ name: 'channels.m3u', mimeType: 'audio/x-mpegurl', buffer: Buffer.from('#EXTM3U\\n#EXTINF:-1,One\\nhttps://example.invalid/one\\n') })
  await expect(page.getByText('Ready to analyze 1 playlist.')).toBeVisible()
  await page.getByRole('button', { name: 'Analyze source set' }).click()
  await expect(page.getByText('Review ready. Nothing has been accepted yet.')).toBeVisible()
  await expect(page.getByText('Unmatched playlists')).toBeVisible()
  await expect(page.locator('dt').filter({ hasText: 'Unmatched playlists' }).locator('xpath=following-sibling::dd[1]')).toHaveText('1')
  await expect(page.locator('body')).not.toContainText('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  await page.getByLabel(/I reviewed these results/).check()
  await page.getByRole('button', { name: 'Accept reviewed proposal' }).click()
  await expect(page.getByText('Accepted lineup confirmed.')).toBeVisible()
  await expect(page.getByText('The reviewed source set is now the accepted local state.')).toBeVisible()
  await expect(page.locator('body')).not.toContainText('C:\\')
  await expect(page.locator('body')).not.toContainText('file://')
})
test('shows a focused safe error and retains loaded playlists after Analyze fails', async ({ page }) => {
  await page.route('**/api/guided-setup/proposal', async (route) => {
    expect(route.request().postDataJSON()).toMatchObject({
      schemaVersion: 2,
      playlists: [{ sourceKey: 'playlist-1' }, { label: 'Playlist 2' }],
    })
    await route.fulfill({
      status: 503,
      contentType: 'application/json',
      body: JSON.stringify({
        Error: 'package-data-unavailable',
        Message: 'C:\\private\\provider.local.json?token=secret',
      }),
    })
  })

  await page.goto('/')
  await page.getByRole('button', { name: 'Open Guided Setup' }).click()
  await page.getByLabel('Choose playlist').setInputFiles({ name: 'channels-one.m3u', mimeType: 'audio/x-mpegurl', buffer: Buffer.from('#EXTM3U\\n#EXTINF:-1,One\\nhttps://example.invalid/one\\n') })
  await page.getByRole('button', { name: 'Add another playlist' }).click()
  await page.getByLabel('Choose playlist').nth(1).setInputFiles({ name: 'channels-two.m3u', mimeType: 'audio/x-mpegurl', buffer: Buffer.from('#EXTM3U\\n#EXTINF:-1,Two\\nhttps://example.invalid/two\\n') })
  await expect(page.getByText('Ready to analyze 2 playlists.')).toBeVisible()
  await page.getByRole('button', { name: 'Analyze source set' }).click()

  const error = page.getByRole('alert')
  await expect(error).toContainText('ChannelForge is missing required analysis data.')
  await expect(error).toBeVisible()
  await expect(error).toBeInViewport()
  await expect(error).toBeFocused()
  await expect(page.getByText('Analysis stopped; 2 playlists remain selected.')).toBeVisible()
  await expect(page.getByText('channels-one.m3u')).toBeVisible()
  await expect(page.getByText('channels-two.m3u')).toBeVisible()
  await expect(page.locator('body')).not.toContainText('C:\\private')
  await expect(page.locator('body')).not.toContainText('token=secret')
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
  await page
    .getByRole('button', { name: /view state gallery/i })
    .last()
    .click()
  const results = await new AxeBuilder({ page }).analyze()
  expect(results.violations).toEqual([])
})

test('renders all synthetic state gallery cards', async ({ page }) => {
  await page.goto('/')
  await page
    .getByRole('button', { name: /view state gallery/i })
    .last()
    .click()
  const gallery = page.getByRole('region', {
    name: 'ChannelForge status states',
  })
  await expect(gallery).toBeVisible()
  for (const state of [
    'Not configured',
    'Not checked',
    'Running',
    'Ready',
    'Warning',
    'Review needed',
    'Blocked',
    'Failed',
    'Success',
    'Disabled',
  ]) {
    await expect(gallery.getByText(state, { exact: true })).toBeVisible()
  }
  await expect(page.getByText('Synthetic data only')).toBeVisible()
})

test('opens read-only lineup review after a safe aggregate result', async ({ page }) => {
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
  await expect(page.getByRole('button', { name: 'Open lineup review' })).toBeEnabled()
  await page.getByRole('button', { name: 'Open lineup review' }).click()

  await expect(page.getByRole('heading', { level: 1, name: 'Review playlist and guide coverage' })).toBeVisible()
  await expect(
    page.getByRole('region', { name: /Coverage needs/ }).getByText('1 playlist entries have no guide match.', { exact: false }),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: /Saved lineup/ })).toBeDisabled()
  for (const action of ['Accept', 'Apply', 'Resolve', 'Save', 'Export', 'Publish']) {
    await expect(page.getByRole('button', { name: action, exact: true })).toHaveCount(0)
  }
  await expect(page.locator('body')).not.toContainText('https://secret.invalid')
  await expect(page.locator('body')).not.toContainText('playlist-id-secret')
  await expect(page.locator('body')).not.toContainText('programme-title-secret')
})

test('saves a checked lineup only after accessible confirmation', async ({ page }) => {
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
          if (command === 'accept_saved_lineup') {
            return {
              saveStatus: 'saved',
              acceptedLineupStatus: 'present',
              acceptedEntryCount: 2,
              reasonCode: null,
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
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Save lineup' })).toBeDisabled()
  await dialog.getByRole('checkbox', { name: /understand/i }).check()
  await dialog.getByRole('button', { name: 'Save lineup' }).click()
  await expect(page.getByText('Saved lineup is available from the Saved lineup navigation item.')).toBeVisible()
  await expect(page.getByRole('button', { name: /Saved lineup(?! Next)/ })).toBeEnabled()
  await expect(page.locator('body')).not.toContainText('https://')
  await expect(page.locator('body')).not.toContainText('C:\\')
})
