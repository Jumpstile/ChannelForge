import { useEffect, useState } from 'react'
import { StatusBanner } from './StatusBanner'
import { ErrorNotice } from './ErrorNotice'
import { failureKindOf, isLoadFailure, loadFailedMessage, type FriendlyMessage, type LoadFailureKind } from '../app/friendlyError'
import { fetchWebStatus, refreshSavedSources, removeSavedSource, type SourceRefreshAction, type SourceRemoveAction, type SourceRow, type WebStatusFetcher, type WebStatusSnapshot } from '../app/webStatus'

const refreshFailedMessage: FriendlyMessage = {
  headline: 'ChannelForge could not check your sources',
  whatHappened: 'ChannelForge could not check your saved sources, and could not tell why. Your accepted lineup was not changed.',
  whatToDo: 'Press Refresh now to try again. If it keeps happening, make sure ChannelForge is still running or open Details.',
  details: { code: 'source-refresh-failed', cause: 'The request to refresh the saved sources failed or the answer could not be read.' },
}

// Browser time zone, labeled. An unreadable value is treated as not reported.
function formatLocalTime(value: string | null | undefined): string | null {
  if (!value) return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'long' })
}

type DashboardState = 'loading' | 'ready' | 'unavailable'

type StatusDashboardProps = {
  fetchStatus?: WebStatusFetcher
  refreshSources?: SourceRefreshAction
  removeSource?: SourceRemoveAction
  onReplaceSources?: () => void
  onSnapshotChange?: (snapshot: WebStatusSnapshot | null) => void
}

function sourceStatusLabel(status: WebStatusSnapshot['sourcesStatus']): string {
  switch (status) {
    case 'saved': return 'Sources saved'
    case 'up-to-date': return 'Up to date'
    case 'changes-found': return 'Changes found'
    case 'source-unavailable': return 'Source unavailable'
    case 'needs-attention': return 'Needs attention'
    default: return 'Sources not saved'
  }
}

function detailLabel(status: WebStatusSnapshot['playlistStatus'] | WebStatusSnapshot['guideStatus']): string {
  switch (status) {
    case 'ready': return 'Ready'
    case 'no-guide': return 'No guide selected'
    case 'changes-found': return 'Changes found'
    case 'source-unavailable': return 'Source unavailable'
    case 'needs-attention': return 'Needs attention'
    default: return 'Not saved'
  }
}

function sourceRowState(state: SourceRow['state']): string {
  switch (state) {
    case 'ready': return 'Up to date'
    case 'changes-found': return 'Changes found. Refresh, then review before replacing sources.'
    case 'source-unavailable': return 'Needs attention: this source could not be read. Your last saved copy is kept.'
    default: return 'Not refreshed yet'
  }
}

export function StatusDashboard({
  fetchStatus = fetchWebStatus,
  refreshSources = refreshSavedSources,
  removeSource = removeSavedSource,
  onReplaceSources,
  onSnapshotChange,
}: StatusDashboardProps) {
  const [state, setState] = useState<DashboardState>('loading')
  const [snapshot, setSnapshot] = useState<WebStatusSnapshot | null>(null)
  const [failure, setFailure] = useState<LoadFailureKind>('unknown')
  const [refreshing, setRefreshing] = useState(false)
  const [refreshMessage, setRefreshMessage] = useState<string | null>(null)
  const [confirming, setConfirming] = useState<number | null>(null)
  const [removing, setRemoving] = useState(false)
  const [removeMessage, setRemoveMessage] = useState<string | null>(null)
  const [actionError, setActionError] = useState<FriendlyMessage | null>(null)

  useEffect(() => {
    let mounted = true
    void fetchStatus()
      .then((next) => {
        if (!mounted) return
        if (next === null || isLoadFailure(next)) {
          setFailure(failureKindOf(next))
          onSnapshotChange?.(null)
          setState('unavailable')
          return
        }
        setSnapshot(next)
        onSnapshotChange?.(next)
        setState('ready')
      })
      .catch(() => {
        if (mounted) {
          onSnapshotChange?.(null)
          setState('unavailable')
        }
      })
    return () => {
      mounted = false
    }
  }, [fetchStatus, onSnapshotChange])

  async function handleRefresh() {
    setRefreshing(true)
    setRefreshMessage(null)
    setActionError(null)
    const result = await refreshSources()
    if (result === null) {
      setActionError(refreshFailedMessage)
      setRefreshing(false)
      return
    }
    setRefreshMessage(result.status === 'UP_TO_DATE' ? 'Sources are up to date.' : 'Changes found. Review before replacing sources.')
    const next = await fetchStatus()
    if (next !== null && !isLoadFailure(next)) {
      setSnapshot(next)
      onSnapshotChange?.(next)
    }
    setRefreshing(false)
  }

  async function handleRemove(source: SourceRow) {
    setRemoving(true)
    setActionError(null)
    setRemoveMessage(null)
    const result = await removeSource(source)
    setRemoving(false)
    setConfirming(null)
    if ('message' in result) {
      setActionError(result.message)
      return
    }
    setRemoveMessage(`Removed "${source.label}". Your other sources were not changed.`)
    const next = await fetchStatus()
    if (next !== null && !isLoadFailure(next)) {
      setSnapshot(next)
      onSnapshotChange?.(next)
    }
  }

  if (state === 'loading') {
    return (
      <StatusBanner status="Not checked" title="Checking ChannelForge status">
        <p>Checking whether ChannelForge is ready.</p>
        <p><strong>This page only shows information.</strong> It cannot change your lineup yet.</p>
      </StatusBanner>
    )
  }

  if (state === 'unavailable' || snapshot === null) {
    return (
      <StatusBanner status="Warning" title="ChannelForge status is unavailable">
        <ErrorNotice message={loadFailedMessage('the status', 'status-unavailable', 'Start ChannelForge if it is closed, then reload this page.', failure)} />
        <p><strong>This page only shows information.</strong> It cannot change your lineup yet.</p>
      </StatusBanner>
    )
  }

  const sourcesStatus = snapshot.sourcesStatus ?? 'not-enrolled'
  const playlistStatus = snapshot.playlistStatus ?? 'not-enrolled'
  const guideStatus = snapshot.guideStatus ?? 'no-guide'
  const canRefresh = snapshot.canRefreshSources === true
  const lastChecked = formatLocalTime(snapshot.lastCheckedUtc) ?? 'Not checked yet'
  const snapshotTime = formatLocalTime(snapshot.snapshotUtc) ?? 'Not reported yet'
  const coverageStart = formatLocalTime(snapshot.coverageStartUtc)
  const coverageEnd = formatLocalTime(snapshot.coverageEndUtc)
  const coverage = coverageStart && coverageEnd ? `${coverageStart} to ${coverageEnd}` : 'Not reported yet'

  return (
    <>
      <StatusBanner status="Ready" title="ChannelForge is running">
        <p>{snapshot.lineupAccepted ? 'An accepted lineup is available.' : 'No lineup has been accepted yet.'}</p>
        <p>{snapshot.lineupAccepted ? 'Open Guided Setup to review.' : 'Open Guided Setup to begin.'}</p>
        <p><strong>Your accepted lineup is not changed here.</strong> You can check saved sources and remove one you no longer want.</p>
      </StatusBanner>
      <section className="workbench-grid" aria-label="Saved source status">
        <article className="summary-card">
          <span className="summary-card-label">Sources</span>
          <strong>{sourceStatusLabel(sourcesStatus)}</strong>
          <span className="summary-card-detail">{snapshot.sourcesGuidance ?? 'Your saved playlist stays on this computer.'}</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Playlist</span>
          <strong>{detailLabel(playlistStatus)}</strong>
          <span className="summary-card-detail">Saved on this computer</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Guide</span>
          <strong>{detailLabel(guideStatus)}</strong>
          <span className="summary-card-detail">Optional guide</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Last checked</span>
          <strong>{lastChecked}</strong>
          <span className="summary-card-detail">{refreshMessage ?? 'Refresh checks whether your saved files have changed.'}</span>
        </article>
      </section>
      <section className="workbench-grid" aria-label="Guide freshness">
        <article className="summary-card">
          <span className="summary-card-label">Snapshot time</span>
          <strong>{snapshotTime}</strong>
          <span className="summary-card-detail">When your accepted lineup was saved. Shown in your browser time zone.</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Coverage window</span>
          <strong>{coverage}</strong>
          <span className="summary-card-detail">The period the guide data covers. Shown in your browser time zone.</span>
        </article>
      </section>
      {snapshot.sources && snapshot.sources.length > 0 ? (
        <section className="workbench-grid" aria-label="Status of each saved source">
          {snapshot.sources.map((source, index) => (
            <article className="summary-card" key={`${source.kind}-${index}`}>
              <span className="summary-card-label">{source.kind === 'guide' ? 'Guide' : 'Playlist'}</span>
              <strong>{source.label}</strong>
              <span className="summary-card-detail">{sourceRowState(source.state)}</span>
              {confirming === index ? (
                <div role="group" aria-label={`Remove ${source.label}`}>
                  <p>Remove "{source.label}" from ChannelForge? Your other sources stay as they are. Your own file is not deleted.</p>
                  <button className="button button-primary" type="button" onClick={() => void handleRemove(source)} disabled={removing}>
                    {removing ? 'Removing…' : 'Yes, remove this source'}
                  </button>
                  <button className="button button-secondary" type="button" onClick={() => setConfirming(null)} disabled={removing}>Keep this source</button>
                </div>
              ) : (
                <button className="button button-secondary" type="button" onClick={() => { setRemoveMessage(null); setActionError(null); setConfirming(index) }} disabled={removing}>
                  {`Remove ${source.label}`}
                </button>
              )}
            </article>
          ))}
        </section>
      ) : null}
      <div className="next-action-card">
        <div className="next-action-copy">
          <p className="eyebrow">Saved sources</p>
          <h2>{refreshMessage ?? sourceStatusLabel(sourcesStatus)}</h2>
          <p>Refreshing never replaces your accepted lineup automatically.</p>
          {removeMessage ? <p role="status">{removeMessage}</p> : null}
          {actionError ? <ErrorNotice message={actionError} /> : null}
        </div>
        <div className="next-action-buttons">
          <button className="button button-primary" type="button" onClick={() => void handleRefresh()} disabled={!canRefresh || refreshing}>
            {refreshing ? 'Refreshing…' : 'Refresh now'}
          </button>
          {onReplaceSources ? <button className="button button-secondary" type="button" onClick={onReplaceSources}>Replace sources</button> : null}
        </div>
      </div>
    </>
  )
}
