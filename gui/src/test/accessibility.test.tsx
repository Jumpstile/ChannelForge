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

  it('names browser source controls and explicit no-guide state', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Guided Setup' }))

    expect(screen.getByRole('status', { name: 'Workspace status' })).toHaveTextContent('Server-owned')
    expect(screen.getByRole('heading', { name: 'Workspace ready' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Choose workspace' })).not.toBeInTheDocument()
    expect(screen.getByText('No guide selected')).toBeInTheDocument()
    expect(screen.getByLabelText('Choose playlist')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add another playlist' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeInTheDocument()
  })
})
