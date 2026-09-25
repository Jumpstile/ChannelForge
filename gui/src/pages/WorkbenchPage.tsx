import { ArrowRight, BookOpen, LockKeyhole, Sparkles } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { StatusDashboard } from '../components/StatusDashboard'
import { StepRail } from '../components/StepRail'
import { fetchWebStatus, type WebStatusFetcher } from '../app/webStatus'

type WorkbenchPageProps = {
  onOpenGallery: () => void
  onOpenSetup: () => void
  fetchStatus?: WebStatusFetcher
}

const workflowSteps = [
  { number: 1, label: 'Playlist', state: 'current' as const },
  { number: 2, label: 'Guide', state: 'upcoming' as const },
  { number: 3, label: 'Review', state: 'upcoming' as const },
  { number: 4, label: 'Saved lineup', state: 'upcoming' as const },
]

export function WorkbenchPage({ onOpenGallery, onOpenSetup, fetchStatus = fetchWebStatus }: WorkbenchPageProps) {
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

      <StatusDashboard fetchStatus={fetchStatus} onReplaceSources={onOpenSetup} />

      <StepRail steps={workflowSteps} />

      <section className="next-action-card" aria-labelledby="next-action-title">
        <div className="next-action-icon" aria-hidden="true"><ArrowRight size={24} /></div>
        <div className="next-action-copy">
          <p className="eyebrow">Your next step</p>
          <h2 id="next-action-title">Add playlists and optional guides</h2>
          <p>Open Guided Setup to add one or more playlists and optional XMLTV guides. Your review stays in ChannelForge's server-owned workspace. Choose which playlists each guide covers.</p>
        </div>
        <button className="button button-primary" type="button" onClick={onOpenSetup}>Open Guided Setup</button>
      </section>

      <section className="workbench-grid" aria-label="Workspace summary">
        <article className="summary-card">
          <span className="summary-card-label">Playlists and guides</span>
          <strong>Not configured</strong>
          <span className="summary-card-detail">M3U playlists and optional XMLTV guides</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Lineup</span>
          <strong>Not built</strong>
          <span className="summary-card-detail">Not accepted yet</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Saved lineup</span>
          <strong>Not available</strong>
          <span className="summary-card-detail">Nothing has been accepted yet</span>
        </article>
      </section>

      <section className="workbench-lower-grid">
        <EmptyState title="Nothing to review yet">
          There is nothing to review yet because no playlist or guide has been added.
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
