import { useState } from 'react'
import {
  applyTextSize,
  readTextSize,
  saveTextSize,
  textSizeChoices,
  type TextSize,
} from '../app/textSize'

const labels: Record<TextSize, string> = { normal: 'Normal', large: 'Large', 'extra-large': 'Extra large' }

export function TextSizeControl() {
  const [choice, setChoice] = useState<TextSize>(readTextSize)

  function choose(next: TextSize) {
    setChoice(next)
    saveTextSize(next)
    applyTextSize(next)
  }

  return (
    <fieldset className="appearance-control">
      <legend>Text size</legend>
      {textSizeChoices.map((value) => (
        <label key={value}>
          <input
            type="radio"
            name="text-size"
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
