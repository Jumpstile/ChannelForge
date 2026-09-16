export type WebStatusSnapshot = {
  lineupAccepted: boolean
}

export type WebStatusFetcher = () => Promise<WebStatusSnapshot | null>

type JsonRecord = Record<string, unknown>

function isJsonRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export async function fetchWebStatus(request: typeof fetch = fetch): Promise<WebStatusSnapshot | null> {
  try {
    const response = await request('/api/status', {
      method: 'GET',
      headers: { Accept: 'application/json' },
    })

    if (response.status !== 200) return null

    const payload: unknown = await response.json()
    if (
      !isJsonRecord(payload) ||
      payload.Service !== 'ChannelForge' ||
      payload.Status !== 'ok' ||
      payload.Message !== 'ChannelForge is running' ||
      payload.ReadOnly !== true
    ) {
      return null
    }

    if (payload.LineupStatus === 'not-accepted') return { lineupAccepted: false }
    if (payload.LineupStatus === 'accepted') return { lineupAccepted: true }
    return null
  } catch {
    return null
  }
}
