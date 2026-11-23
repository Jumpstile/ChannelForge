import { describe, expect, it, vi } from 'vitest'
import { fetchWebStatus, refreshSavedSources } from '../app/webStatus'

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
  it('consumes the safe saved-source refresh result', async () => {
    const request = vi.fn().mockResolvedValue(response(200, {
      Version: 'source-refresh/v1',
      Status: 'CHANGES_FOUND',
      ReviewNeeded: true,
      ReviewNeededCount: 1,
    }))

    await expect(refreshSavedSources(request as unknown as typeof fetch)).resolves.toEqual({
      status: 'CHANGES_FOUND',
      reviewNeeded: true,
      reviewNeededCount: 1,
    })
    expect(request).toHaveBeenCalledWith('/api/sources/refresh', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: '',
    })
  })

  it('reads the per-source list when present and ignores it when absent', async () => {
    const withSources = vi.fn().mockResolvedValue(response(200, {
      ...acceptedPayload,
      SourcesStatus: 'saved',
      Sources: [{ Kind: 'M3U', Label: 'Home', State: 'ready' }, { Kind: 'XMLTV', Label: 'Guide', State: 'source-unavailable' }, { Kind: 'bad' }],
    }))
    const withoutSources = vi.fn().mockResolvedValue(response(200, { ...acceptedPayload, SourcesStatus: 'saved' }))

    const a = await fetchWebStatus(withSources as unknown as typeof fetch)
    expect(a?.sources).toEqual([
      { kind: 'playlist', label: 'Home', state: 'ready' },
      { kind: 'guide', label: 'Guide', state: 'source-unavailable' },
    ])
    expect((await fetchWebStatus(withoutSources as unknown as typeof fetch))?.sources).toBeUndefined()
  })

  it('reads snapshot time and coverage window when sent and leaves them empty when not', async () => {
    const sent = vi.fn().mockResolvedValue(response(200, {
      ...acceptedPayload,
      SourcesStatus: 'saved',
      SnapshotUtc: '2026-01-01T00:00:00Z',
      CoverageStartUtc: '2026-01-01T00:00:00Z',
      CoverageEndUtc: '2026-01-03T00:00:00Z',
    }))
    const absent = vi.fn().mockResolvedValue(response(200, { ...acceptedPayload, SourcesStatus: 'saved' }))

    const a = await fetchWebStatus(sent as unknown as typeof fetch)
    expect([a?.snapshotUtc, a?.coverageStartUtc, a?.coverageEndUtc]).toEqual(['2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-03T00:00:00Z'])
    const b = await fetchWebStatus(absent as unknown as typeof fetch)
    expect([b?.snapshotUtc, b?.coverageStartUtc, b?.coverageEndUtc]).toEqual([null, null, null])
  })
})
