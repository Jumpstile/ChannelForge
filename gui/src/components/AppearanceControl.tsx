import { useEffect, useState } from 'react'
import {
  appearanceChoices,
  applyAppearance,
  readAppearance,
  saveAppearance,
  saveServerAppearance,
  syncAppearance,
  type Appearance,
} from '../app/appearance'
import type { FriendlyMessage } from '../app/friendlyError'
import { ErrorNotice } from './ErrorNotice'

const labels: Record<Appearance, string> = { light: 'Light', dark: 'Dark', system: 'System' }

const saveFailed: FriendlyMessage = {
  headline: 'ChannelForge could not save your look choice',
  whatHappened: 'Your choice works in this browser right now, but ChannelForge could not keep it for your other browsers.',
  whatToDo: 'Make sure ChannelForge is still running, then pick the look again.',
  details: { code: 'settings-not-saved', cause: 'The request to save the appearance setting on the ChannelForge server did not succeed.' },
}

export function AppearanceControl() {
  const [choice, setChoice] = useState<Appearance>(readAppearance)
  const [failed, setFailed] = useState(false)

  // The server value wins. The browser value is only a cache that avoids a flash of the wrong look.
  useEffect(() => {
    let current = true
    void syncAppearance().then((serverChoice) => {
      if (!current) return
      setChoice(serverChoice)
      applyAppearance(serverChoice)
    })
    return () => {
      current = false
    }
  }, [])

  async function choose(next: Appearance) {
    setChoice(next)
    saveAppearance(next)
    applyAppearance(next)
    setFailed(!(await saveServerAppearance(next)))
  }

  return (
    <>
      <fieldset className="appearance-control">
        <legend>Appearance</legend>
        {appearanceChoices.map((value) => (
          <label key={value}>
            <input
              type="radio"
              name="appearance"
              value={value}
              checked={choice === value}
              onChange={() => void choose(value)}
            />
            {labels[value]}
          </label>
        ))}
      </fieldset>
      {failed ? <ErrorNotice message={saveFailed} /> : null}
    </>
  )
}
