import { useEffect, useState } from 'react'
import { StatusBanner } from './StatusBanner'
import { fetchWebStatus, refreshSavedSources, type SourceRefreshAction, type WebStatusFetcher, type WebStatusSnapshot } from '../app/webStatus'

type DashboardState = 'loading' | 'ready' | 'unavailable'

type StatusDashboardProps = {
  fetchStatus?: WebStatusFetcher
  refreshSources?: SourceRefreshAction
  onReplaceSources?: () => void
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

export function StatusDashboard({
  fetchStatus = fetchWebStatus,
  refreshSources = refreshSavedSources,
  onReplaceSources,
}: StatusDashboardProps) {
  const [state, setState] = useState<DashboardState>('loading')
  const [snapshot, setSnapshot] = useState<WebStatusSnapshot | null>(null)
  const [refreshing, setRefreshing] = useState(false)
  const [refreshMessage, setRefreshMessage] = useState<string | null>(null)

  useEffect(() => {
    let mounted = true
    void fetchStatus()
      .then((next) => {
        if (!mounted) return
        if (next === null) {
          setState('unavailable')
          return
        }
        setSnapshot(next)
        setState('ready')
      })
      .catch(() => {
        if (mounted) setState('unavailable')
      })
    return () => {
      mounted = false
    }
  }, [fetchStatus])

  async function handleRefresh() {
    setRefreshing(true)
    setRefreshMessage(null)
    const result = await refreshSources()
    if (result === null) {
      setRefreshMessage('Refresh could not complete safely. Your accepted lineup was not changed.')
      setRefreshing(false)
      return
    }
    setRefreshMessage(result.status === 'UP_TO_DATE' ? 'Sources are up to date.' : 'Changes found. Review before replacing sources.')
    const next = await fetchStatus()
    if (next !== null) setSnapshot(next)
    setRefreshing(false)
  }

  if (state === 'loading') {
    return (
      <StatusBanner status="Not checked" title="Checking ChannelForge status">
        <p>Checking whether your local ChannelForge server is ready.</p>
        <p><strong>Read-only status.</strong> This page can show status, but it cannot change your lineup yet.</p>
      </StatusBanner>
    )
  }

  if (state === 'unavailable' || snapshot === null) {
    return (
      <StatusBanner status="Warning" title="ChannelForge status is unavailable">
        <p>We could not read the local server status. Check that ChannelForge is running, then refresh this page.</p>
        <p><strong>Read-only status.</strong> This page can show status, but it cannot change your lineup yet.</p>
      </StatusBanner>
    )
  }

  const sourcesStatus = snapshot.sourcesStatus ?? 'not-enrolled'
  const playlistStatus = snapshot.playlistStatus ?? 'not-enrolled'
  const guideStatus = snapshot.guideStatus ?? 'no-guide'
  const canRefresh = snapshot.canRefreshSources === true
  const lastChecked = snapshot.lastCheckedUtc ? new Date(snapshot.lastCheckedUtc).toLocaleString() : 'Not checked yet'

  return (
    <>
      <StatusBanner status="Ready" title="ChannelForge is running">
        <p>{snapshot.lineupAccepted ? 'An accepted lineup is available.' : 'No lineup has been accepted yet.'}</p>
        <p>{snapshot.lineupAccepted ? 'Open Guided Setup to review.' : 'Open Guided Setup to begin.'}</p>
        <p><strong>Read-only status.</strong> This page can show status, but it cannot change your lineup yet.</p>
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
          <span className="summary-card-detail">Server-owned saved source</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Guide</span>
          <strong>{detailLabel(guideStatus)}</strong>
          <span className="summary-card-detail">Optional XMLTV guide</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Last checked</span>
          <strong>{lastChecked}</strong>
          <span className="summary-card-detail">{refreshMessage ?? 'Refresh checks for changed source bytes.'}</span>
        </article>
      </section>
      <div className="next-action-card">
        <div className="next-action-copy">
          <p className="eyebrow">Saved sources</p>
          <h2>{refreshMessage ?? sourceStatusLabel(sourcesStatus)}</h2>
          <p>Refreshing never replaces your accepted lineup automatically.</p>
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
