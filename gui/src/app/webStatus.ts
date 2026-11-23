export type SourcesStatus = 'not-enrolled' | 'saved' | 'up-to-date' | 'changes-found' | 'needs-attention' | 'source-unavailable'
export type PlaylistStatus = 'not-enrolled' | 'ready' | 'changes-found' | 'source-unavailable'
export type GuideStatus = 'no-guide' | 'not-enrolled' | 'ready' | 'changes-found' | 'source-unavailable' | 'needs-attention'
export type SourceRowState = 'ready' | 'changes-found' | 'source-unavailable' | 'not-refreshed'
export type SourceRow = { kind: 'playlist' | 'guide'; label: string; state: SourceRowState }

export type WebStatusSnapshot = {
  lineupAccepted: boolean
  sourcesStatus?: SourcesStatus
  playlistStatus?: PlaylistStatus
  guideStatus?: GuideStatus
  lastCheckedUtc?: string | null
  snapshotUtc?: string | null
  coverageStartUtc?: string | null
  coverageEndUtc?: string | null
  canRefreshSources?: boolean
  sourcesGuidance?: string
  sources?: SourceRow[]
}

export type WebStatusFetcher = () => Promise<WebStatusSnapshot | null>

export type SourceRefreshResult = {
  status: 'UP_TO_DATE' | 'CHANGES_FOUND'
  reviewNeeded: boolean
  reviewNeededCount: number
}

export type SourceRefreshAction = () => Promise<SourceRefreshResult | null>

type JsonRecord = Record<string, unknown>

function isJsonRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

const sourceStatuses: SourcesStatus[] = ['not-enrolled', 'saved', 'up-to-date', 'changes-found', 'needs-attention', 'source-unavailable']
const playlistStatuses: PlaylistStatus[] = ['not-enrolled', 'ready', 'changes-found', 'source-unavailable']
const guideStatuses: GuideStatus[] = ['no-guide', 'not-enrolled', 'ready', 'changes-found', 'source-unavailable', 'needs-attention']

function isOneOf<T extends string>(value: unknown, values: T[]): value is T {
  return typeof value === 'string' && values.includes(value as T)
}

const sourceRowStates: SourceRowState[] = ['ready', 'changes-found', 'source-unavailable', 'not-refreshed']

// A missing or malformed list means "no per-source rows": the single summary still shows.
function normalizeSourceRows(value: unknown): SourceRow[] | undefined {
  if (!Array.isArray(value)) return undefined
  const rows: SourceRow[] = []
  for (const item of value) {
    if (!isJsonRecord(item) || typeof item.Label !== 'string') continue
    const kind = item.Kind === 'M3U' ? 'playlist' : item.Kind === 'XMLTV' ? 'guide' : null
    if (kind === null) continue
    rows.push({ kind, label: item.Label, state: isOneOf(item.State, sourceRowStates) ? item.State : 'not-refreshed' })
  }
  return rows
}

function normalizeStatus(payload: JsonRecord): WebStatusSnapshot | null {
  if (payload.LineupStatus !== 'not-accepted' && payload.LineupStatus !== 'accepted') return null
  const lineupAccepted = payload.LineupStatus === 'accepted'
  if (!Object.prototype.hasOwnProperty.call(payload, 'SourcesStatus')) return { lineupAccepted }
  const sourcesStatus = isOneOf(payload.SourcesStatus, sourceStatuses) ? payload.SourcesStatus : 'not-enrolled'
  const playlistStatus = isOneOf(payload.PlaylistStatus, playlistStatuses) ? payload.PlaylistStatus : 'not-enrolled'
  const guideStatus = isOneOf(payload.GuideStatus, guideStatuses) ? payload.GuideStatus : 'no-guide'
  const lastCheckedUtc = payload.LastCheckedUtc === null || typeof payload.LastCheckedUtc === 'string' ? (payload.LastCheckedUtc as string | null) : null
  const snapshotUtc = typeof payload.SnapshotUtc === 'string' ? payload.SnapshotUtc : null
  const coverageStartUtc = typeof payload.CoverageStartUtc === 'string' ? payload.CoverageStartUtc : null
  const coverageEndUtc = typeof payload.CoverageEndUtc === 'string' ? payload.CoverageEndUtc : null
  return {
    lineupAccepted,
    sourcesStatus,
    playlistStatus,
    guideStatus,
    lastCheckedUtc,
    snapshotUtc,
    coverageStartUtc,
    coverageEndUtc,
    canRefreshSources: payload.CanRefreshSources === true,
    sourcesGuidance: typeof payload.SourcesGuidance === 'string' ? payload.SourcesGuidance : undefined,
    sources: normalizeSourceRows(payload.Sources),
  }
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

    return normalizeStatus(payload)
  } catch {
    return null
  }
}

export async function refreshSavedSources(request: typeof fetch = fetch): Promise<SourceRefreshResult | null> {
  try {
    const response = await request('/api/sources/refresh', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: '',
    })
    if (response.status !== 200) return null
    const payload: unknown = await response.json()
    if (
      !isJsonRecord(payload) ||
      payload.Version !== 'source-refresh/v1' ||
      (payload.Status !== 'UP_TO_DATE' && payload.Status !== 'CHANGES_FOUND') ||
      typeof payload.ReviewNeeded !== 'boolean' ||
      typeof payload.ReviewNeededCount !== 'number' ||
      !Number.isInteger(payload.ReviewNeededCount) ||
      payload.ReviewNeededCount < 0
    ) {
      return null
    }
    return {
      status: payload.Status,
      reviewNeeded: payload.ReviewNeeded,
      reviewNeededCount: payload.ReviewNeededCount,
    }
  } catch {
    return null
  }
}

export type SourceRemoveResult = { ok: true } | { ok: false; message: string }
export type SourceRemoveAction = (source: Pick<SourceRow, 'kind' | 'label'>) => Promise<SourceRemoveResult>

const removeFailureMessage = 'The source could not be removed. Your saved sources were not changed.'

export async function removeSavedSource(source: Pick<SourceRow, 'kind' | 'label'>, request: typeof fetch = fetch): Promise<SourceRemoveResult> {
  try {
    const response = await request('/api/sources/remove', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ Label: source.label, Kind: source.kind === 'guide' ? 'XMLTV' : 'M3U' }),
    })
    const payload: unknown = await response.json()
    if (response.status === 200 && isJsonRecord(payload) && payload.Version === 'source-remove/v1' && payload.Status === 'REMOVED') return { ok: true }
    // Only the server's plain-words message is shown; anything else gets the fixed text.
    if (isJsonRecord(payload) && typeof payload.Message === 'string' && response.status >= 400 && response.status < 500) return { ok: false, message: payload.Message }
    return { ok: false, message: removeFailureMessage }
  } catch {
    return { ok: false, message: removeFailureMessage }
  }
}
