import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import App from '../App'
import { ChannelLineupPage } from '../pages/ChannelLineupPage'
import type { LineupChannel, LineupFetcher } from '../app/lineup'

const channel = (n: number, over: Partial<LineupChannel> = {}): LineupChannel =>
  ({ id: `id-${n}`, number: n, name: `Test Channel ${n}`, group: 'Test Group', current: null, next: null, ...over })

describe('Channel lineup page', () => {
  it('lists channels with number, name, group, and now/next', async () => {
    const fetchPage: LineupFetcher = async () => ({
      generation: 'g', total: 1,
      items: [channel(7, { current: { title: 'Test Show', startUtc: 'a', stopUtc: 'b' }, next: { title: 'Test Film', startUtc: 'b', stopUtc: 'c' } })],
    })
    render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    const row = await screen.findByRole('listitem', { name: '7, Test Channel 7, Test Group, Now: Test Show · Next: Test Film' })
    expect(row).toHaveTextContent('Test Group')
    expect(row).toHaveTextContent('Now: Test Show')
  })

  it('shows a dash when the channel number is missing and no guide line', async () => {
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 1, items: [channel(0, { number: null })] })} onOpenSetup={() => {}} />)
    const row = await screen.findByRole('listitem', { name: 'No number, Test Channel 0, Test Group' })
    expect(row).toHaveTextContent('—')
    expect(row).not.toHaveTextContent('Now:')
  })

  it('shows an empty state with a Setup step', async () => {
    const user = userEvent.setup()
    const onOpenSetup = vi.fn()
    render(<ChannelLineupPage fetchPage={async () => ({ generation: 'g', total: 0, items: [] })} onOpenSetup={onOpenSetup} />)
    expect(await screen.findByRole('heading', { name: 'No channels saved yet' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Go to Setup' }))
    expect(onOpenSetup).toHaveBeenCalledOnce()
  })

  it('shows a plain error and retries', async () => {
    const user = userEvent.setup()
    const fetchPage = vi.fn<LineupFetcher>().mockResolvedValueOnce(null).mockResolvedValueOnce({ generation: 'g', total: 1, items: [channel(1)] })
    render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Your channels could not be loaded')
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Test Channel 1')).toBeVisible()
  })

  it('shows more channels with a keyboard-reachable button', async () => {
    const user = userEvent.setup()
    const fetchPage = vi.fn<LineupFetcher>()
      .mockResolvedValueOnce({ generation: 'g', total: 2, items: [channel(1)] })
      .mockResolvedValueOnce({ generation: 'g', total: 2, items: [channel(2)] })
    render(<ChannelLineupPage fetchPage={fetchPage} onOpenSetup={() => {}} />)
    await screen.findByText('Test Channel 1')
    expect(screen.getByRole('status')).toHaveTextContent('Showing 1 of 2 channels')
    await user.tab()
    await user.tab()
    expect(screen.getByRole('button', { name: 'Show more channels' })).toHaveFocus()
    await user.keyboard('{Enter}')
    expect(await screen.findByText('Test Channel 2')).toBeVisible()
    expect(fetchPage).toHaveBeenLastCalledWith(1, 'g')
    expect(screen.queryByRole('button', { name: 'Show more channels' })).not.toBeInTheDocument()
  })

  it('is an enabled navigation entry', async () => {
    const user = userEvent.setup()
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 503 }))
    render(<App />)
    const entry = screen.getByRole('button', { name: /Channel lineup/ })
    expect(entry).toBeEnabled()
    await user.click(entry)
    expect(screen.getByRole('heading', { level: 1, name: 'Your channel lineup' })).toBeInTheDocument()
  })
})
