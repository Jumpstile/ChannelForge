import { ArrowLeft, ShieldCheck } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StateCard } from '../components/StateCard'
import { stateGalleryFixtures } from '../fixtures/state-gallery'

type StateGalleryPageProps = {
  onBack: () => void
}

export function StateGalleryPage({ onBack }: StateGalleryPageProps) {
  return (
    <div className="page-stack">
      <PageHeader
        action={<span className="gallery-safety-label"><ShieldCheck size={16} aria-hidden="true" /> Synthetic data only</span>}
        description="A deterministic gallery for reviewing every visual state before real operations are connected."
        eyebrow="Development view"
        title="State gallery"
      />
      <div className="gallery-notice">
        <strong>No operations are connected.</strong>
        <span>These examples contain only safe labels, digest placeholders, and synthetic explanations. They never read a workspace or invoke PowerShell.</span>
      </div>
      <section className="state-gallery-grid" aria-label="ChannelForge status states">
        {stateGalleryFixtures.map((state) => <StateCard key={state.id} state={state} />)}
      </section>
      <button className="back-link" type="button" onClick={onBack}><ArrowLeft size={16} aria-hidden="true" /> Return to Workbench</button>
    </div>
  )
}
