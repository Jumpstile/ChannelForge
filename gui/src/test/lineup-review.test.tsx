import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { LineupReviewPage } from '../pages/LineupReviewPage'
import { playlistGuideMatchStateFromResult, type MatchStatus, type PlaylistGuideMatchResult, type PlaylistGuideMatchState } from '../app/setupSelection'

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
    expect(screen.getByText('No relationship was selected automatically, and nothing has been saved.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /accept|apply|resolve|save|export|publish/i })).not.toBeInTheDocument()
    expect(document.body.textContent).not.toContain('https://secret.invalid')
    expect(document.body.textContent).not.toContain('playlist-id-secret')
    expect(document.body.textContent).not.toContain('programme-title-secret')
  })

  it('keeps guide-only coverage informational and non-destructive', () => {
    renderReview(matchState('needs-attention', { unmatchedPlaylistCount: 0, guideOnlyCount: 2 }))

    expect(screen.getAllByText(/2 guide channels have no playlist counterpart/)).toHaveLength(2)
    expect(screen.getByText('Guide-only coverage is informational. Nothing is removed or changed.')).toBeInTheDocument()
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
