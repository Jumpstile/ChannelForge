import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import App from '../App'
import type { SetupMatcher, SetupPicker, SetupSelectionKind, SetupSelectionResult } from '../app/setupSelection'

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
  it('starts at Workbench and opens the synthetic state gallery without backend work', async () => {
    const user = userEvent.setup()
    render(<App />)

    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
    await user.click(screen.getAllByRole('button', { name: /view state gallery/i }).at(-1)!)
    expect(screen.getByRole('heading', { name: 'State gallery' })).toBeInTheDocument()
    expect(screen.getByText('Synthetic data only')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /return to workbench/i }))
    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
  })

  it('opens Guided Setup and shows display-safe unselected states without enabling controls', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Open Guided Setup' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeInTheDocument()
    expect(screen.getByText('Your playlist tells ChannelForge what channels you have.')).toBeInTheDocument()
    expect(screen.getByText('Your guide tells ChannelForge what is on those channels.')).toBeInTheDocument()
    expect(
      screen.getByText(
        'No workspace, playlist, or guide is selected or checked. These controls do not open files or save changes yet.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('Preview only. Playlist content is not checked here.')).toBeInTheDocument()
    expect(screen.getByText('Preview only. Guide content is not checked here.')).toBeInTheDocument()
    expect(screen.getAllByText('Not selected')).toHaveLength(3)
    expect(screen.getAllByText('Not checked')).toHaveLength(6)
    expect(screen.getByText('No workspace is selected.')).toBeInTheDocument()
    expect(screen.getByText('No playlist is selected.')).toBeInTheDocument()
    expect(screen.getByText('No guide is selected.')).toBeInTheDocument()
    for (const label of ['Choose workspace', 'Add playlist', 'Add guide']) {
      expect(screen.getByRole('button', { name: label })).toBeDisabled()
    }
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
})
