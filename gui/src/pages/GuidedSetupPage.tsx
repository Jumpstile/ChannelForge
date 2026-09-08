import { BookOpen, CheckCircle2, FileText, FolderOpen, ListVideo } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import { StepRail } from '../components/StepRail'
import { setupSelectionStates } from '../app/setupSelection'

const setupSteps = [
  {
    number: 1,
    title: 'Choose workspace',
    description: 'Choose where ChannelForge keeps your lineup work.',
    buttonLabel: 'Choose workspace',
    selectionKind: 'workspace' as const,
    icon: FolderOpen,
  },
  {
    number: 2,
    title: 'Add playlist',
    description: 'Your playlist tells ChannelForge what channels you have.',
    buttonLabel: 'Add playlist',
    selectionKind: 'playlist' as const,
    icon: ListVideo,
  },
  {
    number: 3,
    title: 'Add guide',
    description: 'Your guide tells ChannelForge what is on those channels.',
    buttonLabel: 'Add guide',
    selectionKind: 'guide' as const,
    icon: FileText,
  },
]

const setupProgress = [
  { label: 'Workbench', status: 'Works now' },
  { label: 'Guided Setup layout', status: 'Preview only' },
  { label: 'Display-safe selection status', status: 'Works now' },
  { label: 'File selection and validation', status: 'Blocked / needs review' },
  { label: 'Saved lineup', status: 'Planned / not built yet' },
  { label: 'Automatic updates', status: 'Planned / not built yet' },
]

export function GuidedSetupPage() {
  return (
    <div className="page-stack">
      <PageHeader
        description="Choose a workspace, add your playlist, and add your guide."
        eyebrow="Guided setup"
        title="Set up your workspace"
      />

      <StatusBanner status="Disabled" title="Preview only">
        <p>No workspace, playlist, or guide is selected or checked. These controls do not open files or save changes yet.</p>
      </StatusBanner>

      <StepRail
        steps={setupSteps.map(({ number, title }) => ({
          number,
          label: title,
          state: number === 1 ? 'current' : 'upcoming',
        }))}
      />

      <section className="setup-step-grid" aria-label="Guided setup steps">
        {setupSteps.map(({ number, title, description, buttonLabel, selectionKind, icon: Icon }) => {
          const selection = setupSelectionStates[selectionKind]

          return (
            <article className="setup-step-card" key={title}>
              <div className="setup-step-heading">
                <div className="setup-step-icon" aria-hidden="true"><Icon size={22} /></div>
                <div>
                  <p className="setup-step-number">Step {number}</p>
                  <h2>{title}</h2>
                </div>
              </div>
              <p className="setup-step-description">{description}</p>
              <div className="setup-step-selection" role="status" aria-label={`${title} selection status`}>
                <div className="setup-step-selection-row">
                  <span className="setup-step-selection-label">Selection</span>
                  <strong>{selection.displayLabel}</strong>
                </div>
                <div className="setup-step-selection-row">
                  <span className="setup-step-selection-label">Validation</span>
                  <strong>{selection.validationLabel}</strong>
                </div>
                <span>{selection.detail}</span>
              </div>
              <div className="setup-step-footer">
                <span className="setup-step-status">Preview only</span>
                <button className="button button-secondary" disabled type="button">{buttonLabel}</button>
              </div>
            </article>
          )
        })}
      </section>

      <section className="setup-progress-card" aria-labelledby="setup-progress-title">
        <div className="setup-progress-heading">
          <div className="setup-progress-icon" aria-hidden="true"><CheckCircle2 size={20} /></div>
          <div>
            <p className="eyebrow">Running tally</p>
            <h2 id="setup-progress-title">What works today</h2>
          </div>
        </div>
        <ul className="setup-progress-list">
          {setupProgress.map(({ label, status }) => (
            <li key={label}>
              <span>{label}</span>
              <strong>{status}</strong>
            </li>
          ))}
        </ul>
        <p className="setup-progress-note"><BookOpen size={15} aria-hidden="true" /> This screen only displays setup state. It does not open, read, or store files.</p>
      </section>
    </div>
  )
}
