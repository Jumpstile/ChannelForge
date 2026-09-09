import { ArrowLeft, CheckCircle2 } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import type { UiStatus } from '../components/StatusBadge'
import type { MatchStatus, PlaylistGuideMatchState } from '../app/setupSelection'

type LineupReviewPageProps = {
  matchState: PlaylistGuideMatchState
  onBack: () => void
}

type ReviewCopy = {
  bannerStatus: UiStatus
  title: string
  message: string
  detail: string
}

const bannerStatuses: Record<MatchStatus, UiStatus> = {
  'not-checked': 'Not checked',
  checking: 'Running',
  checked: 'Success',
  'needs-attention': 'Warning',
  'review-needed': 'Review needed',
  blocked: 'Blocked',
}

function countLabel(value: number | null, noun: string): string {
  return `${value ?? 0} ${noun}`
}

function reviewCopy(state: PlaylistGuideMatchState): ReviewCopy {
  if (state.status === 'checked') {
    return {
      bannerStatus: bannerStatuses.checked,
      title: 'Exact coverage found',
      message: 'Every playlist entry has one exact guide match. Nothing has been saved.',
      detail: 'This result is ready for review only. It does not create or change a lineup.',
    }
  }
  if (state.status === 'needs-attention') {
    const notices: string[] = []
    if ((state.unmatchedPlaylistCount ?? 0) > 0) {
      notices.push(`${countLabel(state.unmatchedPlaylistCount, 'playlist entries')} have no guide match`)
    }
    if ((state.guideOnlyCount ?? 0) > 0) {
      notices.push(`${countLabel(state.guideOnlyCount, 'guide channels')} have no playlist counterpart`)
    }
    return {
      bannerStatus: bannerStatuses['needs-attention'],
      title: 'Coverage needs attention',
      message: `${notices.join('. ')}. Review the coverage before any future lineup action.`,
      detail: 'Guide-only coverage is informational. Nothing is removed or changed.',
    }
  }
  if (state.status === 'review-needed') {
    return {
      bannerStatus: bannerStatuses['review-needed'],
      title: 'Review is needed',
      message: `${countLabel(state.ambiguousCount, 'playlist entries')} have more than one possible guide relationship.`,
      detail: 'No relationship was selected automatically, and nothing has been saved.',
    }
  }
  if (state.status === 'checking') {
    return {
      bannerStatus: bannerStatuses.checking,
      title: 'Checking coverage',
      message: 'The local playlist and guide are being compared. No lineup changes are being made.',
      detail: 'This review will show aggregate counts when the check completes.',
    }
  }
  if (state.status === 'blocked') {
    return {
      bannerStatus: bannerStatuses.blocked,
      title: 'Review is blocked',
      message: 'Matching cannot safely run, or the previous result is no longer current.',
      detail: 'Return to Guided Setup and check both local files again.',
    }
  }
  return {
    bannerStatus: bannerStatuses['not-checked'],
    title: 'Review is not ready',
    message: 'Run the local playlist and guide check first.',
    detail: 'This surface only presents a safe aggregate result; it does not run matching.',
  }
}

export function LineupReviewPage({ matchState, onBack }: LineupReviewPageProps) {
  const copy = reviewCopy(matchState)
  const metrics = [
    { label: 'Playlist entries', value: matchState.playlistEntryCount },
    { label: 'Guide channels', value: matchState.guideChannelCount },
    { label: 'Exact matches', value: matchState.matchedCount },
    { label: 'No guide match', value: matchState.unmatchedPlaylistCount },
    { label: 'Needs review', value: matchState.ambiguousCount },
    { label: 'Guide-only', value: matchState.guideOnlyCount },
  ]

  return (
    <div className="page-stack">
      <PageHeader
        action={
          <button className="button button-secondary" type="button" onClick={onBack}>
            <ArrowLeft size={17} aria-hidden="true" />
            Return to Guided Setup
          </button>
        }
        description="Understand playlist and guide coverage before any future saved-lineup action."
        eyebrow="Lineup review"
        title="Review playlist and guide coverage"
      />

      <StatusBanner status={copy.bannerStatus} title={copy.title}>
        <p>{copy.message}</p>
        <p>{copy.detail}</p>
      </StatusBanner>

      <section className="lineup-review-card" aria-labelledby="lineup-review-summary-title">
        <div className="lineup-review-heading">
          <div className="setup-progress-icon" aria-hidden="true">
            <CheckCircle2 size={20} />
          </div>
          <div>
            <p className="eyebrow">Aggregate result</p>
            <h2 id="lineup-review-summary-title">What the check found</h2>
          </div>
        </div>
        <div className="lineup-review-grid" aria-label="Playlist and guide review counts">
          {metrics.map(({ label, value }) => (
            <div className="lineup-review-metric" key={label}>
              <span>{label}</span>
              <strong>{value ?? '—'}</strong>
            </div>
          ))}
        </div>
        <p className="lineup-review-note">Matched means one exact playlist-to-guide identity relationship. Channel IDs, programme titles, stream URLs, and source file details stay hidden.</p>
      </section>

      <section className="lineup-review-card" aria-labelledby="lineup-review-next-title">
        <div className="lineup-review-heading">
          <div className="setup-progress-icon" aria-hidden="true">
            <CheckCircle2 size={20} />
          </div>
          <div>
            <p className="eyebrow">Before saving</p>
            <h2 id="lineup-review-next-title">Nothing changes from this review</h2>
          </div>
        </div>
        <p className="lineup-review-note" role="status" aria-live="polite">
          {copy.title}. {copy.message}
        </p>
        <p className="lineup-review-note">This screen is local and read-only. It does not accept ambiguous relationships, build a lineup, save state, export files, or publish output.</p>
      </section>
    </div>
  )
}
