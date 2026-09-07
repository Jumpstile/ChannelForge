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

  it('does not expose future workflow pages as active controls', () => {
    render(<App />)

    for (const label of ['Playlist', 'Guide', 'Lineup', 'Saved lineup', 'Automatic updates', 'Learn']) {
      expect(screen.getByRole('button', { name: new RegExp(`${label} Next`) })).toBeDisabled()
    }
  })
})
