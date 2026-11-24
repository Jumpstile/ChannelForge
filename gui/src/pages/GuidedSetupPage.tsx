import { useEffect, useRef, useState } from 'react'
import { BookOpen, CheckCircle2, FileText, FolderOpen, ListVideo } from 'lucide-react'
import {
  acceptGuidedSetupSourceSetProposal,
  submitGuidedSetupSourceSetProposal,
  type GuidedSetupCheck,
  type GuidedSetupSourceDraft,
  type GuidedSetupSourceSetAcceptance,
  type GuidedSetupSourceSetProposal,
  type GuidedSetupSourceSetSubmitter,
} from '../app/guidedSetupProposal'
import { TermCoach } from '../components/TermCoach'
import { PageHeader } from '../components/PageHeader'
import { StatusBanner } from '../components/StatusBanner'
import { StepRail } from '../components/StepRail'
import { nativePickerAvailable, chooseSetupItem, checkPlaylistGuideMatch } from '../app/setupPicker'
import { toFriendlyMessage, type FriendlyMessage } from '../app/friendlyError'
import { ErrorNotice } from '../components/ErrorNotice'
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
  sourceSetProposalSubmitter?: GuidedSetupSourceSetSubmitter
  sourceSetAcceptanceSubmitter?: (proposalId: string) => Promise<GuidedSetupSourceSetAcceptance>
}

type BrowserSourceRow = {
  id: string
  label: string
  mode: 'file' | 'url'
  file: File | null
  url: string
}

type GuideBindingSelection = {
  all: boolean
  playlistIds: string[]
  explicitlyUnbound: boolean
}

const missingSourceMessage = (kind: 'playlist' | 'guide'): FriendlyMessage => ({
  headline: `A ${kind} is still empty`,
  whatHappened: `At least one ${kind} has no file or web address yet. Nothing was sent and your files were not changed.`,
  whatToDo: `Choose a file, or paste a public https:// address, for every ${kind} (or remove the ones you do not need). Then press Analyze.`,
  details: { code: `${kind}-source-missing`, cause: `A ${kind} row has neither a selected file nor a URL.` },
})

const analysisFailedMessage: FriendlyMessage = {
  headline: 'ChannelForge could not check these files',
  whatHappened: 'The check stopped before it finished, and ChannelForge could not tell why. Your playlist and guide files were not changed.',
  whatToDo: 'Start ChannelForge if it is closed, then press Analyze again. If it keeps happening, open Details and share it when you ask for help.',
  details: { cause: 'An unexpected error stopped the analysis before the server gave a result.' },
}

const acceptanceFailedMessage: FriendlyMessage = {
  headline: 'ChannelForge could not accept this lineup',
  whatHappened: 'The accept step stopped before it finished, and ChannelForge could not tell why. It cannot tell whether your lineup was saved.',
  whatToDo: 'Refresh this page and look at your lineup before trying again. If it keeps happening, open Details and share it when you ask for help.',
  details: { cause: 'An unexpected error stopped the accept step before the server gave a result.' },
}

const selectionFailedMessage: FriendlyMessage = {
  headline: 'ChannelForge could not finish that choice',
  whatHappened: 'The file chooser stopped before it gave an answer, and ChannelForge could not tell why. Your earlier choice was kept.',
  whatToDo: 'Pick the item again. If it keeps happening, open Details and share it when you ask for help.',
  details: { cause: 'An unexpected error stopped the file chooser before it gave an answer.' },
}

function ProposalCheckRow({ check }: { check: GuidedSetupCheck }) {
  const [open, setOpen] = useState(false)
  const name = check.Kind === 'logos' ? 'Logos' : check.Kind === 'guides' ? 'Guides' : 'Categories'
  const state = check.Status === 'ok' ? 'OK' : check.Status === 'attention' ? 'Needs a look' : 'Not available'
  return (
    <li>
      <strong>{name}: {state}.</strong> {check.Headline}
      {check.Details.length > 0 ? <> <button aria-expanded={open} className="button" type="button" onClick={() => setOpen(!open)}>{open ? 'Hide details' : 'Details'}</button></> : null}
      {open ? <ul>{check.Details.map((line, index) => <li key={index}>{line}</li>)}</ul> : null}
    </li>
  )
}

function BrowserGuidedSetupPage({
  sourceSetProposalSubmitter,
  sourceSetAcceptanceSubmitter,
}: {
  sourceSetProposalSubmitter: GuidedSetupSourceSetSubmitter
  sourceSetAcceptanceSubmitter: (proposalId: string) => Promise<GuidedSetupSourceSetAcceptance>
}) {
  const [playlists, setPlaylists] = useState<BrowserSourceRow[]>([
    { id: 'playlist-1', label: 'Playlist 1', mode: 'file', file: null, url: '' },
  ])
  const [guides, setGuides] = useState<BrowserSourceRow[]>([])
  const [bindings, setBindings] = useState<Record<string, GuideBindingSelection>>({})
  const [proposal, setProposal] = useState<GuidedSetupSourceSetProposal | null>(null)
  const [accepted, setAccepted] = useState<GuidedSetupSourceSetAcceptance | null>(null)
  const shownWarnings = (proposal?.Warnings ?? []).filter((warning) => !(warning.Code === 'logo-check' && proposal?.Checks?.some((check) => check.Kind === 'logos')))
  const [acknowledged, setAcknowledged] = useState(false)
  const [error, setError] = useState<FriendlyMessage | null>(null)
  const proposalErrorRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const message = proposalErrorRef.current
    if (!error || !message) return
    message.scrollIntoView?.({ behavior: 'smooth', block: 'center' })
    message.focus()
  }, [error])
  const [submitting, setSubmitting] = useState(false)
  const [accepting, setAccepting] = useState(false)

  const resetReview = () => {
    setProposal(null)
    setAccepted(null)
    setAcknowledged(false)
    setError(null)
  }
  const updateSource = (kind: 'playlist' | 'guide', id: string, patch: Partial<BrowserSourceRow>) => {
    resetReview()
    const update = (source: BrowserSourceRow) => source.id === id ? { ...source, ...patch } : source
    if (kind === 'playlist') setPlaylists((items) => items.map(update))
    else setGuides((items) => items.map(update))
  }
  const addPlaylist = () => {
    const number = playlists.length + 1
    setPlaylists((items) => [...items, { id: `playlist-${number}-${Date.now()}`, label: `Playlist ${number}`, mode: 'file', file: null, url: '' }])
    resetReview()
  }
  const addGuide = () => {
    const number = guides.length + 1
    const guide = { id: `guide-${number}-${Date.now()}`, label: `Guide ${number}`, mode: 'file' as const, file: null, url: '' }
    setGuides((items) => [...items, guide])
    if (playlists.length === 1) {
      setBindings((current) => ({ ...current, [guide.id]: { all: false, playlistIds: [playlists[0].id], explicitlyUnbound: false } }))
    }
    resetReview()
  }
  const removeGuide = (id: string) => {
    setGuides((items) => items.filter((guide) => guide.id !== id))
    setBindings((current) => {
      const next = { ...current }
      delete next[id]
      return next
    })
    resetReview()
  }
  const setBinding = (guideId: string, selection: Omit<GuideBindingSelection, 'explicitlyUnbound'>) => {
    setBindings((current) => ({
      ...current,
      [guideId]: { ...selection, explicitlyUnbound: !selection.all && selection.playlistIds.length === 0 },
    }))
    resetReview()
  }

  const renderSourceRow = (source: BrowserSourceRow, kind: 'playlist' | 'guide', index: number) => {
    const noun = kind === 'playlist' ? 'playlist' : 'guide'
    return (
      <div className="setup-source-row" key={source.id}>
        <div className="setup-source-row-heading">
          <strong>{source.label || `${noun[0].toUpperCase()}${noun.slice(1)} ${index + 1}`}</strong>
          {kind === 'guide' ? <button className="button button-tertiary" type="button" onClick={() => removeGuide(source.id)}>Remove</button> : null}
        </div>
        <label>
          Friendly name
          <input value={source.label} onChange={(event) => updateSource(kind, source.id, { label: event.target.value })} />
        </label>
        <div className="setup-source-mode" role="group" aria-label={`${noun} input type`}>
          <button className={`button ${source.mode === 'file' ? 'button-primary' : 'button-secondary'}`} type="button" onClick={() => updateSource(kind, source.id, { mode: 'file', url: '' })}>Local file</button>
          <button className={`button ${source.mode === 'url' ? 'button-primary' : 'button-secondary'}`} type="button" onClick={() => updateSource(kind, source.id, { mode: 'url', file: null })}>Public HTTPS</button>
        </div>
        {source.mode === 'file' ? (
          <>
            <label className="button button-secondary" htmlFor={`guided-setup-${noun}-${source.id}`}>Choose {noun}</label>
            <input id={`guided-setup-${noun}-${source.id}`} accept={kind === 'playlist' ? '.m3u,.m3u8' : '.xml,.xmltv'} onChange={(event) => updateSource(kind, source.id, { file: event.target.files?.[0] ?? null })} type="file" />
            <span className="setup-source-detail">{source.file ? source.file.name : 'No file selected'}</span>
          </>
        ) : (
          <label>
            Public HTTPS URL
            <input inputMode="url" placeholder="https://provider.example/playlist.m3u" value={source.url} onChange={(event) => updateSource(kind, source.id, { url: event.target.value })} />
          </label>
        )}
      </div>
    )
  }

  const submit = async () => {
    if (playlists.some((source) => (source.mode === 'file' ? !source.file : !source.url.trim()))) {
      setError(missingSourceMessage('playlist'))
      return
    }
    if (guides.some((source) => (source.mode === 'file' ? !source.file : !source.url.trim()))) {
      setError(missingSourceMessage('guide'))
      return
    }
    const playlistDrafts: GuidedSetupSourceDraft[] = playlists.map((source, index) => ({
      sourceKey: source.id,
      label: source.label.trim() || `Playlist ${index + 1}`,
      priority: index + 1,
      file: source.mode === 'file' ? source.file : null,
      url: source.mode === 'url' ? source.url : undefined,
    }))
    const guideDrafts: GuidedSetupSourceDraft[] = guides.map((source, index) => ({
      sourceKey: source.id,
      label: source.label.trim() || `Guide ${index + 1}`,
      priority: index + 1,
      file: source.mode === 'file' ? source.file : null,
      url: source.mode === 'url' ? source.url : undefined,
    }))
    const bindingDrafts = guides.flatMap((guide) => {
      const selection = bindings[guide.id]
      if (!selection) return []
      if (selection.all) return [{ guideRef: guide.id, playlistRefs: [], appliesToAll: true }]
      if (selection.playlistIds.length > 0) return [{ guideRef: guide.id, playlistRefs: selection.playlistIds, appliesToAll: false }]
      if (selection.explicitlyUnbound) return [{ guideRef: guide.id, playlistRefs: [], appliesToAll: false, explicitlyUnbound: true }]
      return []
    })
    setSubmitting(true)
    setError(null)
    setProposal(null)
    setAccepted(null)
    setAcknowledged(false)
    try {
      setProposal(await sourceSetProposalSubmitter(playlistDrafts, guideDrafts, bindingDrafts))
    } catch (submissionError) {
      setError(toFriendlyMessage(submissionError, analysisFailedMessage))
    } finally {
      setSubmitting(false)
    }
  }

  const accept = async () => {
    if (!proposal || !proposal.Proposal.CanAccept || !acknowledged) return
    setAccepting(true)
    setError(null)
    try {
      setAccepted(await sourceSetAcceptanceSubmitter(proposal.Proposal.ProposalId))
    } catch (acceptanceError) {
      setError(toFriendlyMessage(acceptanceError, acceptanceFailedMessage))
    } finally {
      setAccepting(false)
    }
  }

  const selectedPlaylistCount = playlists.filter((source) =>
    source.mode === 'file' ? source.file !== null : source.url.trim().length > 0,
  ).length

  return (
    <div className="page-stack">
      <PageHeader description="Add one or more playlists, optionally add guides, and review explicit guide bindings before acceptance." eyebrow="Guided setup" title="Set up your workspace" />
      <StatusBanner status={accepted ? 'Success' : 'Ready'} title={accepted ? 'Accepted lineup' : 'Browser review'}>
        <p>{accepted ? 'The reviewed source set is now the accepted local state.' : 'Files are read in this browser only to create a server-owned candidate. Nothing is accepted until you acknowledge the review.'}</p>
      </StatusBanner>
      {error ? <ErrorNotice message={error} ref={proposalErrorRef} /> : null}
      <section className="setup-step-grid" aria-label="Guided setup steps">
        <article className="setup-step-card">
          <div className="setup-step-heading"><div className="setup-step-icon" aria-hidden="true"><FolderOpen size={22} /></div><div><p className="eyebrow">Workspace</p><h2>Workspace ready</h2></div></div>
          <p className="setup-step-description">ChannelForge keeps this review in a server-owned workspace.</p>
          <div className="setup-step-selection" role="status" aria-label="Workspace status">
            <div className="setup-step-selection-row"><span className="setup-step-selection-label">Status</span><strong>Server-owned</strong></div>
            <span>This browser flow does not ask you to choose a folder.</span>
          </div>
        </article>
        <article className="setup-step-card">
          <div className="setup-step-heading"><div className="setup-step-icon" aria-hidden="true"><ListVideo size={22} /></div><div><p className="setup-step-number">Step 1</p><h2>Playlists</h2></div></div>
          <p className="setup-step-description">Add every playlist that belongs in the source set. Each item can be a local file or a public HTTPS URL.</p>
          <p className="setup-step-description">Links with a password or token in them are not supported yet. Use a file instead.</p>
          {playlists.map((source, index) => renderSourceRow(source, 'playlist', index))}
          <button className="button button-secondary" type="button" onClick={addPlaylist}>Add another playlist</button>
        </article>
        <article className="setup-step-card">
          <div className="setup-step-heading"><div className="setup-step-icon" aria-hidden="true"><FileText size={22} /></div><div><p className="setup-step-number">Step 2</p><h2>Guides</h2></div></div>
          <p className="setup-step-description">Guides are optional. Continue with no guide, or add each <TermCoach term="xmltv-guide" /> file or public HTTPS URL explicitly.</p>
          {guides.length === 0 ? <div className="setup-step-selection" role="status"><strong>No guide selected</strong><span>ChannelForge will keep the source set in playlist-only mode.</span></div> : guides.map((source, index) => renderSourceRow(source, 'guide', index))}
          <button className="button button-secondary" type="button" onClick={addGuide}>Add guide</button>
        </article>
      </section>
      {guides.length > 0 ? (
        <section className="setup-match-card" aria-labelledby="guide-binding-title">
          <div className="setup-match-heading"><div className="setup-progress-icon" aria-hidden="true"><CheckCircle2 size={20} /></div><div><p className="eyebrow">Explicit review</p><h2 id="guide-binding-title">Bind each guide to playlists</h2></div></div>
          <p className="setup-match-note">A guide defaults to the only playlist. Clear its selection to keep it explicitly unbound, or choose all playlists when more than one is configured.</p>
          {guides.map((guide) => {
            const selection = bindings[guide.id] ?? { all: false, playlistIds: [], explicitlyUnbound: false }
            const bindingStatus = selection.all
              ? 'Selected for all playlists. This guide will be applied to every playlist only after you accept the reviewed proposal.'
              : selection.playlistIds.length > 0
                ? `Selected for ${selection.playlistIds.length} playlist${selection.playlistIds.length === 1 ? '' : 's'}. This guide will be applied only to those playlists after acceptance.`
                : selection.explicitlyUnbound
                  ? 'Explicitly unbound. This guide remains enrolled for review but will not be applied.'
                  : 'Unbound because no binding decision was supplied. This guide remains enrolled for review but will not be applied.'
            return (
              <fieldset className="setup-binding-fieldset" key={guide.id}>
                <legend>{guide.label || 'Guide'} — Apply this guide to:</legend>
                {playlists.length > 1 && !selection.all && selection.playlistIds.length === 0 && !selection.explicitlyUnbound ? <p className="setup-binding-status" role="status"><strong>Choose a playlist for this guide</strong></p> : null}
                <p className="setup-binding-status" role="status">{bindingStatus}</p>
                {playlists.length > 1 ? <label><input checked={selection.all} type="checkbox" onChange={(event) => setBinding(guide.id, { all: event.target.checked, playlistIds: [] })} /> All playlists</label> : null}
                {playlists.map((playlist) => <label key={playlist.id}><input checked={!selection.all && selection.playlistIds.includes(playlist.id)} disabled={selection.all} type="checkbox" onChange={(event) => setBinding(guide.id, { all: false, playlistIds: event.target.checked ? [...selection.playlistIds, playlist.id] : selection.playlistIds.filter((id) => id !== playlist.id) })} /> {playlist.label || 'Playlist'}</label>)}
              </fieldset>
            )
          })}
        </section>
      ) : null}
      <section className="setup-match-card" aria-labelledby="browser-proposal-title">
        <div className="setup-match-heading"><div className="setup-progress-icon" aria-hidden="true"><CheckCircle2 size={20} /></div><div><p className="eyebrow">{accepted ? 'Accepted' : proposal ? 'Review ready' : 'Review'}</p><h2 id="browser-proposal-title">{accepted ? 'Lineup accepted' : 'Analyze and review'}</h2></div></div>
        <p className="setup-match-note">{accepted ? 'The acknowledgement committed the exact reviewed candidate through the existing immutable acceptance and recovery path. Provider files and downstream outputs were not changed.' : 'The server stores the exact candidate bytes for this review. Accepted state remains unchanged until you acknowledge and accept the reviewed proposal.'}</p>
        <div className="setup-step-footer"><span className="setup-step-status">{accepted ? 'Accepted successfully' : proposal ? (proposal.Proposal.CanAccept ? 'Ready for acknowledgement' : 'Blocked by review') : error ? (selectedPlaylistCount > 0 ? `Analysis stopped; ${selectedPlaylistCount} playlist${selectedPlaylistCount === 1 ? '' : 's'} remain selected.` : 'Add at least one playlist to analyze.') : submitting ? `Analyzing ${selectedPlaylistCount} playlist${selectedPlaylistCount === 1 ? '' : 's'}…` : selectedPlaylistCount === 0 ? 'Add at least one playlist to analyze.' : `Ready to analyze ${selectedPlaylistCount} playlist${selectedPlaylistCount === 1 ? '' : 's'}.`}</span><button aria-busy={submitting} className="button button-primary" disabled={playlists.length === 0 || submitting} type="button" onClick={() => void submit()}>{submitting ? 'Analyzing proposal…' : 'Analyze source set'}</button></div>
        {proposal ? (
          <div className="setup-proposal-summary" role="status" aria-live="polite">
            <strong>{accepted ? 'Accepted lineup confirmed.' : proposal.Proposal.CanAccept ? 'Review ready. Nothing has been accepted yet.' : 'Review blocked. Nothing has been accepted.'}</strong>
            <dl>
              <div><dt>Playlists</dt><dd>{proposal.Proposal.PlaylistCount}</dd></div>
              <div><dt>Guides</dt><dd>{proposal.Proposal.GuideCount}</dd></div>
              <div><dt>Exact guide matches</dt><dd>{proposal.Proposal.ExactGuideMatchCount}</dd></div>
              <div><dt>Unmatched playlists</dt><dd>{proposal.Proposal.UnmatchedPlaylistCount}</dd></div>
              <div><dt>Needs review</dt><dd>{proposal.Proposal.AmbiguityCount}</dd></div>
              <div><dt>Unbound guides</dt><dd>{proposal.Proposal.UnboundGuideCount}</dd></div>
            </dl>
            {proposal.Checks && proposal.Checks.length > 0 ? <><h3>Checks before you accept</h3><ul>{proposal.Checks.map((check) => <ProposalCheckRow check={check} key={check.Kind} />)}</ul></> : null}
            {shownWarnings.length > 0 ? <ul>{shownWarnings.map((warning) => <li key={warning.Code}>{warning.Message}</li>)}</ul> : <p>No proposal warnings.</p>}
            {proposal.Proposal.BlockingReasons.length > 0 ? <p role="alert">Acceptance is blocked until the review blockers are resolved.</p> : null}
            {!accepted ? <div className="saved-lineup-action-row"><label className="saved-lineup-acknowledgement"><input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} /> I reviewed these results and want to accept this exact proposal.</label><button aria-busy={accepting} className="button button-primary" disabled={!proposal.Proposal.CanAccept || !acknowledged || accepting} type="button" onClick={() => void accept()}>{accepting ? 'Accepting…' : 'Accept reviewed proposal'}</button></div> : null}
          </div>
        ) : null}
      </section>
    </div>
  )
}


export function GuidedSetupPage({
  picker = chooseSetupItem,
  matcher = checkPlaylistGuideMatch,
  pickerAvailable = nativePickerAvailable,
  matchState: externalMatchState,
  onMatchStateChange,
  onOpenReview,
  sourceSetProposalSubmitter = submitGuidedSetupSourceSetProposal,
  sourceSetAcceptanceSubmitter = acceptGuidedSetupSourceSetProposal,
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
  const [pickerError, setPickerError] = useState<FriendlyMessage | null>(null)
  const selectionVersion = useRef(0)
  if (!pickerAvailable) return <BrowserGuidedSetupPage sourceSetProposalSubmitter={sourceSetProposalSubmitter} sourceSetAcceptanceSubmitter={sourceSetAcceptanceSubmitter} />

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
      setPickerError(selectionFailedMessage)
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
    ? 'ChannelForge checks that each item you pick exists, is the right kind, and can be opened. When your playlist and guide both pass, you can check how well they match. Your files are not changed.'
    : 'Nothing is picked or checked yet. These buttons do not open or save anything yet.'
  const playlistContentMessage = pickerAvailable
    ? <>The playlist is checked for safe <TermCoach term="m3u-playlist" /> structure only. <TermCoach term="stream-url" />s are not opened or displayed.</>
    : 'Preview only. Playlist content is not checked here.'
  const guideContentMessage = pickerAvailable
    ? <>The guide is checked for safe XMLTV structure only. Plain XML/XMLTV, gzip, and single-guide ZIP content are supported; program titles and <TermCoach term="channel-id" label="channel ID" />s are not displayed.</>
    : 'Preview only. Guide content is not checked here.'
  const progressNote = pickerAvailable
    ? 'ChannelForge checks the files you pick and compares your playlist with your guide. It never opens your streams and never changes or stores your files.'
    : 'This screen only shows the setup steps. It does not open, read, or store any files.'
  return (
    <div className="page-stack">
      <PageHeader description="Choose a workspace, add your playlist, and add your guide." eyebrow="Guided setup" title="Set up your workspace" />

      <StatusBanner status={bannerStatus} title={bannerTitle}>
        <p>{bannerMessage}</p>
      </StatusBanner>

      {pickerError ? <ErrorNotice message={pickerError} /> : null}

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
        <p className="setup-match-note">This is a comparison only. Nothing changes automatically. <TermCoach term="channel-id" />s, program titles, and <TermCoach term="stream-url" label="stream URL" />s stay hidden.</p>
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
