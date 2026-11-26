export type Appearance = 'light' | 'dark' | 'system'

export const appearanceStorageKey = 'channelforge.appearance'
export const appearanceChoices: readonly Appearance[] = ['light', 'dark', 'system']

const darkQuery = '(prefers-color-scheme: dark)'

function storedAppearance(): Appearance | null {
  try {
    const saved = window.localStorage.getItem(appearanceStorageKey)
    return appearanceChoices.find((choice) => choice === saved) ?? null
  } catch {
    return null
  }
}

export function readAppearance(): Appearance {
  return storedAppearance() ?? 'system'
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

const settingsHeaders = { Accept: 'application/json', 'Content-Type': 'application/json' }

function isAppearance(value: unknown): value is Appearance {
  return appearanceChoices.some((choice) => choice === value)
}

/** Saves the choice on the server. Returns false when the server could not keep it. */
export async function saveServerAppearance(choice: Appearance, request: typeof fetch = fetch): Promise<boolean> {
  try {
    const response = await request('/api/settings', { method: 'PUT', headers: settingsHeaders, body: JSON.stringify({ appearance: choice }) })
    return response.status === 200
  } catch {
    return false
  }
}

/**
 * Asks the server for the saved choice. The server value wins and the local value is only a cache.
 * A server with nothing saved gets the valid local value once. An unreachable server never blocks: the local value (or System) is used.
 */
export async function syncAppearance(request: typeof fetch = fetch): Promise<Appearance> {
  const local = readAppearance()
  try {
    const response = await request('/api/settings', { method: 'GET', headers: { Accept: 'application/json' } })
    if (response.status !== 200) return local
    const body = (await response.json()) as { appearance?: unknown; saved?: unknown }
    if (body.saved === true && isAppearance(body.appearance)) {
      saveAppearance(body.appearance)
      return body.appearance
    }
    if (body.saved === false && storedAppearance() !== null) await saveServerAppearance(local, request)
  } catch {
    // Unreachable or unreadable answer: keep the local value.
  }
  return local
}
