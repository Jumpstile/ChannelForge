import type { ChangeEvent } from 'react'
import type { AppearanceMode } from '../app/appearance'

const appearanceOptions: Array<{ value: AppearanceMode; label: string }> = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'system', label: 'System' },
]

type AppearanceControlProps = {
  mode: AppearanceMode
  onChange: (mode: AppearanceMode) => void
}

export function AppearanceControl({ mode, onChange }: AppearanceControlProps) {
  const handleChange = (event: ChangeEvent<HTMLSelectElement>) => {
    onChange(event.target.value as AppearanceMode)
  }

  return (
    <div className="appearance-control">
      <label htmlFor="appearance-mode">Appearance</label>
      <select id="appearance-mode" value={mode} onChange={handleChange} aria-describedby="appearance-mode-help">
        {appearanceOptions.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      <span id="appearance-mode-help">System follows your device setting.</span>
    </div>
  )
}
