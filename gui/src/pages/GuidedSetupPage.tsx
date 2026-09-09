import { useRef, useState } from 'react'
import { BookOpen, CheckCircle2, FileText, FolderOpen, ListVideo } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import { StepRail } from '../components/StepRail'
import { nativePickerAvailable, chooseSetupItem, checkPlaylistGuideMatch } from '../app/setupPicker'
import {
  applySetupSelectionResult,
  createInitialGuideContentState,
  createInitialPlaylistContentState,
  createInitialPlaylistGuideMatchState,
  guideContentStateFromResult,
  playlistContentStateFromResult,
  playlistGuideMatchStateFromResult,
  safeMatchMessage,
  safePickerMessage,
  setGuideContentChecking,
  setPlaylistContentChecking,
  setPlaylistGuideMatchChecking,
  setSetupSelectionChecking,
  setupSelectionStates,
  isPlaylistGuideReviewAvailable,
  type PlaylistGuideMatchState,
  type SetupMatcher,
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
  { label: 'Pre-parse selection checks', status: 'Works now' },
  {
    label: 'Playlist structural content validation',
    status: 'Works now — structural only',
  },
  {
    label: 'Guide structural content validation',
    status: 'Works now — structural only',
  },
  {
    label: 'Playlist/guide exact matching',
    status: 'Implemented — local checks passed',
  },
  { label: 'Saved lineup', status: 'Implemented — explicit confirmation required' },
  { label: 'Automatic updates', status: 'Planned / not built yet' },
]

type GuidedSetupPageProps = {
  picker?: SetupPicker
  matcher?: SetupMatcher
  pickerAvailable?: boolean
  matchState?: PlaylistGuideMatchState
  onMatchStateChange?: (state: PlaylistGuideMatchState) => void
  onOpenReview?: () => void
}

export function GuidedSetupPage({
  picker = chooseSetupItem,
  matcher = checkPlaylistGuideMatch,
  pickerAvailable = nativePickerAvailable,
  matchState: externalMatchState,
  onMatchStateChange,
  onOpenReview,
}: GuidedSetupPageProps = {}) {
  const [selectionStates, setSelectionStates] = useState(setupSelectionStates)
  const [playlistContent, setPlaylistContent] = useState(createInitialPlaylistContentState)
  const [guideContent, setGuideContent] = useState(createInitialGuideContentState)
  const [localMatchState, setLocalMatchState] = useState(createInitialPlaylistGuideMatchState)
  const matchState = externalMatchState ?? localMatchState
  const updateMatchState = (nextState: PlaylistGuideMatchState) => {
    if (externalMatchState === undefined) {
      setLocalMatchState(nextState)
    }
    onMatchStateChange?.(nextState)
  }
  const [pendingKind, setPendingKind] = useState<SetupSelectionKind | null>(null)
  const [matching, setMatching] = useState(false)
  const [pickerError, setPickerError] = useState<string | null>(null)
  const selectionVersion = useRef(0)

  const handleSelect = async (kind: SetupSelectionKind) => {
    const operationVersion = selectionVersion.current + 1
    selectionVersion.current = operationVersion
    const previousStates = selectionStates
    const previousPlaylistContent = playlistContent
    const previousGuideContent = guideContent
    updateMatchState(createInitialPlaylistGuideMatchState())
    setSelectionStates((states) => setSetupSelectionChecking(states, kind))
    if (kind === 'playlist') {
      setPlaylistContent(setPlaylistContentChecking())
    } else if (kind === 'guide') {
      setGuideContent(setGuideContentChecking())
    }
    setPendingKind(kind)
    setPickerError(null)

    try {
      const result = await picker(kind)
      if (operationVersion !== selectionVersion.current) return
      if (result.outcome === 'selected' && result.selectionStatus === 'selected') {
        setSelectionStates((states) => applySetupSelectionResult(states, result))
        if (kind === 'playlist') {
          setPlaylistContent(playlistContentStateFromResult(result))
          setGuideContent(createInitialGuideContentState())
        } else if (kind === 'guide') {
          setGuideContent(guideContentStateFromResult(result))
        } else if (kind === 'workspace') {
          setPlaylistContent(createInitialPlaylistContentState())
          setGuideContent(createInitialGuideContentState())
        }
      } else {
        setSelectionStates(previousStates)
        if (kind === 'playlist') {
          setPlaylistContent(previousPlaylistContent)
        } else if (kind === 'guide') {
          setGuideContent(previousGuideContent)
        }
      }
      setPickerError(safePickerMessage(result))
    } catch {
      if (operationVersion !== selectionVersion.current) return
      setSelectionStates(previousStates)
      if (kind === 'playlist') {
        setPlaylistContent(previousPlaylistContent)
      } else if (kind === 'guide') {
        setGuideContent(previousGuideContent)
      }
      setPickerError('Could not complete this selection.')
    } finally {
      if (operationVersion === selectionVersion.current) {
        setPendingKind(null)
      }
    }
  }

  const handleMatch = async () => {
    const operationVersion = selectionVersion.current
    setMatching(true)
    updateMatchState(setPlaylistGuideMatchChecking())
    setPickerError(null)
    try {
      const result = await matcher()
      if (operationVersion !== selectionVersion.current) return
      updateMatchState(playlistGuideMatchStateFromResult(result))
      setPickerError(safeMatchMessage(result))
    } catch {
      if (operationVersion !== selectionVersion.current) return
      const result = {
        matchStatus: 'blocked' as const,
        playlistEntryCount: null,
        guideChannelCount: null,
        matchedCount: null,
        unmatchedPlaylistCount: null,
        ambiguousCount: null,
        guideOnlyCount: null,
        requiresReview: false,
        reasonCode: 'check-unavailable' as const,
      }
      updateMatchState(playlistGuideMatchStateFromResult(result))
      setPickerError(safeMatchMessage(result))
    } finally {
      if (operationVersion === selectionVersion.current) {
        setMatching(false)
      }
    }
  }

  const workspaceReady = selectionStates.workspace.status === 'selected' && selectionStates.workspace.validationStatus === 'ready-to-inspect'
  const playlistReady = selectionStates.playlist.status === 'selected' && selectionStates.playlist.validationStatus === 'ready-to-inspect' && playlistContent.status === 'checked'
  const guideReady = selectionStates.guide.status === 'selected' && selectionStates.guide.validationStatus === 'ready-to-inspect' && guideContent.status === 'checked'
  const canMatch = pickerAvailable && playlistReady && guideReady && pendingKind === null && !matching
  const bannerStatus = pickerAvailable ? 'Not checked' : 'Disabled'
  const bannerTitle = pickerAvailable ? 'Selection available' : 'Preview only'
  const bannerMessage = pickerAvailable
    ? 'Selection checks confirm only that the item exists, has the expected type, and can be accessed now. Playlist and guide matching runs only after both structural checks pass and reports aggregate counts without changing files.'
    : 'No workspace, playlist, or guide is selected or checked. These controls do not open files or save changes yet.'
  const playlistContentMessage = pickerAvailable
    ? 'The playlist is checked for safe M3U structure only. Stream URLs are not opened or displayed.'
    : 'Preview only. Playlist content is not checked here.'
  const guideContentMessage = pickerAvailable
    ? 'The guide is checked for safe XMLTV structure only. Plain XML/XMLTV, gzip, and single-guide ZIP content are supported; programme titles and channel IDs are not displayed.'
    : 'Preview only. Guide content is not checked here.'
  const progressNote = pickerAvailable
    ? 'This screen opens a native picker, performs bounded structure checks, and compares one playlist with one guide using exact identity matching only. It does not open stream URLs, import, mutate, or store selected files.'
    : 'This screen only displays setup state. It does not open, read, or store files.'
  return (
    <div className="page-stack">
      <PageHeader description="Choose a workspace, add your playlist, and add your guide." eyebrow="Guided setup" title="Set up your workspace" />

      <StatusBanner status={bannerStatus} title={bannerTitle}>
        <p>{bannerMessage}</p>
      </StatusBanner>

      {pickerError ? (
        <p className="setup-picker-error" role="alert">
          {pickerError} Try again.
        </p>
      ) : null}

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
          const canSelect = pickerAvailable && (selectionKind === 'workspace' || (selectionKind === 'playlist' && workspaceReady) || (selectionKind === 'guide' && workspaceReady && playlistReady))
          const isPending = pendingKind === selectionKind

          return (
            <article className="setup-step-card" key={title}>
              <div className="setup-step-heading">
                <div className="setup-step-icon" aria-hidden="true">
                  <Icon size={22} />
                </div>
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
                {selectionKind === 'playlist' ? (
                  <div className="setup-step-selection-row">
                    <span className="setup-step-selection-label">Content</span>
                    <strong>{playlistContent.label}</strong>
                  </div>
                ) : null}
                {selectionKind === 'guide' ? (
                  <div className="setup-step-selection-row">
                    <span className="setup-step-selection-label">Content</span>
                    <strong>{guideContent.label}</strong>
                  </div>
                ) : null}
                {selectionKind === 'playlist' ? <span>{playlistContentMessage}</span> : null}
                {selectionKind === 'guide' ? <span>{guideContentMessage}</span> : null}
                <span>{selection.detail}</span>
                {selectionKind === 'playlist' && (selection.status === 'selected' || isPending) ? <span>{playlistContent.detail}</span> : null}
                {selectionKind === 'guide' && (selection.status === 'selected' || isPending) ? <span>{guideContent.detail}</span> : null}
              </div>
              <div className="setup-step-footer">
                <span className="setup-step-status">{pickerAvailable ? 'Selection enabled' : 'Preview only'}</span>
                <button
                  aria-busy={isPending}
                  className="button button-secondary"
                  disabled={!canSelect || pendingKind !== null || matching}
                  type="button"
                  onClick={() => void handleSelect(selectionKind)}
                >
                  {isPending ? (selectionKind === 'playlist' || selectionKind === 'guide' ? 'Checking…' : 'Choosing…') : buttonLabel}
                </button>
              </div>
            </article>
          )
        })}
      </section>

      <section className="setup-match-card" aria-labelledby="setup-match-title">
        <div className="setup-match-heading">
          <div className="setup-progress-icon" aria-hidden="true">
            <CheckCircle2 size={20} />
          </div>
          <div>
            <p className="eyebrow">Playlist and guide</p>
            <h2 id="setup-match-title">Check their match</h2>
          </div>
        </div>
        <div className="setup-match-status" role="status" aria-live="polite">
          <strong>{matchState.label}</strong>
          <span>{matchState.detail}</span>
        </div>
        <div className="setup-match-grid" aria-label="Playlist and guide match counts">
          <div className="setup-match-metric">
            <span>Matched</span>
            <strong>{matchState.matchedCount ?? '—'}</strong>
          </div>
          <div className="setup-match-metric">
            <span>Not matched</span>
            <strong>{matchState.unmatchedPlaylistCount ?? '—'}</strong>
          </div>
          <div className="setup-match-metric">
            <span>Needs review</span>
            <strong>{matchState.ambiguousCount ?? '—'}</strong>
          </div>
          <div className="setup-match-metric">
            <span>Guide-only</span>
            <strong>{matchState.guideOnlyCount ?? '—'}</strong>
          </div>
        </div>
        <p className="setup-match-note">This is a comparison only. Nothing changes automatically. Channel IDs, programme titles, and stream URLs stay hidden.</p>
        <div className="setup-step-footer">
          <span className="setup-step-status">{canMatch ? 'Ready to check' : 'Check both files first'}</span>
          {onOpenReview && isPlaylistGuideReviewAvailable(matchState) ? (
            <button className="button button-secondary" type="button" onClick={onOpenReview}>
              Open lineup review
            </button>
          ) : null}
          <button aria-busy={matching} className="button button-primary" disabled={!canMatch} type="button" onClick={() => void handleMatch()}>
            {matching ? 'Checking match…' : 'Check playlist and guide'}
          </button>
        </div>
      </section>

      <section className="setup-progress-card" aria-labelledby="setup-progress-title">
        <div className="setup-progress-heading">
          <div className="setup-progress-icon" aria-hidden="true">
            <CheckCircle2 size={20} />
          </div>
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
        <p className="setup-progress-note">
          <BookOpen size={15} aria-hidden="true" /> {progressNote}
        </p>
      </section>
    </div>
  )
}
