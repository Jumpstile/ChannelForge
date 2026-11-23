import type { KeyboardEvent } from 'react'
import { ArrowLeft, House } from 'lucide-react'

type HomeBackBarProps = {
  onHome: () => void
  onBack: () => void
}

// Left and Right arrows move between the two buttons; Enter presses the focused one.
function moveFocus(event: KeyboardEvent<HTMLElement>) {
  if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
  const buttons = Array.from(event.currentTarget.querySelectorAll('button'))
  const index = buttons.indexOf(document.activeElement as HTMLButtonElement)
  if (index < 0) return
  event.preventDefault()
  const step = event.key === 'ArrowRight' ? 1 : -1
  buttons[(index + step + buttons.length) % buttons.length].focus()
}

export function HomeBackBar({ onHome, onBack }: HomeBackBarProps) {
  return (
    <nav className="home-back-bar" aria-label="Home and Back" onKeyDown={moveFocus}>
      <button className="button button-secondary home-back-button" type="button" onClick={onHome}>
        <House size={20} aria-hidden="true" />
        Home
      </button>
      <button className="button button-secondary home-back-button" type="button" onClick={onBack}>
        <ArrowLeft size={20} aria-hidden="true" />
        Back
      </button>
    </nav>
  )
}
