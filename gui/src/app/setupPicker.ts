import { invoke, isTauri } from '@tauri-apps/api/core'
import type { SetupPicker, SetupSelectionKind, SetupSelectionResult } from './setupSelection'

export const nativePickerAvailable = isTauri()

export const chooseSetupItem: SetupPicker = (kind: SetupSelectionKind): Promise<SetupSelectionResult> =>
  invoke<SetupSelectionResult>('choose_setup_item', { kind })
