import { useState } from 'react'
import { BookOpen, CheckCircle2, FileText, FolderOpen, ListVideo } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import { StepRail } from '../components/StepRail'
import { nativePickerAvailable, chooseSetupItem } from '../app/setupPicker'
import {
  applySetupSelectionResult,
  safePickerMessage,
  setupSelectionStates,
  type SetupPicker,
  type SetupSelectionKind,
} from '../app/setupSelection'

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
  { label: 'Native file-picker bridge', status: 'Works now' },
  { label: 'File selection and validation', status: 'Blocked / needs review' },
  { label: 'Saved lineup', status: 'Planned / not built yet' },
  { label: 'Automatic updates', status: 'Planned / not built yet' },
]

type GuidedSetupPageProps = {
  picker?: SetupPicker
  pickerAvailable?: boolean
}

export function GuidedSetupPage({ picker = chooseSetupItem, pickerAvailable = nativePickerAvailable }: GuidedSetupPageProps = {}) {
  const [selectionStates, setSelectionStates] = useState(setupSelectionStates)
  const [pendingKind, setPendingKind] = useState<SetupSelectionKind | null>(null)
  const [pickerError, setPickerError] = useState<string | null>(null)

  const handleSelect = async (kind: SetupSelectionKind) => {
    setPendingKind(kind)
    setPickerError(null)

    try {
      const result = await picker(kind)
      setSelectionStates((states) => applySetupSelectionResult(states, result))
      setPickerError(safePickerMessage(result))
    } catch {
      setPickerError('Could not complete this selection.')
    } finally {
      setPendingKind(null)
    }
  }

  const workspaceSelected = selectionStates.workspace.status === 'selected'
  const playlistSelected = selectionStates.playlist.status === 'selected'
  const bannerStatus = pickerAvailable ? 'Not checked' : 'Disabled'
  const bannerTitle = pickerAvailable ? 'Selection available' : 'Preview only'
  const bannerMessage = pickerAvailable
    ? 'Native selection is connected. Files are not read, parsed, or validated yet.'
    : 'No workspace, playlist, or guide is selected or checked. These controls do not open files or save changes yet.'
  const progressNote = pickerAvailable
    ? 'This screen opens a native picker but does not read, parse, validate, or store selected files.'
    : 'This screen only displays setup state. It does not open, read, or store files.'

  return (
    <div className="page-stack">
      <PageHeader
        description="Choose a workspace, add your playlist, and add your guide."
        eyebrow="Guided setup"
        title="Set up your workspace"
      />

      <StatusBanner status={bannerStatus} title={bannerTitle}>
        <p>{bannerMessage}</p>
      </StatusBanner>

      {pickerError ? <p className="setup-picker-error" role="alert">{pickerError} Try again.</p> : null}

      <StepRail
        steps={setupSteps.map(({ number, title }) => ({
          number,
          label: title,
          state: number === 1 ? 'current' : 'upcoming',
        }))}
      />

      <section className="setup-step-grid" aria-label="Guided setup steps">
        {setupSteps.map(({ number, title, description, buttonLabel, selectionKind, icon: Icon }) => {
          const selection = selectionStates[selectionKind]
          const canSelect = pickerAvailable
            && (selectionKind === 'workspace' || (selectionKind === 'playlist' && workspaceSelected) || (selectionKind === 'guide' && workspaceSelected && playlistSelected))
          const isPending = pendingKind === selectionKind

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
                <span className="setup-step-status">{pickerAvailable ? 'Selection enabled' : 'Preview only'}</span>
                <button
                  aria-busy={isPending}
                  className="button button-secondary"
                  disabled={!canSelect || pendingKind !== null}
                  type="button"
                  onClick={() => void handleSelect(selectionKind)}
                >
                  {isPending ? 'Choosing…' : buttonLabel}
                </button>
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
        <p className="setup-progress-note"><BookOpen size={15} aria-hidden="true" /> {progressNote}</p>
      </section>
    </div>
  )
}
