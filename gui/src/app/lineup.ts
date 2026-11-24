export type LineupProgramme = { title: string; startUtc: string; stopUtc: string }

export type LineupChannel = {
  id: string
  number: number | null
  name: string
  group: string
  current: LineupProgramme | null
  next: LineupProgramme | null
  // Only present when the page was asked for a time window: every accepted program that overlaps it, in start order.
  programmes?: LineupProgramme[]
}

export type LineupPage = { generation: string; total: number; items: LineupChannel[] }

// 'changed' means the saved lineup changed while paging; the page starts over from the first channels.
export type LineupFetcher = (offset: number, generation: string | null) => Promise<LineupPage | 'changed' | null>

// A UTC schedule window of at most three hours, like 2026-01-01T10:00:00Z.
export type LineupWindow = { from: string; to: string }
export type LineupWindowFetcher = (offset: number, generation: string | null, window: LineupWindow) => Promise<LineupPage | 'changed' | null>

function readProgramme(value: unknown): LineupProgramme | null {
  const row = value as Partial<LineupProgramme> | null
  return row && typeof row.title === 'string' && typeof row.startUtc === 'string' && typeof row.stopUtc === 'string'
    ? { title: row.title, startUtc: row.startUtc, stopUtc: row.stopUtc }
    : null
}

function readChannel(value: unknown): LineupChannel | null {
  const row = value as Record<string, unknown> | null
  if (!row || typeof row.id !== 'string' || typeof row.name !== 'string') return null
  const programmes = Array.isArray(row.programmes) ? row.programmes.map(readProgramme) : undefined
  if (programmes?.some((item) => item === null)) return null
  return {
    id: row.id,
    number: typeof row.number === 'number' ? row.number : null,
    name: row.name,
    group: typeof row.group === 'string' ? row.group : '',
    current: readProgramme(row.current),
    next: readProgramme(row.next),
    ...(programmes ? { programmes: programmes as LineupProgramme[] } : {}),
  }
}

export async function fetchLineupPage(offset: number, generation: string | null, request: typeof fetch = fetch, window?: LineupWindow): Promise<LineupPage | 'changed' | null> {
  let query = generation ? `?limit=100&offset=${offset}&generation=${generation}` : '?limit=100'
  if (window) query += `&from=${encodeURIComponent(window.from)}&to=${encodeURIComponent(window.to)}`
  try {
    const response = await request(`/api/lineup/channels${query}`, { method: 'GET', headers: { Accept: 'application/json' } })
    if (response.status === 409) return 'changed'
    if (response.status !== 200) return null
    const body = await response.json()
    if (typeof body?.generation !== 'string' || typeof body?.total !== 'number' || !Array.isArray(body?.items)) return null
    const items = body.items.map(readChannel)
    if (items.some((item: LineupChannel | null) => item === null)) return null
    return { generation: body.generation, total: body.total, items }
  } catch {
    return null
  }
}

export const fetchLineupWindowPage: LineupWindowFetcher = (offset, generation, window) => fetchLineupPage(offset, generation, fetch, window)

export function formatUtcTime(value: string): string {
  return new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC' }).format(new Date(value))
}
