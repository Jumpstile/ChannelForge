import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import App from '../App'

describe('navigation shell', () => {
  it('starts at Workbench and opens the synthetic state gallery without backend work', async () => {
    const user = userEvent.setup()
    render(<App />)

    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
    await user.click(screen.getAllByRole('button', { name: /view state gallery/i }).at(-1)!)
    expect(screen.getByRole('heading', { name: 'State gallery' })).toBeInTheDocument()
    expect(screen.getByText('Synthetic data only')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /return to workbench/i }))
    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
  })

  it('opens Guided Setup and shows display-safe unselected states without enabling controls', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: 'Open Guided Setup' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Set up your workspace' })).toBeInTheDocument()
    expect(screen.getByText('Your playlist tells ChannelForge what channels you have.')).toBeInTheDocument()
    expect(screen.getByText('Your guide tells ChannelForge what is on those channels.')).toBeInTheDocument()
    expect(screen.getByText('No workspace, playlist, or guide is selected or checked. These controls do not open files or save changes yet.')).toBeInTheDocument()
    expect(screen.getAllByText('Not selected')).toHaveLength(3)
    expect(screen.getAllByText('Not checked')).toHaveLength(3)
    expect(screen.getByText('No workspace is selected.')).toBeInTheDocument()
    expect(screen.getByText('No playlist is selected.')).toBeInTheDocument()
    expect(screen.getByText('No guide is selected.')).toBeInTheDocument()
    for (const label of ['Choose workspace', 'Add playlist', 'Add guide']) {
      expect(screen.getByRole('button', { name: label })).toBeDisabled()
    }
  })

  it('does not expose future workflow pages as active controls', () => {
    render(<App />)

    for (const label of ['Playlist', 'Guide', 'Lineup', 'Saved lineup', 'Automatic updates', 'Learn']) {
      expect(screen.getByRole('button', { name: new RegExp(`${label} Next`) })).toBeDisabled()
    }
  })
})
