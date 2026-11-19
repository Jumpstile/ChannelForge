import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
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
    expect(screen.getByText(/your accepted lineup is not changed here/i)).toBeInTheDocument()
  })

  it('renders the accepted status and review next action', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({ lineupAccepted: true })

    render(<StatusDashboard fetchStatus={fetchStatus} />)

    expect(await screen.findByText('An accepted lineup is available.')).toBeInTheDocument()
    expect(screen.getByText('Open Guided Setup to review.')).toBeInTheDocument()
  })
  it('shows saved source status and refresh actions without exposing internals', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({
      lineupAccepted: true,
      sourcesStatus: 'saved',
      playlistStatus: 'ready',
      guideStatus: 'no-guide',
      lastCheckedUtc: '2026-01-01T00:00:00Z',
      canRefreshSources: true,
    })
    const refreshSources = vi.fn().mockResolvedValue({ status: 'UP_TO_DATE', reviewNeeded: false, reviewNeededCount: 0 })
    const replaceSources = vi.fn()

    render(<StatusDashboard fetchStatus={fetchStatus} refreshSources={refreshSources} onReplaceSources={replaceSources} />)

    expect((await screen.findAllByText('Sources saved')).length).toBeGreaterThan(0)
    expect(screen.getAllByText('Ready').length).toBeGreaterThan(0)
    expect(screen.getByText('No guide selected')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Replace sources' })).toBeInTheDocument()
    expect(screen.queryByText(/managed-sources|hash|generation/i)).not.toBeInTheDocument()
  })

  it('shows one row per saved source and does not blame healthy sources for one failure', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({
      lineupAccepted: true,
      sourcesStatus: 'source-unavailable',
      playlistStatus: 'ready',
      guideStatus: 'source-unavailable',
      sources: [
        { kind: 'playlist', label: 'Home playlist', state: 'ready' },
        { kind: 'guide', label: 'Sports guide', state: 'source-unavailable' },
        { kind: 'guide', label: 'News guide', state: 'ready' },
        { kind: 'guide', label: 'Weekend guide', state: 'not-refreshed' },
      ],
    })

    render(<StatusDashboard fetchStatus={fetchStatus} />)

    expect(await screen.findByText('Sports guide')).toBeInTheDocument()
    expect(screen.getAllByText('Up to date')).toHaveLength(2)
    expect(screen.getAllByText(/^Needs attention: this source could not be read/)).toHaveLength(1)
    expect(screen.getByText('Not refreshed yet')).toBeInTheDocument()
    expect(screen.queryByText(/https?:\/\/|token/i)).not.toBeInTheDocument()
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

describe('remove one saved source', () => {
  const twoSources = {
    lineupAccepted: true,
    sourcesStatus: 'saved',
    sources: [
      { kind: 'playlist', label: 'Home playlist', state: 'ready' },
      { kind: 'playlist', label: 'Backup playlist', state: 'ready' },
    ],
  }

  it('asks first, and keeping the source changes nothing', async () => {
    const removeSource = vi.fn()
    render(<StatusDashboard fetchStatus={vi.fn().mockResolvedValue(twoSources)} removeSource={removeSource} />)

    await userEvent.click(await screen.findByRole('button', { name: 'Remove Backup playlist' }))
    expect(screen.getByText(/Your other sources stay as they are/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Keep this source' }))

    expect(removeSource).not.toHaveBeenCalled()
    expect(screen.getByText('Backup playlist')).toBeInTheDocument()
  })

  it('removes only the confirmed source and shows the list the server returns', async () => {
    const fetchStatus = vi.fn().mockResolvedValueOnce(twoSources).mockResolvedValue({ ...twoSources, sources: [twoSources.sources[0]] })
    const removeSource = vi.fn().mockResolvedValue({ ok: true })
    render(<StatusDashboard fetchStatus={fetchStatus} removeSource={removeSource} />)

    await userEvent.click(await screen.findByRole('button', { name: 'Remove Backup playlist' }))
    await userEvent.click(screen.getByRole('button', { name: 'Yes, remove this source' }))

    expect(removeSource).toHaveBeenCalledWith({ kind: 'playlist', label: 'Backup playlist', state: 'ready' })
    expect(await screen.findByText(/Removed "Backup playlist"/)).toBeInTheDocument()
    expect(screen.getByText('Home playlist')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Remove Backup playlist' })).not.toBeInTheDocument()
  })

  it('shows a plain message and keeps the source when the remove fails', async () => {
    const removeSource = vi.fn().mockResolvedValue({ ok: false, message: 'The source could not be removed. Your saved sources were not changed.' })
    render(<StatusDashboard fetchStatus={vi.fn().mockResolvedValue(twoSources)} removeSource={removeSource} />)

    await userEvent.click(await screen.findByRole('button', { name: 'Remove Backup playlist' }))
    await userEvent.click(screen.getByRole('button', { name: 'Yes, remove this source' }))

    expect(await screen.findByText(/could not be removed/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Remove Backup playlist' })).toBeInTheDocument()
  })
})
