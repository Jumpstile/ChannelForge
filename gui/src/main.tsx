import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { AuthGate } from './components/AuthGate'
import { applyAppearance, readAppearance, watchSystemAppearance } from './app/appearance'
import { applyTextSize, readTextSize } from './app/textSize'
import './styles/global.css'

const root = document.getElementById('root')

if (!root) {
  throw new Error('ChannelForge GUI root element is missing')
}

applyAppearance(readAppearance())
watchSystemAppearance()
applyTextSize(readTextSize())

createRoot(root).render(
  <StrictMode>
    <AuthGate />
  </StrictMode>,
)
