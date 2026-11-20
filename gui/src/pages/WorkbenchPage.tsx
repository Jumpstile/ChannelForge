import { useState } from 'react'
import { ArrowRight, BookOpen, LockKeyhole, Sparkles } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { StatusDashboard } from '../components/StatusDashboard'
import { StepRail } from '../components/StepRail'
import { fetchWebStatus, type WebStatusFetcher, type WebStatusSnapshot } from '../app/webStatus'

type WorkbenchPageProps = {
  onOpenGallery: () => void
  onOpenSetup: () => void
  fetchStatus?: WebStatusFetcher
}

export function WorkbenchPage({ onOpenGallery, onOpenSetup, fetchStatus = fetchWebStatus }: WorkbenchPageProps) {
  const [snapshot, setSnapshot] = useState<WebStatusSnapshot | null | undefined>(undefined)
  const statusPending = snapshot === undefined
  const statusUnavailable = snapshot === null
  const lineupAccepted = snapshot?.lineupAccepted === true
  const sourceSetConfigured = lineupAccepted || (
    snapshot !== null &&
    snapshot !== undefined &&
    snapshot.sourcesStatus !== undefined &&
    snapshot.sourcesStatus !== 'not-enrolled'
  )
  const workflowSteps = lineupAccepted
    ? [
        { number: 1, label: 'Playlist', state: 'complete' as const },
        { number: 2, label: 'Guide', state: 'complete' as const },
        { number: 3, label: 'Review', state: 'complete' as const },
        { number: 4, label: 'Saved lineup', state: 'complete' as const },
      ]
    : [
        { number: 1, label: 'Playlist', state: 'current' as const },
        { number: 2, label: 'Guide', state: 'upcoming' as const },
        { number: 3, label: 'Review', state: 'upcoming' as const },
        { number: 4, label: 'Saved lineup', state: 'upcoming' as const },
      ]

  return (
    <div className="page-stack">
      <PageHeader
        action={
          <button className="button button-secondary" type="button" onClick={onOpenGallery}>
            <Sparkles size={17} aria-hidden="true" />
            View state gallery
          </button>
        }
        description="Build a TV lineup from one or more playlists and optional XMLTV guides."
        eyebrow="Guided workspace"
        title="Your lineup workbench"
      />

      <StatusDashboard fetchStatus={fetchStatus} onReplaceSources={onOpenSetup} onSnapshotChange={setSnapshot} />

      <StepRail steps={workflowSteps} />

      <section className="next-action-card" aria-labelledby="next-action-title">
        <div className="next-action-icon" aria-hidden="true"><ArrowRight size={24} /></div>
        <div className="next-action-copy">
          <p className="eyebrow">Your next step</p>
          <h2 id="next-action-title">Open Guided Setup</h2>
          <p>Add, review, or replace one or more playlists and optional XMLTV guides. Your review stays in ChannelForge's server-owned workspace. Choose which playlists each guide covers.</p>
        </div>
        <button className="button button-primary" type="button" onClick={onOpenSetup}>Open Guided Setup</button>
      </section>

      <section className="workbench-grid" aria-label="Workspace summary">
        <article className="summary-card">
          <span className="summary-card-label">Playlists and guides</span>
          <strong>{statusPending ? 'Checking' : statusUnavailable ? 'Unavailable' : sourceSetConfigured ? 'Saved' : 'Not configured'}</strong>
          <span className="summary-card-detail">
            {statusPending
              ? 'Waiting for ChannelForge status'
              : statusUnavailable
                ? 'ChannelForge status unavailable'
                : sourceSetConfigured
                  ? 'Saved source configuration is available'
                  : 'M3U playlists and optional XMLTV guides'}
          </span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Lineup</span>
          <strong>{statusPending ? 'Checking' : statusUnavailable ? 'Unavailable' : lineupAccepted ? 'Accepted' : 'Not built'}</strong>
          <span className="summary-card-detail">
            {statusPending ? 'Waiting for ChannelForge status' : statusUnavailable ? 'ChannelForge status unavailable' : lineupAccepted ? 'Your accepted lineup is available' : 'Not accepted yet'}
          </span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Saved lineup</span>
          <strong>{statusPending ? 'Checking' : statusUnavailable ? 'Unavailable' : lineupAccepted ? 'Available' : 'Not available'}</strong>
          <span className="summary-card-detail">
            {statusPending ? 'Waiting for ChannelForge status' : statusUnavailable ? 'ChannelForge status unavailable' : lineupAccepted ? 'Ready to review' : 'Nothing has been accepted yet'}
          </span>
        </article>
      </section>

      <section className="workbench-lower-grid">
        <EmptyState title={statusPending ? 'Checking workspace' : statusUnavailable ? 'Status unavailable' : lineupAccepted ? 'Saved lineup ready' : 'Nothing to review yet'}>
          {statusPending
            ? 'Waiting for ChannelForge to report the current workspace state.'
            : statusUnavailable
              ? 'ChannelForge could not report the current workspace state. Check that the local server is running.'
              : lineupAccepted
                ? 'Your accepted lineup is available. Open Guided Setup to review or replace sources.'
                : 'There is nothing to review yet because no playlist or guide has been added.'}
        </EmptyState>
        <aside className="safety-card" aria-label="Safety boundary">
          <div className="safety-card-heading"><LockKeyhole size={19} aria-hidden="true" /><h2>Before you save</h2></div>
          <p>ChannelForge will show you changes before saving them.</p>
          <a href="https://github.com/Jumpstile/ChannelForge" target="_blank" rel="noreferrer"><BookOpen size={15} aria-hidden="true" /> Read the project principles</a>
        </aside>
      </section>
    </div>
  )
}
