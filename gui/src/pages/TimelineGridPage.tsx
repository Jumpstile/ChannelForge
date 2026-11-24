import { useEffect, useState, type CSSProperties } from 'react'
import { RefreshCw } from 'lucide-react'
import { fetchLineupWindowPage, formatUtcTime } from '../app/lineup'
import type { LineupChannel, LineupProgramme, LineupWindow, LineupWindowFetcher } from '../app/lineup'
import { failureOf, isLoadFailure, loadFailedMessage, loadFailure, type LoadFailure } from '../app/friendlyError'
import { ErrorNotice } from '../components/ErrorNotice'
import { focusActiveNavItem } from '../components/SideNav'
import { PageHeader } from '../components/PageHeader'

type TimelineGridPageProps = { fetchPage?: LineupWindowFetcher; now?: () => Date }

type TimelineView = { channels: LineupChannel[]; total: number; generation: string; window: LineupWindow }

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const WINDOW_HOURS = 3
const currentTime = () => new Date()

const toUtcText = (time: number): string => new Date(time).toISOString().replace(/\.\d{3}Z$/, 'Z')

// Fixed window: the current minute and the next three hours, in UTC.
function nextThreeHours(now: Date): LineupWindow {
  const from = Math.floor(now.getTime() / MINUTE) * MINUTE
  return { from: toUtcText(from), to: toUtcText(from + WINDOW_HOURS * HOUR) }
}

const timeRange = (program: LineupProgramme): string => `${formatUtcTime(program.startUtc)}–${formatUtcTime(program.stopUtc)} UTC`

// Position of a program inside the window, in percent. Programs that run past an edge are cut at the edge.
function blockStyle(program: LineupProgramme, window: LineupWindow): CSSProperties {
  const from = Date.parse(window.from)
  const span = Date.parse(window.to) - from
  const start = Math.max(Date.parse(program.startUtc), from)
  const stop = Math.min(Date.parse(program.stopUtc), from + span)
  return { left: `${((start - from) / span) * 100}%`, width: `${((stop - start) / span) * 100}%` }
}

const channelLabel = (channel: LineupChannel): string => `${channel.number ?? '—'} ${channel.name}`

function GridView({ channels, window }: { channels: LineupChannel[]; window: LineupWindow }) {
  const from = Date.parse(window.from)
  const ticks = Array.from({ length: WINDOW_HOURS + 1 }, (_, hour) => from + hour * HOUR)
  return (
    <div className="timeline-scroll" role="region" aria-label="Timeline grid, times in UTC" tabIndex={0}>
      <div className="timeline-grid">
        <div className="timeline-row timeline-axis" aria-hidden="true">
          <span className="timeline-label">UTC</span>
          <div className="timeline-track">
            {ticks.map((tick, index) => <span className="timeline-tick" key={tick} style={{ left: `${(index / WINDOW_HOURS) * 100}%` }}>{formatUtcTime(toUtcText(tick))}</span>)}
          </div>
        </div>
        {channels.map((channel) => {
          const programs = channel.programmes ?? []
          return <div className="timeline-row" key={channel.id}>
            <span className="timeline-label">{channelLabel(channel)}</span>
            <ul className="timeline-track" aria-label={`Programs on ${channelLabel(channel)}`}>
              {programs.map((program) => <li className="timeline-block" key={`${program.startUtc}-${program.title}`} style={blockStyle(program, window)} title={`${program.title}, ${timeRange(program)}`}>
                <span className="timeline-block-title">{program.title}</span>
                <span className="timeline-block-time">{timeRange(program)}</span>
              </li>)}
              {programs.length === 0 && <li className="timeline-empty">No programs in this window</li>}
            </ul>
          </div>
        })}
      </div>
    </div>
  )
}

// The same information as the grid, in plain time order. Nothing here depends on position or color.
function ListView({ channels }: { channels: LineupChannel[] }) {
  return (
    <div className="timeline-list">
      {channels.map((channel) => {
        const programs = channel.programmes ?? []
        return <section className="timeline-list-channel" key={channel.id} aria-label={channelLabel(channel)}>
          <h2>{channelLabel(channel)}</h2>
          {programs.length === 0 ? <p>No programs in this window</p> : <ol>
            {programs.map((program) => <li key={`${program.startUtc}-${program.title}`}><span className="timeline-list-time">{timeRange(program)}</span> {program.title}</li>)}
          </ol>}
        </section>
      })}
    </div>
  )
}

export function TimelineGridPage({ fetchPage = fetchLineupWindowPage, now = currentTime }: TimelineGridPageProps) {
  const [view, setView] = useState<TimelineView | null | undefined>(undefined)
  const [mode, setMode] = useState<'grid' | 'list'>('grid')
  const [loadingMore, setLoadingMore] = useState(false)
  const [moreFailed, setMoreFailed] = useState<LoadFailure | null>(null)
  const [failure, setFailure] = useState<LoadFailure>(loadFailure('unknown'))
  const [retry, setRetry] = useState(0)

  useEffect(() => {
    let active = true
    const window = nextThreeHours(now())
    setView(undefined)
    void fetchPage(0, null, window).then((page) => {
      if (!active) return
      if (page === null || page === 'changed' || isLoadFailure(page)) {
        setFailure(page === 'changed' ? loadFailure('changed') : failureOf(page))
        setView(null)
      } else setView({ channels: page.items, total: page.total, generation: page.generation, window })
    })
    return () => { active = false }
  }, [fetchPage, now, retry])

  // If the saved lineup changed between pages, everything starts over so rows never mix two lineups.
  const showMore = async () => {
    if (!view) return
    setLoadingMore(true)
    setMoreFailed(null)
    const page = await fetchPage(view.channels.length, view.generation, view.window)
    setLoadingMore(false)
    if (page === 'changed') setRetry((value) => value + 1)
    else if (page === null || isLoadFailure(page)) setMoreFailed(failureOf(page))
    else setView({ ...view, channels: [...view.channels, ...page.items], total: page.total, generation: page.generation })
  }

  return (
    <div className="page-stack timeline-page">
      <PageHeader eyebrow="Decide" title="Timeline" description="See what airs on each saved channel over the next three hours. This page only shows them." />
      {view === undefined ? <p role="status">Loading the timeline…</p> :
        view === null ? <section className="empty-state" onKeyDown={(event) => {
          if (event.key === 'ArrowLeft') {
            event.preventDefault()
            focusActiveNavItem()
          }
        }}>
          <ErrorNotice message={loadFailedMessage('the timeline', 'timeline-load-failed', 'Start ChannelForge if it is closed, and make sure you have saved a lineup. Then try again.', failure)} />
          <div className="empty-state-action">
            <button className="button button-secondary" type="button" onClick={() => setRetry((value) => value + 1)}><RefreshCw size={18} aria-hidden="true" /> Try again</button>
          </div>
        </section> : view.total === 0 ? <section className="empty-state" aria-live="polite">
          <h2>No channels saved yet</h2><p>Set up a playlist and save your lineup. Your channels will show up here.</p>
        </section> : <>
          <p className="timeline-window">Showing {formatUtcTime(view.window.from)}–{formatUtcTime(view.window.to)} <abbr title="Coordinated Universal Time">UTC</abbr>, the next three hours. All times are UTC.</p>
          <div className="timeline-modes" role="group" aria-label="How to show the timeline">
            <button className="button button-secondary" type="button" aria-pressed={mode === 'grid'} onClick={() => setMode('grid')}>Grid</button>
            <button className="button button-secondary" type="button" aria-pressed={mode === 'list'} onClick={() => setMode('list')}>List</button>
          </div>
          <p role="status" aria-live="polite">Showing {view.channels.length} of {view.total} channels</p>
          {mode === 'grid' ? <GridView channels={view.channels} window={view.window} /> : <ListView channels={view.channels} />}
          {moreFailed && <ErrorNotice message={loadFailedMessage('more channels', 'timeline-more-failed', 'Press Show more channels to try again.', moreFailed)} />}
          {view.channels.length < view.total && <button className="button button-secondary" type="button" disabled={loadingMore} onClick={() => { void showMore() }}>{loadingMore ? 'Loading…' : 'Show more channels'}</button>}
        </>}
    </div>
  )
}
