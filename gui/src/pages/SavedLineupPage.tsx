import { ArrowLeft, CheckCircle2 } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'

type SavedLineupPageProps = {
  acceptedEntryCount: number | null
  onBack: () => void
}

export function SavedLineupPage({ acceptedEntryCount, onBack }: SavedLineupPageProps) {
  return (
    <div className="page-stack">
      <PageHeader
        action={
          <button className="button button-secondary" type="button" onClick={onBack}>
            <ArrowLeft size={17} aria-hidden="true" />
            Return to lineup review
          </button>
        }
        description="View the current accepted lineup state without editing it in place."
        eyebrow="Saved lineup"
        title="Your saved lineup"
      />

      <StatusBanner status="Success" title="Saved lineup is current">
        <p>The native acceptance boundary confirmed accepted local state.</p>
        <p>This view does not export, schedule, publish, or edit the accepted lineup.</p>
      </StatusBanner>

      <section className="lineup-review-card saved-lineup-card" aria-labelledby="saved-lineup-summary-title">
        <div className="lineup-review-heading">
          <div className="setup-progress-icon" aria-hidden="true">
            <CheckCircle2 size={20} />
          </div>
          <div>
            <p className="eyebrow">Accepted state</p>
            <h2 id="saved-lineup-summary-title">Accepted lineup is available</h2>
          </div>
        </div>
        <div className="lineup-review-grid" aria-label="Saved lineup summary">
          <div className="lineup-review-metric">
            <span>Accepted entries</span>
            <strong>{acceptedEntryCount ?? '—'}</strong>
          </div>
          <div className="lineup-review-metric">
            <span>State</span>
            <strong>Current</strong>
          </div>
        </div>
        <p className="lineup-review-note" role="status" aria-live="polite">
          The accepted lineup is authoritative local state. Source identities, stream URLs, generation IDs, and file paths stay hidden.
        </p>
      </section>
    </div>
  )
}
