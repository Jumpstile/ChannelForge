import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { ArrowLeft, CheckCircle2, X } from 'lucide-react'
import { acceptSavedLineup, prepareSavedLineupPlan } from '../app/setupPicker'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import type { UiStatus } from '../components/StatusBadge'
import type {
  MatchStatus,
  PlaylistGuideMatchState,
  SavedLineupAcceptor,
  SavedLineupPlan,
  SavedLineupPlanner,
  SavedLineupResult,
} from '../app/setupSelection'

type LineupReviewPageProps = {
  matchState: PlaylistGuideMatchState
  onBack: () => void
  planner?: SavedLineupPlanner
  acceptor?: SavedLineupAcceptor
  plan?: SavedLineupPlan | null
  onPlanChange?: (plan: SavedLineupPlan | null) => void
  saveResult?: SavedLineupResult | null
  onSavedLineupChange?: (result: SavedLineupResult) => void
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
      detail: 'This result is ready for a read-only save preview.',
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
      message: `${notices.join('. ')}. Review the coverage before saving.`,
      detail: 'Guide-only coverage is informational, but this state cannot be saved.',
    }
  }
  if (state.status === 'review-needed') {
    return {
      bannerStatus: bannerStatuses['review-needed'],
      title: 'Review is needed',
      message: `${countLabel(state.ambiguousCount, 'playlist entries')} have more than one possible guide relationship.`,
      detail: 'No relationship was selected automatically, and saving is blocked.',
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
    detail: 'This surface only presents safe aggregate results.',
  }
}

function blockedSaveResult(): SavedLineupResult {
  return {
    saveStatus: 'blocked',
    acceptedLineupStatus: 'unavailable',
    acceptedEntryCount: null,
    reasonCode: 'acceptance-failed',
  }
}

function planMessage(matchState: PlaylistGuideMatchState, plan: SavedLineupPlan | null, saveResult: SavedLineupResult | null): string {
  if (saveResult?.saveStatus === 'saved') {
    return 'Saved lineup confirmed. The accepted local state is now available from Saved lineup.'
  }
  if (saveResult?.saveStatus === 'stale') {
    return 'The candidate or accepted parent changed. Nothing was saved. Run the check and prepare a new preview.'
  }
  if (saveResult?.saveStatus === 'blocked') {
    return 'The native acceptance boundary did not save the lineup. Existing accepted state was not changed.'
  }
  if (matchState.status !== 'checked') {
    return 'Saving is blocked until the status is checked with exact coverage.'
  }
  if (plan?.planStatus === 'ready') {
    return 'This is still a candidate preview. Nothing has changed, and the current saved lineup remains unchanged.'
  }
  if (plan?.planStatus === 'stale') {
    return 'The candidate is stale. Nothing was saved. Prepare a new preview.'
  }
  if (plan?.planStatus === 'blocked') {
    return 'The native save preview is unavailable. Existing accepted state was not changed.'
  }
  return 'Prepare a read-only save preview before any accepted state can change.'
}

export function LineupReviewPage({
  matchState,
  onBack,
  planner = prepareSavedLineupPlan,
  acceptor = acceptSavedLineup,
  plan,
  onPlanChange,
  saveResult,
  onSavedLineupChange,
}: LineupReviewPageProps) {
  const [localPlan, setLocalPlan] = useState<SavedLineupPlan | null>(null)
  const [localSaveResult, setLocalSaveResult] = useState<SavedLineupResult | null>(null)
  const effectiveSaveResult = saveResult === undefined ? localSaveResult : saveResult
  const [planning, setPlanning] = useState(false)
  const [saving, setSaving] = useState(false)
  const [acknowledged, setAcknowledged] = useState(false)
  const [dialogOpen, setDialogOpen] = useState(false)
  const dialogRef = useRef<HTMLDivElement>(null)
  const effectivePlan = plan === undefined ? localPlan : plan
  const updatePlan = (nextPlan: SavedLineupPlan | null) => {
    setLocalPlan(nextPlan)
    onPlanChange?.(nextPlan)
  }
  const updateSaveResult = (nextResult: SavedLineupResult) => {
    setLocalSaveResult(nextResult)
    if (nextResult.saveStatus === 'stale') {
      updatePlan(null)
    }
    onSavedLineupChange?.(nextResult)
  }
  const copy = reviewCopy(matchState)
  const metrics = [
    { label: 'Playlist entries', value: matchState.playlistEntryCount },
    { label: 'Guide channels', value: matchState.guideChannelCount },
    { label: 'Exact matches', value: matchState.matchedCount },
    { label: 'No guide match', value: matchState.unmatchedPlaylistCount },
    { label: 'Needs review', value: matchState.ambiguousCount },
    { label: 'Guide-only', value: matchState.guideOnlyCount },
  ]
  const planReady = matchState.status === 'checked' && effectivePlan?.planStatus === 'ready'

  useEffect(() => {
    if (dialogOpen) dialogRef.current?.focus()
  }, [dialogOpen])

  const handlePrepare = async () => {
    if (matchState.status !== 'checked' || planning) return
    setPlanning(true)
    try {
      updatePlan(await planner())
    } catch {
      updatePlan({
        planStatus: 'blocked',
        playlistEntryCount: null,
        guideChannelCount: null,
        matchedCount: null,
        unmatchedPlaylistCount: null,
        ambiguousCount: null,
        guideOnlyCount: null,
        requiresReview: false,
        acceptedLineupStatus: 'unavailable',
        candidateFreshness: 'unknown',
        acceptedEntryCount: null,
      })
    } finally {
      setPlanning(false)
    }
  }

  const closeDialog = () => {
    setDialogOpen(false)
    setAcknowledged(false)
  }

  const handleSave = async () => {
    if (!planReady || !acknowledged || saving) return
    setDialogOpen(false)
    setSaving(true)
    try {
      const result = await acceptor()
      updateSaveResult(result)
    } catch {
      updateSaveResult(blockedSaveResult())
    } finally {
      setSaving(false)
      setAcknowledged(false)
    }
  }

  const handleDialogKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      closeDialog()
      return
    }
    if (event.key !== 'Tab') return
    const focusable = Array.from(event.currentTarget.querySelectorAll<HTMLElement>('button, input'))
    if (focusable.length === 0) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  return (
    <div className="page-stack">
      <PageHeader
        action={
          <button className="button button-secondary" type="button" onClick={onBack}>
            <ArrowLeft size={17} aria-hidden="true" />
            Return to Guided Setup
          </button>
        }
        description="Understand playlist and guide coverage before preparing or saving a lineup."
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

      <section className="lineup-review-card saved-lineup-action-card" aria-labelledby="lineup-review-save-title">
        <div className="lineup-review-heading">
          <div className="setup-progress-icon" aria-hidden="true">
            <CheckCircle2 size={20} />
          </div>
          <div>
            <p className="eyebrow">Saved lineup</p>
            <h2 id="lineup-review-save-title">Prepare and confirm saving</h2>
          </div>
        </div>
        <p className="lineup-review-note" role="status" aria-live="polite">{planMessage(matchState, effectivePlan, effectiveSaveResult)}</p>
        {planReady ? (
          <div className="saved-lineup-action-row">
            <span className="setup-step-status">Save preview ready</span>
            <button className="button button-primary" type="button" onClick={() => setDialogOpen(true)} disabled={saving}>
              {saving ? 'Saving…' : 'Save lineup'}
            </button>
          </div>
        ) : matchState.status === 'checked' && effectiveSaveResult?.saveStatus !== 'saved' ? (
          <div className="saved-lineup-action-row">
            <span className="setup-step-status">Accepted state is unchanged</span>
            <button className="button button-primary" type="button" onClick={handlePrepare} disabled={planning}>
              {planning ? 'Preparing…' : 'Prepare save preview'}
            </button>
          </div>
        ) : null}
        {effectiveSaveResult?.saveStatus === 'saved' ? (
          <div className="saved-lineup-success" role="status">Saved lineup is available from the Saved lineup navigation item.</div>
        ) : null}
        <p className="lineup-review-note">The preview contains aggregate counts only. The native acceptance boundary owns candidate revalidation, staging, journaling, pointer updates, and recovery.</p>
      </section>

      {dialogOpen ? (
        <div className="saved-lineup-dialog-backdrop" role="presentation">
          <div
            ref={dialogRef}
            className="saved-lineup-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="saved-lineup-dialog-title"
            aria-describedby="saved-lineup-dialog-description"
            tabIndex={-1}
            onKeyDown={handleDialogKeyDown}
          >
            <div className="saved-lineup-dialog-heading">
              <div>
                <p className="eyebrow">Final confirmation</p>
                <h2 id="saved-lineup-dialog-title">Save this lineup?</h2>
              </div>
              <button className="icon-button" type="button" aria-label="Cancel save" onClick={closeDialog}>
                <X size={18} aria-hidden="true" />
              </button>
            </div>
            <p id="saved-lineup-dialog-description">This will ask the native acceptance boundary to revalidate the candidate and accepted parent before changing accepted local state. It will not export, schedule, release, or distribute anything.</p>
            <label className="saved-lineup-acknowledgement">
              <input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} />
              <span>I understand that saving changes the accepted local lineup state.</span>
            </label>
            <div className="saved-lineup-dialog-actions">
              <button className="button button-secondary" type="button" onClick={closeDialog}>Cancel</button>
              <button className="button button-primary" type="button" onClick={handleSave} disabled={!acknowledged || saving}>Save lineup</button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
