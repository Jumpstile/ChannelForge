import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { CheckCircle2, X } from 'lucide-react'
import { acceptSavedLineup, prepareSavedLineupPlan } from '../app/setupPicker'
import { TermCoach } from '../components/TermCoach'
import { PageHeader } from '../components/PageHeader'
import { ErrorNotice } from '../components/ErrorNotice'
import { StatusBanner } from '../components/StatusBanner'
import type { FriendlyMessage } from '../app/friendlyError'
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
  const count = value ?? 0
  return `${count} ${noun}${count === 1 ? '' : 's'}`
}

function reviewCopy(state: PlaylistGuideMatchState): ReviewCopy {
  if (state.status === 'checked') {
    return {
      bannerStatus: bannerStatuses.checked,
      title: 'Every channel has a guide match',
      message: 'Every playlist channel matches exactly one guide channel. Nothing has been saved yet.',
      detail: 'You can now prepare a preview of your lineup.',
    }
  }
  if (state.status === 'needs-attention') {
    const notices: string[] = []
    if ((state.unmatchedPlaylistCount ?? 0) > 0) {
      notices.push(`${countLabel(state.unmatchedPlaylistCount, 'playlist channel')} with no guide`)
    }
    if ((state.guideOnlyCount ?? 0) > 0) {
      notices.push(`${countLabel(state.guideOnlyCount, 'guide channel')} not in your playlist`)
    }
    return {
      bannerStatus: bannerStatuses['needs-attention'],
      title: 'Some channels need attention',
      message: `Found ${notices.join(' and ')}. Look at the counts below before you save.`,
      detail: 'Saving is turned off until these counts are sorted out.',
    }
  }
  if (state.status === 'review-needed') {
    return {
      bannerStatus: bannerStatuses['review-needed'],
      title: 'Some channels need your review',
      message: `${countLabel(state.ambiguousCount, 'playlist channel')} could match more than one guide channel.`,
      detail: 'ChannelForge did not pick one for you. Saving is turned off until this is sorted out.',
    }
  }
  if (state.status === 'checking') {
    return {
      bannerStatus: bannerStatuses.checking,
      title: 'Checking your files',
      message: 'ChannelForge is comparing your playlist and guide. Nothing is being changed.',
      detail: 'The counts will show up here when it finishes.',
    }
  }
  if (state.status === 'blocked') {
    return {
      bannerStatus: bannerStatuses.blocked,
      title: 'The check could not finish',
      message: 'ChannelForge could not compare your playlist and guide. A file may have changed or become unreadable since it was checked, or the last result is out of date.',
      detail: 'Go back to Guided Setup and check both files again.',
    }
  }
  return {
    bannerStatus: bannerStatuses['not-checked'],
    title: 'Not ready yet',
    message: 'Check your playlist and guide first.',
    detail: 'This page shows counts only. It does not show your channel details.',
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

function planNotice(plan: SavedLineupPlan | null, saveResult: SavedLineupResult | null): FriendlyMessage | null {
  if (saveResult?.saveStatus === 'stale') {
    return {
      headline: 'Your lineup was not saved',
      whatHappened: 'Your files changed while you were working, so ChannelForge stopped. Nothing was saved.',
      whatToDo: 'Check your files again, then prepare a new preview.',
      details: { code: saveResult.reasonCode ?? 'stale-candidate', cause: 'The candidate or the saved lineup changed after the preview was made.' },
    }
  }
  if (saveResult?.saveStatus === 'blocked') {
    return {
      headline: 'Your lineup was not saved',
      whatHappened: 'Something stopped the save. Your saved lineup was not changed.',
      whatToDo: 'Try again. If it keeps happening, open Details and share it when you ask for help.',
      details: { code: saveResult.reasonCode ?? 'acceptance-failed', cause: 'The save step refused or failed. The existing saved lineup was left as it was.' },
    }
  }
  if (plan?.planStatus === 'stale') {
    return {
      headline: 'The preview is out of date',
      whatHappened: 'Your files changed after the preview was made. Nothing was saved.',
      whatToDo: 'Prepare a new preview.',
      details: { code: 'stale-candidate', cause: 'The candidate changed after the preview was made.' },
    }
  }
  if (plan?.planStatus === 'blocked') {
    return {
      headline: 'ChannelForge could not prepare the preview',
      whatHappened: 'The preview stopped before it gave a result, and ChannelForge could not tell why. Your saved lineup was not changed.',
      whatToDo: 'Press Prepare save preview to try again. If it keeps happening, open Details and share it when you ask for help.',
      details: { code: 'preview-unavailable', cause: 'The save preview step refused or failed before it gave a result.' },
    }
  }
  return null
}

function planMessage(matchState: PlaylistGuideMatchState, plan: SavedLineupPlan | null, saveResult: SavedLineupResult | null): string {
  if (saveResult?.saveStatus === 'saved') {
    return 'Your lineup is saved. You can open it from Saved lineup.'
  }
  if (matchState.status !== 'checked') {
    return 'You can save only after every playlist channel has an exact guide match.'
  }
  if (plan?.planStatus === 'ready') {
    return 'This is only a preview. Nothing has changed, and your current saved lineup stays as it is.'
  }
  return 'Prepare a preview first. Nothing is saved until you confirm.'
}

export function LineupReviewPage({
  matchState,
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
  const notice = planNotice(effectivePlan, effectiveSaveResult)
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
        description="See how well your playlist and guide fit together before you save a lineup."
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
        <p className="lineup-review-note">Matched means a playlist channel lines up with exactly one guide channel. <TermCoach term="channel-id" />s, program titles, <TermCoach term="stream-url" label="stream URL" />s, and file details are not shown here.</p>
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
        {notice ? <ErrorNotice message={notice} /> : <p className="lineup-review-note" role="status" aria-live="polite">{planMessage(matchState, effectivePlan, effectiveSaveResult)}</p>}
        {planReady ? (
          <div className="saved-lineup-action-row">
            <span className="setup-step-status">Save preview ready</span>
            <button className="button button-primary" type="button" onClick={() => setDialogOpen(true)} disabled={saving}>
              {saving ? 'Saving…' : 'Save lineup'}
            </button>
          </div>
        ) : matchState.status === 'checked' && effectiveSaveResult?.saveStatus !== 'saved' ? (
          <div className="saved-lineup-action-row">
            <span className="setup-step-status">Your saved lineup is unchanged</span>
            <button className="button button-primary" type="button" onClick={handlePrepare} disabled={planning}>
              {planning ? 'Preparing…' : 'Prepare save preview'}
            </button>
          </div>
        ) : null}
        {effectiveSaveResult?.saveStatus === 'saved' ? (
          <div className="saved-lineup-success" role="status">Your lineup is saved. Open Saved lineup in the menu to see it.</div>
        ) : null}
        <p className="lineup-review-note">The preview shows counts only. When you save, ChannelForge checks everything one last time before it changes your saved lineup.</p>
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
            <p id="saved-lineup-dialog-description">ChannelForge will check your files one more time, then save this lineup on this computer. It will not export, schedule, publish, or share anything.</p>
            <label className="saved-lineup-acknowledgement">
              <input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} />
              <span>I understand that saving replaces my saved lineup.</span>
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
