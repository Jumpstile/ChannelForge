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

export type SetupSelectionResult = {
  kind: SetupSelectionKind
  outcome: SetupSelectionOutcome
  selectionStatus: SetupSelectionStatus
  validationStatus: SetupValidationStatus
  reasonCode: PickerReasonCode | null
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

export type SetupPicker = (kind: SetupSelectionKind) => Promise<SetupSelectionResult>

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

export function setSetupSelectionChecking(states: SetupSelectionStates, kind: SetupSelectionKind): SetupSelectionStates {
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

export function applySetupSelectionResult(states: SetupSelectionStates, result: SetupSelectionResult): SetupSelectionStates {
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
