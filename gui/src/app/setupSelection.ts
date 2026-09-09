export type SetupSelectionKind = 'workspace' | 'playlist' | 'guide'

export type SetupSelectionStatus = 'not-selected' | 'selected'
export type SetupValidationStatus = 'not-checked' | 'checking' | 'ready-to-inspect' | 'needs-attention'
export type SetupSelectionOutcome = 'selected' | 'cancelled' | 'rejected' | 'unavailable'
export type PickerReasonCode =
  | 'picker-unavailable'
  | 'permission-denied'
  | 'wrong-kind'
  | 'unknown'
  | 'not-found'
  | 'not-readable'
  | 'check-unavailable'

export type PlaylistContentStatus = 'not-checked' | 'checking' | 'checked' | 'needs-attention'
export type PlaylistContentReasonCode =
  | 'missing-header'
  | 'empty-playlist'
  | 'incomplete-entry'
  | 'orphan-stream-line'
  | 'invalid-encoding'
  | 'too-large'
  | 'unreadable'
  | 'check-unavailable'

export type PlaylistContentResult = {
  contentStatus: PlaylistContentStatus
  entryCount: number | null
  reasonCode: PlaylistContentReasonCode | null
}

export type GuideContentStatus = 'not-checked' | 'checking' | 'checked' | 'needs-attention'
export type GuideContentReasonCode =
  | 'missing-root'
  | 'empty-guide'
  | 'incomplete-channel'
  | 'incomplete-programme'
  | 'invalid-encoding'
  | 'too-large'
  | 'unsupported-format'
  | 'malformed-xml'
  | 'unreadable'
  | 'check-unavailable'

export type GuideContentResult = {
  contentStatus: GuideContentStatus
  channelCount: number | null
  programmeCount: number | null
  reasonCode: GuideContentReasonCode | null
}

export type SetupSelectionResult = {
  kind: SetupSelectionKind
  outcome: SetupSelectionOutcome
  selectionStatus: SetupSelectionStatus
  validationStatus: SetupValidationStatus
  reasonCode: PickerReasonCode | null
  playlistContent?: PlaylistContentResult | null
  guideContent?: GuideContentResult | null
}

export type MatchStatus = 'not-checked' | 'checking' | 'checked' | 'needs-attention' | 'review-needed' | 'blocked'
export type MatchReasonCode =
  | 'missing-playlist'
  | 'missing-guide'
  | 'playlist-not-ready'
  | 'guide-not-ready'
  | 'playlist-content-invalid'
  | 'guide-content-invalid'
  | 'playlist-unavailable'
  | 'guide-unavailable'
  | 'unsupported-format'
  | 'too-large'
  | 'stale-selection'
  | 'unmatched-identity'
  | 'ambiguous-identity'
  | 'check-unavailable'

export type PlaylistGuideMatchResult = {
  matchStatus: MatchStatus
  playlistEntryCount: number | null
  guideChannelCount: number | null
  matchedCount: number | null
  unmatchedPlaylistCount: number | null
  ambiguousCount: number | null
  guideOnlyCount: number | null
  requiresReview: boolean
  reasonCode: MatchReasonCode | null
}

export type SetupSelectionState = {
  kind: SetupSelectionKind
  status: SetupSelectionStatus
  validationStatus: SetupValidationStatus
  displayLabel: string
  validationLabel: string
  detail: string
}

export type SetupSelectionStates = Record<SetupSelectionKind, SetupSelectionState>

export type PlaylistContentState = {
  status: PlaylistContentStatus
  label: string
  detail: string
  entryCount: number | null
}

export type GuideContentState = {
  status: GuideContentStatus
  label: string
  detail: string
  channelCount: number | null
  programmeCount: number | null
}

export type PlaylistGuideMatchState = {
  status: MatchStatus
  label: string
  detail: string
  playlistEntryCount: number | null
  guideChannelCount: number | null
  matchedCount: number | null
  unmatchedPlaylistCount: number | null
  ambiguousCount: number | null
  guideOnlyCount: number | null
  requiresReview: boolean
}

export type SetupPicker = (kind: SetupSelectionKind) => Promise<SetupSelectionResult>
export type SetupMatcher = () => Promise<PlaylistGuideMatchResult>

const kindLabels: Record<SetupSelectionKind, string> = {
  workspace: 'Workspace',
  playlist: 'Playlist',
  guide: 'Guide',
}

const validationLabels: Record<SetupValidationStatus, string> = {
  'not-checked': 'Not checked',
  checking: 'Checking',
  'ready-to-inspect': 'Ready to inspect',
  'needs-attention': 'Needs attention',
}

const playlistContentLabels: Record<PlaylistContentStatus, string> = {
  'not-checked': 'Not checked',
  checking: 'Checking',
  checked: 'Checked',
  'needs-attention': 'Needs attention',
}

const guideContentLabels: Record<GuideContentStatus, string> = {
  'not-checked': 'Not checked',
  checking: 'Checking',
  checked: 'Checked',
  'needs-attention': 'Needs attention',
}
const matchLabels: Record<MatchStatus, string> = {
  'not-checked': 'Not checked',
  checking: 'Checking',
  checked: 'Checked',
  'needs-attention': 'Needs attention',
  'review-needed': 'Review needed',
  blocked: 'Blocked',
}

export function createInitialPlaylistGuideMatchState(): PlaylistGuideMatchState {
  return {
    status: 'not-checked',
    label: matchLabels['not-checked'],
    detail: 'Playlist and guide matching has not been checked.',
    playlistEntryCount: null,
    guideChannelCount: null,
    matchedCount: null,
    unmatchedPlaylistCount: null,
    ambiguousCount: null,
    guideOnlyCount: null,
    requiresReview: false,
  }
}

export function setPlaylistGuideMatchChecking(): PlaylistGuideMatchState {
  return {
    ...createInitialPlaylistGuideMatchState(),
    status: 'checking',
    label: matchLabels.checking,
    detail: 'Checking playlist and guide matching...',
  }
}

function matchReasonMessage(reasonCode: MatchReasonCode | null): string {
  if (
    reasonCode === 'missing-playlist' ||
    reasonCode === 'missing-guide' ||
    reasonCode === 'playlist-not-ready' ||
    reasonCode === 'guide-not-ready'
  ) {
    return 'Choose and check both files before checking their match.'
  }
  if (reasonCode === 'stale-selection') {
    return 'The selected files changed. Check the playlist and guide again.'
  }
  if (reasonCode === 'unsupported-format') {
    return 'The guide format cannot be checked. Choose a supported XMLTV guide.'
  }
  if (reasonCode === 'too-large') {
    return 'The selected file is too large to check safely.'
  }
  if (reasonCode === 'playlist-content-invalid' || reasonCode === 'guide-content-invalid') {
    return 'The playlist or guide content needs attention before matching.'
  }
  if (reasonCode === 'playlist-unavailable' || reasonCode === 'guide-unavailable') {
    return 'The selected playlist or guide cannot be opened.'
  }
  return 'The match could not be checked. Try again.'
}

export function playlistGuideMatchStateFromResult(result: PlaylistGuideMatchResult): PlaylistGuideMatchState {
  const status = result.matchStatus
  const counts = {
    playlistEntryCount: result.playlistEntryCount,
    guideChannelCount: result.guideChannelCount,
    matchedCount: result.matchedCount,
    unmatchedPlaylistCount: result.unmatchedPlaylistCount,
    ambiguousCount: result.ambiguousCount,
    guideOnlyCount: result.guideOnlyCount,
    requiresReview: result.requiresReview,
  }
  if (status === 'checked') {
    return {
      ...counts,
      status,
      label: matchLabels[status],
      detail: `Match checked. ${result.matchedCount ?? 0} playlist channel entries matched.`,
    }
  }
  if (status === 'needs-attention') {
    return {
      ...counts,
      status,
      label: matchLabels[status],
      detail: `Match checked. ${result.unmatchedPlaylistCount ?? 0} playlist channel entries have no guide match.`,
    }
  }
  if (status === 'review-needed') {
    return {
      ...counts,
      status,
      label: matchLabels[status],
      detail: `Review needed. ${result.ambiguousCount ?? 0} playlist channel entries need review.`,
    }
  }
  return {
    ...counts,
    status,
    label: matchLabels[status],
    detail: matchReasonMessage(result.reasonCode),
  }
}

export function safeMatchMessage(result: PlaylistGuideMatchResult): string | null {
  if (result.matchStatus === 'blocked') {
    return matchReasonMessage(result.reasonCode)
  }
  return null
}

export function createInitialPlaylistContentState(): PlaylistContentState {
  return {
    status: 'not-checked',
    label: playlistContentLabels['not-checked'],
    detail: 'Playlist content has not been checked.',
    entryCount: null,
  }
}

export function setPlaylistContentChecking(): PlaylistContentState {
  return {
    status: 'checking',
    label: playlistContentLabels.checking,
    detail: 'Checking playlist content...',
    entryCount: null,
  }
}

export function createInitialGuideContentState(): GuideContentState {
  return {
    status: 'not-checked',
    label: guideContentLabels['not-checked'],
    detail: 'Guide content has not been checked.',
    channelCount: null,
    programmeCount: null,
  }
}

export function setGuideContentChecking(): GuideContentState {
  return {
    status: 'checking',
    label: guideContentLabels.checking,
    detail: 'Checking guide content...',
    channelCount: null,
    programmeCount: null,
  }
}

function guideContentReasonMessage(reasonCode: GuideContentReasonCode | null): string {
  if (reasonCode === 'missing-root') {
    return 'Guide content needs attention. The file must contain a <tv> root.'
  }
  if (reasonCode === 'empty-guide') {
    return 'Guide content needs attention. No channel or programme entries were found.'
  }
  if (reasonCode === 'incomplete-channel') {
    return 'Guide content needs attention. A channel entry is missing its required ID.'
  }
  if (reasonCode === 'incomplete-programme') {
    return 'Guide content needs attention. A programme entry is missing required fields.'
  }
  if (reasonCode === 'invalid-encoding') {
    return 'Guide content needs attention. The file is not valid UTF-8 XMLTV.'
  }
  if (reasonCode === 'unsupported-format') {
    return 'Guide content could not be checked for this file type. Choose an XMLTV file.'
  }
  if (reasonCode === 'too-large') {
    return 'Could not check guide content. The file is too large.'
  }
  if (reasonCode === 'malformed-xml') {
    return 'Guide content needs attention. The file is not a valid XMLTV document.'
  }

  return 'Could not check guide content. Try another file.'
}

export function guideContentStateFromResult(result: SetupSelectionResult): GuideContentState {
  const content = result.kind === 'guide'
    && result.outcome === 'selected'
    && result.selectionStatus === 'selected'
    ? result.guideContent
    : null

  if (!content || content.contentStatus === 'not-checked') {
    return createInitialGuideContentState()
  }
  if (content.contentStatus === 'checking') {
    return setGuideContentChecking()
  }
  if (
    content.contentStatus === 'checked'
    && content.channelCount !== null
    && content.programmeCount !== null
  ) {
    return {
      status: 'checked',
      label: guideContentLabels.checked,
      detail: `Guide content checked. ${content.channelCount} channels and ${content.programmeCount} programmes found.`,
      channelCount: content.channelCount,
      programmeCount: content.programmeCount,
    }
  }

  return {
    status: 'needs-attention',
    label: guideContentLabels['needs-attention'],
    detail: guideContentReasonMessage(content.reasonCode),
    channelCount: null,
    programmeCount: null,
  }
}

function playlistContentReasonMessage(reasonCode: PlaylistContentReasonCode | null): string {
  if (reasonCode === 'missing-header') {
    return 'Playlist content needs attention. The file must start with #EXTM3U.'
  }
  if (reasonCode === 'empty-playlist') {
    return 'Playlist content needs attention. No channel entries found.'
  }
  if (reasonCode === 'incomplete-entry') {
    return 'Playlist content needs attention. An entry is missing its stream line.'
  }
  if (reasonCode === 'orphan-stream-line') {
    return 'Playlist content needs attention. The file contains an unexpected stream line.'
  }

  return 'Could not check playlist content. Try another file.'
}

export function playlistContentStateFromResult(result: SetupSelectionResult): PlaylistContentState {
  const content = result.kind === 'playlist'
    && result.outcome === 'selected'
    && result.selectionStatus === 'selected'
    ? result.playlistContent
    : null

  if (!content || content.contentStatus === 'not-checked') {
    return createInitialPlaylistContentState()
  }
  if (content.contentStatus === 'checking') {
    return setPlaylistContentChecking()
  }
  if (content.contentStatus === 'checked' && content.entryCount !== null) {
    return {
      status: 'checked',
      label: playlistContentLabels.checked,
      detail: `Playlist content checked. ${content.entryCount} channel entries found.`,
      entryCount: content.entryCount,
    }
  }

  return {
    status: 'needs-attention',
    label: playlistContentLabels['needs-attention'],
    detail: playlistContentReasonMessage(content.reasonCode),
    entryCount: null,
  }
}

export function createInitialSetupSelectionState(kind: SetupSelectionKind): SetupSelectionState {
  return {
    kind,
    status: 'not-selected',
    validationStatus: 'not-checked',
    displayLabel: 'Not selected',
    validationLabel: 'Not checked',
    detail: `No ${kind} is selected.`,
  }
}

export const setupSelectionStates: SetupSelectionStates = {
  workspace: createInitialSetupSelectionState('workspace'),
  playlist: createInitialSetupSelectionState('playlist'),
  guide: createInitialSetupSelectionState('guide'),
}

export function selectionStateFromResult(result: SetupSelectionResult): SetupSelectionState {
  const selected = result.outcome === 'selected' && result.selectionStatus === 'selected'
  const validationStatus = selected ? result.validationStatus : 'not-checked'
  const kindLabel = kindLabels[result.kind]
  const detail = !selected
    ? `No ${result.kind} is selected.`
    : validationStatus === 'ready-to-inspect'
      ? `${kindLabel} is ready to inspect.`
      : validationStatus === 'needs-attention'
        ? `${kindLabel} needs attention.`
        : validationStatus === 'checking'
          ? `Checking ${result.kind}...`
          : `${kindLabel} selected.`

  return {
    kind: result.kind,
    status: selected ? 'selected' : 'not-selected',
    validationStatus,
    displayLabel: selected ? 'Selected' : 'Not selected',
    validationLabel: validationLabels[validationStatus],
    detail,
  }
}

export function setSetupSelectionChecking(
  states: SetupSelectionStates,
  kind: SetupSelectionKind,
): SetupSelectionStates {
  return {
    ...states,
    [kind]: {
      ...states[kind],
      validationStatus: 'checking',
      validationLabel: validationLabels.checking,
      detail: `Checking ${kind}...`,
    },
  }
}

export function applySetupSelectionResult(
  states: SetupSelectionStates,
  result: SetupSelectionResult,
): SetupSelectionStates {
  if (result.outcome !== 'selected' || result.selectionStatus !== 'selected') {
    return states
  }

  const nextStates: SetupSelectionStates = {
    ...states,
    [result.kind]: selectionStateFromResult(result),
  }

  if (result.kind === 'workspace') {
    nextStates.playlist = createInitialSetupSelectionState('playlist')
    nextStates.guide = createInitialSetupSelectionState('guide')
  } else if (result.kind === 'playlist') {
    nextStates.guide = createInitialSetupSelectionState('guide')
  }

  return nextStates
}

function safeReasonMessage(kind: SetupSelectionKind, reasonCode: PickerReasonCode): string {
  if (reasonCode === 'picker-unavailable') {
    return 'File selection is unavailable right now.'
  }
  if (reasonCode === 'permission-denied' || reasonCode === 'unknown') {
    return 'Could not complete this selection.'
  }
  if (reasonCode === 'wrong-kind') {
    return kind === 'workspace' ? 'Choose a folder for the workspace.' : `Choose a file for the ${kind}.`
  }
  if (reasonCode === 'not-found') {
    return `${kindLabels[kind]} is not available.`
  }
  if (reasonCode === 'not-readable') {
    return `${kindLabels[kind]} cannot be opened.`
  }

  return 'Could not check this selection.'
}

export function safePickerMessage(result: SetupSelectionResult): string | null {
  if (result.outcome === 'cancelled') {
    return 'Selection cancelled.'
  }

  return result.reasonCode === null ? null : safeReasonMessage(result.kind, result.reasonCode)
}
