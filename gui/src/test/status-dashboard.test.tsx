import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { StatusDashboard } from '../components/StatusDashboard'

const unavailable = vi.fn().mockResolvedValue(null)

describe('read-only status dashboard', () => {
  it('renders a loading state while the status request is pending', () => {
    const fetchStatus = vi.fn(() => new Promise<null>(() => undefined))

    render(<StatusDashboard fetchStatus={fetchStatus} />)

    expect(screen.getByRole('heading', { level: 2, name: 'Checking ChannelForge status' })).toBeInTheDocument()
    expect(screen.getByText(/read-only status/i)).toBeInTheDocument()
  })

  it('renders the not-accepted status and beginner next action', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({ lineupAccepted: false })

    render(<StatusDashboard fetchStatus={fetchStatus} />)

    expect(await screen.findByText('No lineup has been accepted yet.')).toBeInTheDocument()
    expect(screen.getByText('Open Guided Setup to begin.')).toBeInTheDocument()
    expect(screen.getByText(/this page can show status, but it cannot change your lineup yet/i)).toBeInTheDocument()
  })

  it('renders the accepted status and review next action', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({ lineupAccepted: true })

    render(<StatusDashboard fetchStatus={fetchStatus} />)

    expect(await screen.findByText('An accepted lineup is available.')).toBeInTheDocument()
    expect(screen.getByText('Open Guided Setup to review.')).toBeInTheDocument()
  })

  it('renders a safe unavailable state for a 503 result', async () => {
    render(<StatusDashboard fetchStatus={unavailable} />)

    expect(await screen.findByRole('heading', { level: 2, name: 'ChannelForge status is unavailable' })).toBeInTheDocument()
    expect(screen.getByText(/could not read the local server status/i)).toBeInTheDocument()
  })

  it('renders a safe unavailable state when fetching fails', async () => {
    const fetchStatus = vi.fn().mockRejectedValue(new Error('not shown'))

    render(<StatusDashboard fetchStatus={fetchStatus} />)

    expect(await screen.findByRole('heading', { level: 2, name: 'ChannelForge status is unavailable' })).toBeInTheDocument()
    expect(screen.queryByText('not shown')).not.toBeInTheDocument()
  })

  it('does not render sensitive or implementation-only values', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({ lineupAccepted: true })

    render(<StatusDashboard fetchStatus={fetchStatus} />)
    await waitFor(() => expect(screen.getByText('An accepted lineup is available.')).toBeInTheDocument())

    const renderedText = document.body.textContent ?? ''
    expect(renderedText).not.toMatch(/https?:\/\/|password|private|hash|generation|parser/i)
  })
})
