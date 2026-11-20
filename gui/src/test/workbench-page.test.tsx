import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { WorkbenchPage } from '../pages/WorkbenchPage'

describe('workbench current-state summary', () => {
  it('keeps accepted workspace copy consistent with the server status', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({
      lineupAccepted: true,
      sourcesStatus: 'up-to-date',
      playlistStatus: 'ready',
      guideStatus: 'ready',
      canRefreshSources: true,
      sourcesGuidance: 'Saved sources are ready.',
    })

    const { container } = render(
      <WorkbenchPage
        fetchStatus={fetchStatus}
        onOpenGallery={vi.fn()}
        onOpenSetup={vi.fn()}
      />,
    )

    expect(await screen.findByText('An accepted lineup is available.')).toBeInTheDocument()
    expect(screen.getByText('Saved source configuration is available')).toBeInTheDocument()
    expect(screen.getByText('Your accepted lineup is available')).toBeInTheDocument()
    expect(screen.getByText('Ready to review')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2, name: 'Saved lineup ready' })).toBeInTheDocument()
    expect(screen.queryByText('Not accepted yet')).not.toBeInTheDocument()
    expect(screen.queryByText('Nothing has been accepted yet')).not.toBeInTheDocument()
    expect(screen.queryByText('There is nothing to review yet because no playlist or guide has been added.')).not.toBeInTheDocument()
    expect(container.querySelectorAll('.step-complete')).toHaveLength(4)
    expect(fetchStatus).toHaveBeenCalledTimes(1)
  })

  it('fails honestly when server status is unavailable', async () => {
    const fetchStatus = vi.fn().mockResolvedValue(null)

    render(
      <WorkbenchPage
        fetchStatus={fetchStatus}
        onOpenGallery={vi.fn()}
        onOpenSetup={vi.fn()}
      />,
    )

    expect(await screen.findByRole('heading', { level: 2, name: 'Status unavailable' })).toBeInTheDocument()
    expect(screen.getAllByText('Unavailable')).toHaveLength(3)
    expect(screen.getAllByText('ChannelForge status unavailable')).toHaveLength(3)
    expect(screen.queryByText('Not configured')).not.toBeInTheDocument()
    expect(screen.queryByText('Not built')).not.toBeInTheDocument()
    expect(fetchStatus).toHaveBeenCalledTimes(1)
  })

  it('retains beginner first-run copy when no lineup is accepted', async () => {
    const fetchStatus = vi.fn().mockResolvedValue({
      lineupAccepted: false,
      sourcesStatus: 'not-enrolled',
      playlistStatus: 'not-enrolled',
      guideStatus: 'no-guide',
      canRefreshSources: false,
    })

    const { container } = render(
      <WorkbenchPage
        fetchStatus={fetchStatus}
        onOpenGallery={vi.fn()}
        onOpenSetup={vi.fn()}
      />,
    )

    expect(await screen.findByText('No lineup has been accepted yet.')).toBeInTheDocument()
    expect(screen.getByText('Not accepted yet')).toBeInTheDocument()
    expect(screen.getByText('Nothing has been accepted yet')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 2, name: 'Nothing to review yet' })).toBeInTheDocument()
    expect(screen.getByText('There is nothing to review yet because no playlist or guide has been added.')).toBeInTheDocument()
    expect(container.querySelectorAll('.step-current')).toHaveLength(1)
    expect(container.querySelectorAll('.step-complete')).toHaveLength(0)
    expect(fetchStatus).toHaveBeenCalledTimes(1)
  })
})
