import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { ErrorNotice } from '../components/ErrorNotice'
import { toFriendlyMessage } from '../app/friendlyError'

const base = { headline: 'ChannelForge could not accept this lineup', whatHappened: 'The accept step stopped.', whatToDo: 'Try again.' }

describe('ErrorNotice server message', () => {
  it('shows a plain message up front and keeps the full text under Details', async () => {
    render(<ErrorNotice message={{ ...base, details: { cause: 'Refused.', message: 'The playlist is not available right now.' } }} />)
    expect(screen.getByText('The message says: "The playlist is not available right now." The full message is under Details.')).toBeVisible()
    expect(screen.queryByText('The playlist is not available right now.')).toBeNull()
    await userEvent.setup().click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('The playlist is not available right now.')).toBeVisible()
  })

  it('falls back to the pointer sentence for a technical message and keeps its text under Details', async () => {
    render(<ErrorNotice message={{ ...base, details: { cause: 'Refused.', message: '{"error":"no"}' } }} />)
    expect(screen.getByText('ChannelForge also kept a technical message about this. It is under Details.')).toBeVisible()
    expect(screen.queryByText(/The message says/)).toBeNull()
    await userEvent.setup().click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('{"error":"no"}')).toBeVisible()
  })

  it('does not call a network error a server message', () => {
    render(<ErrorNotice message={toFriendlyMessage(new TypeError('Failed to fetch'), { ...base, details: { cause: 'x' } })} />)
    expect(screen.queryByText(/server also sent|server said/i)).toBeNull()
  })

  it('adds no sentence when there is no server message', () => {
    render(<ErrorNotice message={{ ...base, details: { cause: 'Refused.' } }} />)
    expect(screen.queryByText(/ChannelForge also kept a technical message|The message says/)).toBeNull()
  })
})
