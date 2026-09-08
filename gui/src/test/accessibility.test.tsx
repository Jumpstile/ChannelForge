import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import App from '../App'
describe('shell accessibility scaffolding', () => {
  it('provides landmark regions, a named workflow navigation, and a main heading', () => {
    render(<App />)

    expect(screen.getByRole('navigation', { name: 'Workflow pages' })).toBeInTheDocument()
    expect(screen.getByRole('main')).toBeInTheDocument()
    expect(screen.getByRole('contentinfo')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
  })

  it('provides a named Guided Setup step region', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Guided setup steps' })).toBeInTheDocument()
  })

  it('names each display-safe selection status and playlist content status', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))

    for (const label of ['Choose workspace', 'Add playlist', 'Add guide']) {
      expect(screen.getByRole('status', { name: `${label} selection status` })).toHaveTextContent('Not selected')
      expect(screen.getByRole('status', { name: `${label} selection status` })).toHaveTextContent('Not checked')
    }
    expect(screen.getByRole('status', { name: 'Add playlist selection status' })).toHaveTextContent('Content')
  })
})
