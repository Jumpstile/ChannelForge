import { CheckCircle2 } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'

type SavedLineupPageProps = {
  acceptedEntryCount: number | null
}

export function SavedLineupPage({ acceptedEntryCount }: SavedLineupPageProps) {
  return (
    <div className="page-stack">
      <PageHeader
        description="Look at your saved lineup. You cannot change it on this page."
        eyebrow="Saved lineup"
        title="Your saved lineup"
      />

      <StatusBanner status="Success" title="Saved lineup is current">
        <p>ChannelForge checked and saved your lineup on this computer.</p>
        <p>This page only shows it. It does not export, schedule, publish, or change your lineup.</p>
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
          This is the lineup ChannelForge saved on this computer. Stream URLs and file locations are not shown here.
        </p>
      </section>
    </div>
  )
}
