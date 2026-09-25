import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import App from '../App'
import { acceptedLineupStatusAfterMatchStateChange } from '../app/setupSelection'
import type {
  SavedLineupAcceptor,
  SavedLineupPlanner,
  SavedLineupResult,
  SetupMatcher,
  SetupPicker,
  SetupSelectionKind,
  SetupSelectionResult,
} from '../app/setupSelection'

function selectedResult(kind: SetupSelectionKind): SetupSelectionResult {
  return {
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
  }
}

describe('navigation shell', () => {
  it('retains accepted evidence during native match rechecks', () => {
    expect(acceptedLineupStatusAfterMatchStateChange('present', 'checking')).toBe('present')
    expect(acceptedLineupStatusAfterMatchStateChange('present', 'checked')).toBe('present')
    expect(acceptedLineupStatusAfterMatchStateChange('present', 'not-checked')).toBe('unavailable')
  })

  it('starts at Workbench and opens the synthetic state gallery without backend work', async () => {
    const user = userEvent.setup()
    render(<App />)

    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2, name: 'Add playlists and optional guides' })).toBeInTheDocument()
    expect(screen.getByText("Open Guided Setup to add one or more playlists and optional XMLTV guides. Your review stays in ChannelForge's server-owned workspace. Choose which playlists each guide covers.")).toBeInTheDocument()
    expect(screen.queryByText(/Choose a workspace/)).not.toBeInTheDocument()
    await user.click(screen.getAllByRole('button', { name: /view state gallery/i }).at(-1)!)
    expect(screen.getByRole('heading', { name: 'State gallery' })).toBeInTheDocument()
    expect(screen.getByText('Synthetic data only')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /return to workbench/i }))
    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
  })

  it('opens browser Guided Setup with multi-source review and explicit binding controls', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Open Guided Setup' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeInTheDocument()
    expect(screen.getByText(/Files are read in this browser only to create a server-owned candidate/)).toBeInTheDocument()
    expect(screen.getByText('Add every playlist that belongs in the source set. Each item can be a local file or a public HTTPS URL.')).toBeInTheDocument()
    expect(screen.getByText('Guides are optional. Continue with no guide, or add each XMLTV file or public HTTPS URL explicitly.')).toBeInTheDocument()
    expect(screen.getByText('No guide selected')).toBeInTheDocument()
    expect(screen.getByText('Server-owned')).toBeInTheDocument()
    expect(screen.getByLabelText('Choose playlist')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add another playlist' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Analyze source set' })).toBeEnabled()
  })

  it('does not expose future workflow pages as active controls', () => {
    render(<App />)

    for (const label of ['Playlist', 'Guide', 'Lineup', 'Saved lineup', 'Automatic updates', 'Learn']) {
      expect(screen.getByRole('button', { name: new RegExp(`${label} Next`) })).toBeDisabled()
    }
  })
  it('enables read-only lineup review only after a safe aggregate result', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>(async (kind) => selectedResult(kind))
    const matcher = vi.fn<SetupMatcher>().mockResolvedValue({
      matchStatus: 'needs-attention',
      playlistEntryCount: 2,
      guideChannelCount: 2,
      matchedCount: 1,
      unmatchedPlaylistCount: 1,
      ambiguousCount: 0,
      guideOnlyCount: 0,
      requiresReview: false,
      reasonCode: 'unmatched-identity',
    })
    render(<App picker={picker} matcher={matcher} pickerAvailable />)

    expect(screen.getByRole('button', { name: /Lineup Next/ })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))
    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    await user.click(screen.getByRole('button', { name: 'Add playlist' }))
    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    await user.click(screen.getByRole('button', { name: 'Check playlist and guide' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Open lineup review' })).toBeEnabled())

    expect(screen.getByRole('button', { name: /Lineup(?! Next)/ })).toBeEnabled()
    expect(screen.getByRole('button', { name: /Saved lineup Next/ })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Open lineup review' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Review playlist and guide coverage' })).toBeInTheDocument()
    for (const action of ['Accept', 'Apply', 'Resolve', 'Save', 'Export', 'Publish']) {
      expect(screen.queryByRole('button', { name: new RegExp(`^${action}$`) })).not.toBeInTheDocument()
    }
  })

  it('enables Saved lineup only after native save success', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>(async (kind) => selectedResult(kind))
    const matcher = vi.fn<SetupMatcher>().mockResolvedValue({
      matchStatus: 'checked',
      playlistEntryCount: 2,
      guideChannelCount: 2,
      matchedCount: 2,
      unmatchedPlaylistCount: 0,
      ambiguousCount: 0,
      guideOnlyCount: 0,
      requiresReview: false,
      reasonCode: null,
    })
    const planner = vi.fn<SavedLineupPlanner>().mockResolvedValue({
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
    })
    const saved: SavedLineupResult = {
      saveStatus: 'saved',
      acceptedLineupStatus: 'present',
      acceptedEntryCount: 2,
      reasonCode: null,
    }
    const acceptor = vi.fn<SavedLineupAcceptor>().mockResolvedValue(saved)
    render(<App acceptor={acceptor} matcher={matcher} picker={picker} pickerAvailable planner={planner} />)

    expect(screen.getByRole('button', { name: /Saved lineup Next/ })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))
    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    await user.click(screen.getByRole('button', { name: 'Add playlist' }))
    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    await user.click(screen.getByRole('button', { name: 'Check playlist and guide' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Open lineup review' })).toBeEnabled())
    await user.click(screen.getByRole('button', { name: 'Open lineup review' }))
    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await user.click(screen.getByRole('button', { name: 'Save lineup' }))
    const dialog = screen.getByRole('dialog')
    await user.click(within(dialog).getByRole('checkbox', { name: /understand/i }))
    await user.click(within(dialog).getByRole('button', { name: 'Save lineup' }))
    await waitFor(() => expect(acceptor).toHaveBeenCalledOnce())
    await waitFor(() => expect(screen.getByRole('button', { name: /Saved lineup(?! Next)/ })).toBeEnabled())
    await user.click(screen.getByRole('button', { name: 'Workbench' }))
    expect(screen.getByRole('button', { name: /Saved lineup(?! Next)/ })).toBeEnabled()
    await user.click(screen.getByRole('button', { name: /Saved lineup(?! Next)/ }))
    expect(screen.getByRole('heading', { level: 1, name: 'Your saved lineup' })).toBeInTheDocument()
  })
})
