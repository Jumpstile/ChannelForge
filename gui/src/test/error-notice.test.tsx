import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { ErrorNotice } from '../components/ErrorNotice'
import { toFriendlyMessage } from '../app/friendlyError'

const base = { headline: 'ChannelForge could not accept this lineup', whatHappened: 'The accept step stopped.', whatToDo: 'Try again.' }

describe('ErrorNotice server message', () => {
  it('tells the user a technical message and keeps its text under Details', async () => {
    render(<ErrorNotice message={{ ...base, details: { cause: 'Refused.', message: 'Server says: no.' } }} />)
    expect(screen.getByText(/ChannelForge also kept a technical message/)).toBeVisible()
    expect(screen.queryByText('Server says: no.')).toBeNull()
    await userEvent.setup().click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('Server says: no.')).toBeVisible()
  })

  it('does not call a network error a server message', () => {
    render(<ErrorNotice message={toFriendlyMessage(new TypeError('Failed to fetch'), { ...base, details: { cause: 'x' } })} />)
    expect(screen.queryByText(/server also sent/i)).toBeNull()
  })

  it('adds no sentence when there is no server message', () => {
    render(<ErrorNotice message={{ ...base, details: { cause: 'Refused.' } }} />)
    expect(screen.queryByText(/ChannelForge also kept a technical message/)).toBeNull()
  })
})
