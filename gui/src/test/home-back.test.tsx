import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import App from '../App'

const workbench = () => screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })
const pages = ['Live Now', 'Wrestling', 'Guided Setup', 'Channel lineup', 'Learn']

describe('Home and Back', () => {
  it.each(pages)('Home goes to the Workbench from %s', async (label) => {
    const user = userEvent.setup()
    render(<App />)
    await user.click(screen.getByRole('button', { name: new RegExp(`^${label}`) }))
    expect(screen.queryByRole('heading', { level: 1, name: 'Your lineup workbench' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Home' }))
    expect(workbench()).toBeInTheDocument()
  })

  it('Back returns to the previous page, then Home when there is none', async () => {
    const user = userEvent.setup()
    render(<App />)
    await user.click(screen.getByRole('button', { name: /^Learn/ }))
    await user.click(screen.getByRole('button', { name: /^Live Now/ }))
    await user.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByRole('button', { name: /^Learn/ })).toHaveClass('is-active')
    await user.click(screen.getByRole('button', { name: 'Back' }))
    expect(workbench()).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Back' }))
    expect(workbench()).toBeInTheDocument()
  })

  it('both buttons are reachable by Tab and by arrow keys', async () => {
    const user = userEvent.setup()
    render(<App />)
    const home = screen.getByRole('button', { name: 'Home' })
    const back = screen.getByRole('button', { name: 'Back' })
    home.focus()
    await user.tab()
    expect(back).toHaveFocus()
    await user.keyboard('{ArrowLeft}')
    expect(home).toHaveFocus()
    await user.keyboard('{ArrowRight}')
    expect(back).toHaveFocus()
  })
})
