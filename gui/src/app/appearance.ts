export type Appearance = 'light' | 'dark' | 'system'

export const appearanceStorageKey = 'channelforge.appearance'
export const appearanceChoices: readonly Appearance[] = ['light', 'dark', 'system']

const darkQuery = '(prefers-color-scheme: dark)'

export function readAppearance(): Appearance {
  try {
    const saved = window.localStorage.getItem(appearanceStorageKey)
    return appearanceChoices.find((choice) => choice === saved) ?? 'system'
  } catch {
    return 'system'
  }
}

export function saveAppearance(choice: Appearance): void {
  try {
    window.localStorage.setItem(appearanceStorageKey, choice)
  } catch {
    // Storage can be blocked. The choice still applies for this visit.
  }
}

export function resolveAppearance(choice: Appearance): 'light' | 'dark' {
  if (choice !== 'system') return choice
  return window.matchMedia?.(darkQuery).matches ? 'dark' : 'light'
}

export function applyAppearance(choice: Appearance): void {
  document.documentElement.dataset.theme = resolveAppearance(choice)
}

/** Re-applies the saved choice when the system setting changes. Returns a stop function. */
export function watchSystemAppearance(): () => void {
  const query = window.matchMedia?.(darkQuery)
  if (!query) return () => undefined
  const onChange = () => applyAppearance(readAppearance())
  query.addEventListener('change', onChange)
  return () => query.removeEventListener('change', onChange)
}
