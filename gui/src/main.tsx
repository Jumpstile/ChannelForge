import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { applyAppearance, readAppearance, watchSystemAppearance } from './app/appearance'
import './styles/global.css'

const root = document.getElementById('root')

if (!root) {
  throw new Error('ChannelForge GUI root element is missing')
}

applyAppearance(readAppearance())
watchSystemAppearance()

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
