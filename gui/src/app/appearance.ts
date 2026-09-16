import { useEffect, useState } from 'react'

export type AppearanceMode = 'light' | 'dark' | 'system'

export const appearanceStorageKey = 'channelforge.appearance-mode'

function isAppearanceMode(value: string | null): value is AppearanceMode {
  return value === 'light' || value === 'dark' || value === 'system'
}

export function readStoredAppearanceMode(storage?: Storage): AppearanceMode {
  try {
    const browserStorage = storage ?? (typeof window === 'undefined' ? undefined : window.localStorage)
    const storedMode = browserStorage?.getItem(appearanceStorageKey)
    return isAppearanceMode(storedMode) ? storedMode : 'system'
  } catch {
    return 'system'
  }
}

export function useAppearanceMode() {
  const [mode, setMode] = useState<AppearanceMode>(() => readStoredAppearanceMode())

  useEffect(() => {
    const root = document.documentElement
    const mediaQuery = window.matchMedia?.('(prefers-color-scheme: dark)')

    const applyTheme = (prefersDark: boolean) => {
      const theme = mode === 'system' ? (prefersDark ? 'dark' : 'light') : mode
      root.dataset.appearanceMode = mode
      root.dataset.theme = theme
      root.style.colorScheme = theme
    }

    applyTheme(mediaQuery?.matches ?? false)

    try {
      window.localStorage.setItem(appearanceStorageKey, mode)
    } catch {
      // Browser storage may be unavailable; the in-memory setting still applies.
    }

    if (mode !== 'system' || !mediaQuery) return undefined

    const handlePreferenceChange = (event: MediaQueryListEvent) => applyTheme(event.matches)
    if (mediaQuery.addEventListener) {
      mediaQuery.addEventListener('change', handlePreferenceChange)
      return () => mediaQuery.removeEventListener('change', handlePreferenceChange)
    }

    mediaQuery.addListener(handlePreferenceChange)
    return () => mediaQuery.removeListener(handlePreferenceChange)
  }, [mode])

  return { mode, setMode }
}
