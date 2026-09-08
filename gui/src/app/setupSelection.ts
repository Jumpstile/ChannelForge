export type SetupSelectionKind = 'workspace' | 'playlist' | 'guide'

export type SetupSelectionStatus = 'not-selected'
export type SetupValidationStatus = 'not-checked'

export type SetupSelectionState = {
  kind: SetupSelectionKind
  status: SetupSelectionStatus
  validationStatus: SetupValidationStatus
  displayLabel: string
  validationLabel: string
  detail: string
}

export const setupSelectionStates: Record<SetupSelectionKind, SetupSelectionState> = {
  workspace: {
    kind: 'workspace',
    status: 'not-selected',
    validationStatus: 'not-checked',
    displayLabel: 'Not selected',
    validationLabel: 'Not checked',
    detail: 'No workspace is selected.',
  },
  playlist: {
    kind: 'playlist',
    status: 'not-selected',
    validationStatus: 'not-checked',
    displayLabel: 'Not selected',
    validationLabel: 'Not checked',
    detail: 'No playlist is selected.',
  },
  guide: {
    kind: 'guide',
    status: 'not-selected',
    validationStatus: 'not-checked',
    displayLabel: 'Not selected',
    validationLabel: 'Not checked',
    detail: 'No guide is selected.',
  },
}
