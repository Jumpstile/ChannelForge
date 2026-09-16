import { describe, expect, it, vi } from 'vitest'
import { fetchWebStatus } from '../app/webStatus'

function response(status: number, payload: unknown) {
  return {
    status,
    json: vi.fn().mockResolvedValue(payload),
  } as unknown as Response
}

const acceptedPayload = {
  Service: 'ChannelForge',
  Version: '0.1.0',
  Status: 'ok',
  Message: 'ChannelForge is running',
  LineupStatus: 'accepted',
  Guidance: 'An accepted lineup is available',
  NextAction: 'Open Guided Setup to review',
  ReadOnly: true,
  ProviderMutation: 'none',
  DownstreamMutation: 'none',
  GuidePublication: 'none',
  AcceptedStateMutation: 'none',
}

describe('web status client', () => {
  it('consumes only the safe accepted-lineup summary from the read-only GET endpoint', async () => {
    const request = vi.fn().mockResolvedValue(response(200, acceptedPayload))

    await expect(fetchWebStatus(request as unknown as typeof fetch)).resolves.toEqual({ lineupAccepted: true })
    expect(request).toHaveBeenCalledTimes(1)
    expect(request).toHaveBeenCalledWith('/api/status', {
      method: 'GET',
      headers: { Accept: 'application/json' },
    })
    expect(request.mock.calls[0][1]).not.toHaveProperty('body')
  })

  it('consumes the safe not-accepted summary', async () => {
    const request = vi.fn().mockResolvedValue(response(200, { ...acceptedPayload, LineupStatus: 'not-accepted' }))

    await expect(fetchWebStatus(request as unknown as typeof fetch)).resolves.toEqual({ lineupAccepted: false })
  })

  it('degrades safely for unavailable, failed, and invalid responses', async () => {
    const unavailableRequest = vi.fn().mockResolvedValue(response(503, { Error: 'status-unavailable' }))
    const failedRequest = vi.fn().mockRejectedValue(new Error('network failure'))
    const invalidRequest = vi.fn().mockResolvedValue(response(200, { Status: 'ok', LineupStatus: 'unknown' }))

    await expect(fetchWebStatus(unavailableRequest as unknown as typeof fetch)).resolves.toBeNull()
    await expect(fetchWebStatus(failedRequest as unknown as typeof fetch)).resolves.toBeNull()
    await expect(fetchWebStatus(invalidRequest as unknown as typeof fetch)).resolves.toBeNull()
  })

  it('never makes a state-changing request', async () => {
    const request = vi.fn().mockResolvedValue(response(200, acceptedPayload))

    await fetchWebStatus(request as unknown as typeof fetch)

    for (const call of request.mock.calls) {
      expect(call[0]).toBe('/api/status')
      expect(call[1]?.method).toBe('GET')
      expect(call[1]).not.toHaveProperty('body')
    }
  })
})
