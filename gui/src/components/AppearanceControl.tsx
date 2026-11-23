import { useState } from 'react'
import {
  appearanceChoices,
  applyAppearance,
  readAppearance,
  saveAppearance,
  type Appearance,
} from '../app/appearance'

const labels: Record<Appearance, string> = { light: 'Light', dark: 'Dark', system: 'System' }

export function AppearanceControl() {
  const [choice, setChoice] = useState<Appearance>(readAppearance)

  function choose(next: Appearance) {
    setChoice(next)
    saveAppearance(next)
    applyAppearance(next)
  }

  return (
    <fieldset className="appearance-control">
      <legend>Appearance</legend>
      {appearanceChoices.map((value) => (
        <label key={value}>
          <input
            type="radio"
            name="appearance"
            value={value}
            checked={choice === value}
            onChange={() => choose(value)}
          />
          {labels[value]}
        </label>
      ))}
    </fieldset>
  )
}
