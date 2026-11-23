export type TextSize = 'normal' | 'large' | 'extra-large'

export const textSizeStorageKey = 'channelforge.textSize'
export const textSizeChoices: readonly TextSize[] = ['normal', 'large', 'extra-large']

export function readTextSize(): TextSize {
  try {
    const saved = window.localStorage.getItem(textSizeStorageKey)
    return textSizeChoices.find((choice) => choice === saved) ?? 'normal'
  } catch {
    return 'normal'
  }
}

export function saveTextSize(choice: TextSize): void {
  try {
    window.localStorage.setItem(textSizeStorageKey, choice)
  } catch {
    // Storage can be blocked. The choice still applies for this visit.
  }
}

export function applyTextSize(choice: TextSize): void {
  document.documentElement.dataset.textSize = choice
}
