import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { LineupReviewPage } from '../pages/LineupReviewPage'
import {
  playlistGuideMatchStateFromResult,
  type MatchStatus,
  type PlaylistGuideMatchResult,
  type PlaylistGuideMatchState,
  type SavedLineupPlan,
  type SavedLineupResult,
} from '../app/setupSelection'

function matchState(status: MatchStatus, overrides: Partial<PlaylistGuideMatchState> = {}): PlaylistGuideMatchState {
  return {
    status,
    label: status,
    detail: 'Synthetic aggregate detail.',
    playlistEntryCount: 4,
    guideChannelCount: 4,
    matchedCount: 4,
    unmatchedPlaylistCount: 0,
    ambiguousCount: 0,
    guideOnlyCount: 0,
    requiresReview: false,
    ...overrides,
  }
}

function readyPlan(): SavedLineupPlan {
  return {
    planStatus: 'ready',
    playlistEntryCount: 4,
    guideChannelCount: 4,
    matchedCount: 4,
    unmatchedPlaylistCount: 0,
    ambiguousCount: 0,
    guideOnlyCount: 0,
    requiresReview: false,
    acceptedLineupStatus: 'none',
    candidateFreshness: 'current',
    acceptedEntryCount: null,
  }
}

function savedResult(): SavedLineupResult {
  return {
    saveStatus: 'saved',
    acceptedLineupStatus: 'present',
    acceptedEntryCount: 4,
    reasonCode: null,
  }
}

function renderReview(state: PlaylistGuideMatchState = matchState('checked')) {
  render(<LineupReviewPage matchState={state} />)
}

describe('read-only lineup review', () => {
  it.each([
    ['not-checked', 'Not ready yet'],
    ['checking', 'Checking your files'],
    ['checked', 'Every channel has a guide match'],
    ['needs-attention', 'Some channels need attention'],
    ['review-needed', 'Some channels need your review'],
    ['blocked', 'The check could not finish'],
  ] as const)('presents the %s aggregate status', (status, title) => {
    renderReview(matchState(status))

    expect(screen.getByRole('heading', { level: 1, name: 'Review playlist and guide coverage' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2, name: title })).toBeInTheDocument()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })

  it('presents matched, unmatched, ambiguous, and guide-only counts without source values', () => {
    renderReview(
      matchState('review-needed', {
        matchedCount: 1,
        unmatchedPlaylistCount: 1,
        ambiguousCount: 2,
        guideOnlyCount: 1,
        requiresReview: true,
      }),
    )

    expect(screen.getByText('Exact matches')).toBeInTheDocument()
    expect(screen.getByText('No guide match')).toBeInTheDocument()
    expect(screen.getByText('Needs review')).toBeInTheDocument()
    expect(screen.getByText('Guide-only')).toBeInTheDocument()
    expect(screen.getByText('ChannelForge did not pick one for you. Saving is turned off until this is sorted out.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /accept|apply|resolve|save|export|publish/i })).not.toBeInTheDocument()
    expect(document.body.textContent).not.toContain('https://secret.invalid')
    expect(document.body.textContent).not.toContain('playlist-id-secret')
    expect(document.body.textContent).not.toContain('programme-title-secret')
  })

  it('keeps guide-only coverage informational and non-destructive', () => {
    renderReview(matchState('needs-attention', { unmatchedPlaylistCount: 0, guideOnlyCount: 2 }))

    expect(screen.getByText(/2 guide channels not in your playlist/)).toBeInTheDocument()
    expect(screen.getByText('Saving is turned off until these counts are sorted out.')).toBeInTheDocument()
  })

  it('has no extra Return button because the Home/Back bar is the way back', () => {
    renderReview()

    expect(screen.queryByRole('button', { name: /^Return to/ })).not.toBeInTheDocument()
  })

  it('keeps the aggregate announcement live', () => {
    renderReview(matchState('needs-attention', { unmatchedPlaylistCount: 1 }))

    expect(screen.getByRole('status')).toHaveAttribute('aria-live', 'polite')
  })


  it('offers a save preview only for checked coverage', async () => {
    const user = userEvent.setup()
    const planner = vi.fn().mockResolvedValue(readyPlan())
    render(<LineupReviewPage matchState={matchState('checked')} planner={planner} />)

    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await waitFor(() => expect(screen.getByText('This is only a preview. Nothing has changed, and your current saved lineup stays as it is.')).toBeInTheDocument())
    expect(planner).toHaveBeenCalledOnce()
    expect(screen.getByRole('button', { name: 'Save lineup' })).toBeInTheDocument()
  })

  it.each(['needs-attention', 'review-needed', 'blocked', 'not-checked', 'checking'] as const)('blocks save preview for %s status', (status) => {
    renderReview(matchState(status))

    expect(screen.queryByRole('button', { name: 'Prepare save preview' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Save lineup' })).not.toBeInTheDocument()
  })

  it('requires explicit acknowledgement before the native acceptance call', async () => {
    const user = userEvent.setup()
    const acceptor = vi.fn().mockResolvedValue(savedResult())
    const onSavedLineupChange = vi.fn()
    render(
      <LineupReviewPage
        acceptor={acceptor}
        matchState={matchState('checked')}
        onSavedLineupChange={onSavedLineupChange}
        planner={vi.fn().mockResolvedValue(readyPlan())}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await user.click(screen.getByRole('button', { name: 'Save lineup' }))
    const dialog = screen.getByRole('dialog')
    const confirm = within(dialog).getByRole('button', { name: 'Save lineup' })
    expect(confirm).toBeDisabled()
    await user.click(within(dialog).getByRole('checkbox', { name: /understand/i }))
    expect(confirm).toBeEnabled()
    await user.click(confirm)
    await waitFor(() => expect(acceptor).toHaveBeenCalledOnce())
    expect(onSavedLineupChange).toHaveBeenCalledWith(savedResult())
    expect(screen.getByText('Your lineup is saved. Open Saved lineup in the menu to see it.')).toBeInTheDocument()
  })

  it('cancels and closes with Escape without calling native acceptance', async () => {
    const user = userEvent.setup()
    const acceptor = vi.fn().mockResolvedValue(savedResult())
    render(
      <LineupReviewPage
        acceptor={acceptor}
        matchState={matchState('checked')}
        planner={vi.fn().mockResolvedValue(readyPlan())}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await user.click(screen.getByRole('button', { name: 'Save lineup' }))
    expect(within(screen.getByRole('dialog')).getByRole('button', { name: 'Save lineup' })).toBeDisabled()
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Save lineup' }))
    await user.keyboard('{Escape}')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(acceptor).not.toHaveBeenCalled()
  })

  it('keeps saved navigation unavailable when the native acceptance result is stale', async () => {
    const user = userEvent.setup()
    const staleResult: SavedLineupResult = {
      saveStatus: 'stale',
      acceptedLineupStatus: 'unavailable',
      acceptedEntryCount: null,
      reasonCode: 'stale-candidate',
    }
    const acceptor = vi.fn().mockResolvedValue(staleResult)
    render(
      <LineupReviewPage
        acceptor={acceptor}
        matchState={matchState('checked')}
        planner={vi.fn().mockResolvedValue(readyPlan())}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await user.click(screen.getByRole('button', { name: 'Save lineup' }))
    const dialog = screen.getByRole('dialog')
    await user.click(within(dialog).getByRole('checkbox', { name: /understand/i }))
    await user.click(within(dialog).getByRole('button', { name: 'Save lineup' }))
    await waitFor(() => expect(acceptor).toHaveBeenCalledOnce())
    expect(screen.getByText('Your files changed while you were working, so ChannelForge stopped. Nothing was saved.')).toBeInTheDocument()
    expect(screen.queryByText('Your lineup is saved. Open Saved lineup in the menu to see it.')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('stale-candidate')).toBeInTheDocument()
  })
  it('maps native aggregate results to fixed review-safe state', () => {
    const result: PlaylistGuideMatchResult = {
      matchStatus: 'needs-attention',
      playlistEntryCount: 4,
      guideChannelCount: 3,
      matchedCount: 2,
      unmatchedPlaylistCount: 2,
      ambiguousCount: 0,
      guideOnlyCount: 1,
      requiresReview: false,
      reasonCode: 'unmatched-identity',
    }

    const state = playlistGuideMatchStateFromResult(result)
    expect(state).toMatchObject({
      status: 'needs-attention',
      matchedCount: 2,
      unmatchedPlaylistCount: 2,
      guideOnlyCount: 1,
      requiresReview: false,
    })
    expect(JSON.stringify(state)).not.toMatch(/(?:https?:\/\/|[A-Za-z]:[\\/]|channel-id|programme-title|token|password|secret|credential)/i)
  })
})

describe('Lineup Review failure reasons', () => {
  it('keeps the thrown preview error under Details and falls back to the plain text without one', async () => {
    const user = userEvent.setup()
    const planner = vi.fn().mockRejectedValueOnce(new Error('planner exploded')).mockRejectedValueOnce('no message')
    render(<LineupReviewPage matchState={matchState('checked')} planner={planner} />)
    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    const alert = await screen.findByRole('alert')
    expect(alert).not.toHaveTextContent('planner exploded')
    await user.click(within(alert).getByRole('button', { name: 'Details' }))
    expect(screen.getByText('planner exploded')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('could not tell why'))
  })
})
