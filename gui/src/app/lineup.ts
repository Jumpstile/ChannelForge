import { failureForStatus, loadFailure, type LoadFailure } from './friendlyError'

export type LineupProgramme = { title: string; startUtc: string; stopUtc: string }

// The only values the lineup route emits. Anything else makes the page fail plainly.
export type LogoStatus = 'missing' | 'present'
export type GuideState = 'none' | 'bound'
export type AttentionReason = 'no-guide' | 'no-logo'

export type LineupChannel = {
  id: string
  number: number | null
  name: string
  group: string
  logoStatus: LogoStatus
  guideState: GuideState
  attention: AttentionReason[]
  current: LineupProgramme | null
  next: LineupProgramme | null
  // Only present when the page was asked for a time window: every accepted program that overlaps it, in start order.
  programmes?: LineupProgramme[]
}

export type LineupPage = { generation: string; total: number; items: LineupChannel[] }

// 'changed' means the saved lineup changed while paging; the page starts over from the first channels.
// A LoadFailure says why the read failed; null (for example from a test double) means no reason is known.
export type LineupResult = LineupPage | 'changed' | LoadFailure | null
export type LineupFetcher = (offset: number, generation: string | null) => Promise<LineupResult>

// A UTC schedule window of at most three hours, like 2026-01-01T10:00:00Z.
export type LineupWindow = { from: string; to: string }
export type LineupWindowFetcher = (offset: number, generation: string | null, window: LineupWindow) => Promise<LineupResult>

function readProgramme(value: unknown): LineupProgramme | null {
  const row = value as Partial<LineupProgramme> | null
  return row && typeof row.title === 'string' && typeof row.startUtc === 'string' && typeof row.stopUtc === 'string'
    ? { title: row.title, startUtc: row.startUtc, stopUtc: row.stopUtc }
    : null
}

const readAttention = (value: unknown): AttentionReason[] | null =>
  Array.isArray(value) && value.every((item) => item === 'no-guide' || item === 'no-logo') ? (value as AttentionReason[]) : null

function readChannel(value: unknown): LineupChannel | null {
  const row = value as Record<string, unknown> | null
  if (!row || typeof row.id !== 'string' || typeof row.name !== 'string') return null
  const attention = readAttention(row.attention)
  if ((row.logoStatus !== 'missing' && row.logoStatus !== 'present') || (row.guideState !== 'none' && row.guideState !== 'bound') || !attention) return null
  const programmes = Array.isArray(row.programmes) ? row.programmes.map(readProgramme) : undefined
  if (programmes?.some((item) => item === null)) return null
  return {
    id: row.id,
    number: typeof row.number === 'number' ? row.number : null,
    name: row.name,
    group: typeof row.group === 'string' ? row.group : '',
    logoStatus: row.logoStatus,
    guideState: row.guideState,
    attention,
    current: readProgramme(row.current),
    next: readProgramme(row.next),
    ...(programmes ? { programmes: programmes as LineupProgramme[] } : {}),
  }
}

export async function fetchLineupPage(offset: number, generation: string | null, request: typeof fetch = fetch, window?: LineupWindow): Promise<LineupResult> {
  let query = generation ? `?limit=100&offset=${offset}&generation=${generation}` : '?limit=100'
  if (window) query += `&from=${encodeURIComponent(window.from)}&to=${encodeURIComponent(window.to)}`
  let response: Response
  try {
    response = await request(`/api/lineup/channels${query}`, { method: 'GET', headers: { Accept: 'application/json' } })
  } catch {
    return loadFailure('unreachable')
  }
  if (response.status === 409) return 'changed'
  if (response.status !== 200) return failureForStatus(response.status)
  try {
    const body = await response.json()
    if (typeof body?.generation !== 'string' || typeof body?.total !== 'number' || !Array.isArray(body?.items)) return loadFailure('not-understood')
    const items = body.items.map(readChannel)
    if (items.some((item: LineupChannel | null) => item === null)) return loadFailure('not-understood')
    return { generation: body.generation, total: body.total, items }
  } catch {
    return loadFailure('not-understood')
  }
}

export const fetchLineupWindowPage: LineupWindowFetcher = (offset, generation, window) => fetchLineupPage(offset, generation, fetch, window)

export function formatUtcTime(value: string): string {
  return new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC' }).format(new Date(value))
}
