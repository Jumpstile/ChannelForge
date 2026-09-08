export type SetupSelectionKind = 'workspace' | 'playlist' | 'guide'

export type SetupSelectionStatus = 'not-selected' | 'selected'
export type SetupValidationStatus = 'not-checked'
export type SetupSelectionOutcome = 'selected' | 'cancelled' | 'rejected' | 'unavailable'
export type PickerErrorCode = 'picker-unavailable' | 'permission-denied' | 'wrong-kind' | 'unknown'

export type SetupSelectionResult = {
  kind: SetupSelectionKind
  outcome: SetupSelectionOutcome
  selectionStatus: SetupSelectionStatus
  validationStatus: SetupValidationStatus
  errorCode: PickerErrorCode | null
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

  return {
    kind: result.kind,
    status: selected ? 'selected' : 'not-selected',
    validationStatus: 'not-checked',
    displayLabel: selected ? 'Selected' : 'Not selected',
    validationLabel: 'Not checked',
    detail: selected ? `${result.kind[0].toUpperCase()}${result.kind.slice(1)} selected.` : `No ${result.kind} is selected.`,
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

const pickerErrorMessages: Record<PickerErrorCode, string> = {
  'picker-unavailable': 'File selection is unavailable right now.',
  'permission-denied': 'Could not complete this selection.',
  'wrong-kind': 'That selection cannot be used here.',
  unknown: 'Could not complete this selection.',
}

export function safePickerMessage(result: SetupSelectionResult): string | null {
  if (result.outcome === 'cancelled') {
    return 'Selection cancelled.'
  }

  return result.errorCode === null ? null : pickerErrorMessages[result.errorCode]
}
