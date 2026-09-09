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
  const onBack = vi.fn()
  render(<LineupReviewPage matchState={state} onBack={onBack} />)
  return onBack
}

describe('read-only lineup review', () => {
  it.each([
    ['not-checked', 'Review is not ready'],
    ['checking', 'Checking coverage'],
    ['checked', 'Exact coverage found'],
    ['needs-attention', 'Coverage needs attention'],
    ['review-needed', 'Review is needed'],
    ['blocked', 'Review is blocked'],
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
    expect(screen.getByText('No relationship was selected automatically, and saving is blocked.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /accept|apply|resolve|save|export|publish/i })).not.toBeInTheDocument()
    expect(document.body.textContent).not.toContain('https://secret.invalid')
    expect(document.body.textContent).not.toContain('playlist-id-secret')
    expect(document.body.textContent).not.toContain('programme-title-secret')
  })

  it('keeps guide-only coverage informational and non-destructive', () => {
    renderReview(matchState('needs-attention', { unmatchedPlaylistCount: 0, guideOnlyCount: 2 }))

    expect(screen.getByText(/2 guide channels have no playlist counterpart/)).toBeInTheDocument()
    expect(screen.getByText('Guide-only coverage is informational, but this state cannot be saved.')).toBeInTheDocument()
  })

  it('returns to Guided Setup through the only available action', async () => {
    const user = userEvent.setup()
    const onBack = renderReview()

    await user.click(screen.getByRole('button', { name: 'Return to Guided Setup' }))
    expect(onBack).toHaveBeenCalledOnce()
  })

  it('keeps the aggregate announcement live and keyboard navigable', async () => {
    const user = userEvent.setup()
    const onBack = renderReview(matchState('needs-attention', { unmatchedPlaylistCount: 1 }))
    const status = screen.getByRole('status')

    expect(status).toHaveAttribute('aria-live', 'polite')
    await user.tab()
    expect(screen.getByRole('button', { name: 'Return to Guided Setup' })).toHaveFocus()
    await user.keyboard('{Enter}')
    expect(onBack).toHaveBeenCalledOnce()
  })


  it('offers a save preview only for checked coverage', async () => {
    const user = userEvent.setup()
    const planner = vi.fn().mockResolvedValue(readyPlan())
    render(<LineupReviewPage matchState={matchState('checked')} onBack={vi.fn()} planner={planner} />)

    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await waitFor(() => expect(screen.getByText('This is still a candidate preview. Nothing has changed, and the current saved lineup remains unchanged.')).toBeInTheDocument())
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
        onBack={vi.fn()}
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
    expect(screen.getByText('Saved lineup is available from the Saved lineup navigation item.')).toBeInTheDocument()
  })

  it('cancels and closes with Escape without calling native acceptance', async () => {
    const user = userEvent.setup()
    const acceptor = vi.fn().mockResolvedValue(savedResult())
    render(
      <LineupReviewPage
        acceptor={acceptor}
        matchState={matchState('checked')}
        onBack={vi.fn()}
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
        onBack={vi.fn()}
        planner={vi.fn().mockResolvedValue(readyPlan())}
      />,
    )

    await user.click(screen.getByRole('button', { name: 'Prepare save preview' }))
    await user.click(screen.getByRole('button', { name: 'Save lineup' }))
    const dialog = screen.getByRole('dialog')
    await user.click(within(dialog).getByRole('checkbox', { name: /understand/i }))
    await user.click(within(dialog).getByRole('button', { name: 'Save lineup' }))
    await waitFor(() => expect(acceptor).toHaveBeenCalledOnce())
    expect(screen.getByText('The candidate or accepted parent changed. Nothing was saved. Run the check and prepare a new preview.')).toBeInTheDocument()
    expect(screen.queryByText('Saved lineup is available from the Saved lineup navigation item.')).not.toBeInTheDocument()
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
