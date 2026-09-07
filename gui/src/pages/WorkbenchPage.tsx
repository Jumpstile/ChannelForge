import { ArrowRight, BookOpen, LockKeyhole, Sparkles } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import { StepRail } from '../components/StepRail'
import { TermCoach } from '../components/TermCoach'

type WorkbenchPageProps = {
  onOpenGallery: () => void
}

const workflowSteps = [
  { number: 1, label: 'Sources', state: 'current' as const },
  { number: 2, label: 'Validate', state: 'upcoming' as const },
  { number: 3, label: 'Review', state: 'upcoming' as const },
  { number: 4, label: 'Accepted output', state: 'upcoming' as const },
]

export function WorkbenchPage({ onOpenGallery }: WorkbenchPageProps) {
  return (
    <div className="page-stack">
      <PageHeader
        action={
          <button className="button button-secondary" type="button" onClick={onOpenGallery}>
            <Sparkles size={17} aria-hidden="true" />
            View state gallery
          </button>
        }
        description="A calm place to move from your source files to a lineup you can verify."
        eyebrow="Guided workspace"
        title="Your lineup workbench"
      />

      <StatusBanner status="Not configured" title="Start with the source files you already trust">
        This foundation is ready to guide setup, validation, review, and safe output. No ChannelForge operation runs from this screen yet.
      </StatusBanner>

      <StepRail steps={workflowSteps} />

      <section className="next-action-card" aria-labelledby="next-action-title">
        <div className="next-action-icon" aria-hidden="true"><ArrowRight size={24} /></div>
        <div className="next-action-copy">
          <p className="eyebrow">Your next step</p>
          <h2 id="next-action-title">Connect a provider playlist</h2>
          <p>When the setup workflow is connected, you will choose a local playlist or another supported source. The tracked example files remain untouched.</p>
        </div>
        <button className="button button-primary" disabled type="button">Coming next</button>
      </section>

      <section className="workbench-grid" aria-label="Workspace summary">
        <article className="summary-card">
          <span className="summary-card-label">Sources</span>
          <strong>Not configured</strong>
          <span className="summary-card-detail">Provider and guide inputs</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Candidate lineup</span>
          <strong>Not built</strong>
          <span className="summary-card-detail">A proposal, not accepted authority</span>
        </article>
        <article className="summary-card">
          <span className="summary-card-label">Accepted output</span>
          <strong>Not available</strong>
          <span className="summary-card-detail">Protected until explicit acceptance</span>
        </article>
      </section>

      <section className="workbench-lower-grid">
        <EmptyState title="Nothing needs your attention yet">
          This workspace has no source or candidate evidence to review. That is different from saying every source is healthy.
        </EmptyState>
        <aside className="safety-card" aria-label="Safety boundary">
          <div className="safety-card-heading"><LockKeyhole size={19} aria-hidden="true" /><h2>Safety boundary</h2></div>
          <p>The interface will show a proposal before any accepted lineup changes. Accepted-generation and pointer safety stay in the existing backend.</p>
          <TermCoach term="Candidate lineup" />
          <a href="https://github.com/Jumpstile/ChannelForge" target="_blank" rel="noreferrer"><BookOpen size={15} aria-hidden="true" /> Read the project principles</a>
        </aside>
      </section>
    </div>
  )
}
