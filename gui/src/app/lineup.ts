export type LineupProgramme = { title: string; startUtc: string; stopUtc: string }

export type LineupChannel = {
  id: string
  number: number | null
  name: string
  group: string
  current: LineupProgramme | null
  next: LineupProgramme | null
}

export type LineupPage = { generation: string; total: number; items: LineupChannel[] }

// 'changed' means the saved lineup changed while paging; the page starts over from the first channels.
export type LineupFetcher = (offset: number, generation: string | null) => Promise<LineupPage | 'changed' | null>

function readProgramme(value: unknown): LineupProgramme | null {
  const row = value as Partial<LineupProgramme> | null
  return row && typeof row.title === 'string' && typeof row.startUtc === 'string' && typeof row.stopUtc === 'string'
    ? { title: row.title, startUtc: row.startUtc, stopUtc: row.stopUtc }
    : null
}

function readChannel(value: unknown): LineupChannel | null {
  const row = value as Record<string, unknown> | null
  if (!row || typeof row.id !== 'string' || typeof row.name !== 'string') return null
  return {
    id: row.id,
    number: typeof row.number === 'number' ? row.number : null,
    name: row.name,
    group: typeof row.group === 'string' ? row.group : '',
    current: readProgramme(row.current),
    next: readProgramme(row.next),
  }
}

export async function fetchLineupPage(offset: number, generation: string | null, request: typeof fetch = fetch): Promise<LineupPage | 'changed' | null> {
  const query = generation ? `?limit=100&offset=${offset}&generation=${generation}` : '?limit=100'
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
