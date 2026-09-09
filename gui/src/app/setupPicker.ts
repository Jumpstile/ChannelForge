import { invoke, isTauri } from '@tauri-apps/api/core'
import type {
  PlaylistGuideMatchResult,
  SetupMatcher,
  SetupPicker,
  SetupSelectionKind,
  SetupSelectionResult,
} from './setupSelection'

export const nativePickerAvailable = isTauri()

export const chooseSetupItem: SetupPicker = (kind: SetupSelectionKind): Promise<SetupSelectionResult> =>
  invoke<SetupSelectionResult>('choose_setup_item', { kind })

export const checkPlaylistGuideMatch: SetupMatcher = (): Promise<PlaylistGuideMatchResult> =>
  invoke<PlaylistGuideMatchResult>('check_playlist_guide_match')
