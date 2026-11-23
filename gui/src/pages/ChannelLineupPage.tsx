import { useEffect, useState } from 'react'
import { Printer, RefreshCw } from 'lucide-react'
import { fetchLineupPage } from '../app/lineup'
import type { LineupChannel, LineupFetcher, LineupProgramme } from '../app/lineup'
import { loadFailedMessage } from '../app/friendlyError'
import { ErrorNotice } from '../components/ErrorNotice'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'

type ChannelLineupPageProps = { fetchPage?: LineupFetcher; onOpenSetup: () => void }

type LineupView = { channels: LineupChannel[]; total: number; generation: string }

const nowAndNext = (current: LineupProgramme | null, next: LineupProgramme | null): string => {
  const parts = [current && `Now: ${current.title}`, next && `Next: ${next.title}`].filter(Boolean)
  return parts.join(' · ')
}

const groupChannels = (channels: LineupChannel[]): Map<string, LineupChannel[]> => {
  const groups = new Map<string, LineupChannel[]>()
  for (const channel of channels) {
    const name = channel.group || 'No group'
    groups.set(name, [...(groups.get(name) ?? []), channel])
  }
  return groups
}

// Print-only summary. Hidden on screen; the print stylesheet shows it and hides the rest of the page.
function PrintSummary({ channels, total }: { channels: LineupChannel[]; total: number }) {
  const printed = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })
  return (
    <section className="lineup-print" aria-hidden="true">
      <h1>Your channel lineup</h1>
      <p>Printed {printed}. {total} {total === 1 ? 'channel' : 'channels'} in your saved lineup.</p>
      {channels.length < total && <p><strong>This summary is cut off.</strong> It lists {channels.length} of {total} channels because some could not be loaded.</p>}
      {[...groupChannels(channels)].map(([group, rows]) => (
        <div className="lineup-print-group" key={group}>
          <h2>{group}</h2>
          <ul>
            {rows.map((channel) => <li key={channel.id}>{`${channel.number ?? '—'}  ${channel.name}`}</li>)}
          </ul>
        </div>
      ))}
    </section>
  )
}

export function ChannelLineupPage({ fetchPage = fetchLineupPage, onOpenSetup }: ChannelLineupPageProps) {
  const [view, setView] = useState<LineupView | null | undefined>(undefined)
  const [loadingMore, setLoadingMore] = useState(false)
  const [moreFailed, setMoreFailed] = useState(false)
  const [retry, setRetry] = useState(0)
  const [printRequested, setPrintRequested] = useState(false)

  useEffect(() => {
    let active = true
    setView(undefined)
    void fetchPage(0, null).then((page) => {
      if (!active) return
      setView(page === null || page === 'changed' ? null : { channels: page.items, total: page.total, generation: page.generation })
    })
    return () => { active = false }
  }, [fetchPage, retry])

  useEffect(() => {
    if (!printRequested) return
    setPrintRequested(false)
    window.print()
  }, [printRequested])

  const showMore = async () => {
    if (!view) return
    setLoadingMore(true)
    setMoreFailed(false)
    const page = await fetchPage(view.channels.length, view.generation)
    setLoadingMore(false)
    if (page === 'changed') setRetry((value) => value + 1)
    else if (page === null) setMoreFailed(true)
    else setView({ channels: [...view.channels, ...page.items], total: page.total, generation: page.generation })
  }

  // Loads every remaining page so the printout holds the whole lineup, then asks for the print dialog.
  const printSummary = async () => {
    if (!view) return
    setLoadingMore(true)
    setMoreFailed(false)
    let channels = view.channels
    while (channels.length < view.total) {
      const page = await fetchPage(channels.length, view.generation)
      if (page === 'changed') { setLoadingMore(false); setRetry((value) => value + 1); return }
      if (page === null || page.items.length === 0) { setMoreFailed(true); break }
      channels = [...channels, ...page.items]
    }
    setLoadingMore(false)
    setView({ ...view, channels })
    setPrintRequested(true)
  }

  const setupButton = <button className="button button-primary" type="button" onClick={onOpenSetup}>Go to Setup</button>

  return (
    <>
    <div className="page-stack lineup-screen">
      <PageHeader eyebrow="Decide" title="Your channel lineup" description="The channels you saved, in the order they were saved. This page only shows them." />
      {view === undefined ? <p role="status">Loading your channels…</p> :
        view === null ? <section className="empty-state">
          <div className="empty-state-action">
            <button className="button button-secondary" type="button" onClick={() => setRetry((value) => value + 1)}><RefreshCw size={18} aria-hidden="true" /> Try again</button>
            {setupButton}
          </div>
          <ErrorNotice message={loadFailedMessage('your channels', 'lineup-load-failed', 'Make sure ChannelForge is running and that you have saved a lineup. Then try again.')} />
        </section> : view.total === 0 ? <EmptyState title="No channels saved yet" action={setupButton}>Set up a playlist and save your lineup. Your channels will show up here.</EmptyState> : <>
          <p role="status" aria-live="polite">Showing {view.channels.length} of {view.total} channels</p>
          <ul className="lineup-channel-list" aria-label="Channels in your lineup">
            {view.channels.map((channel) => {
              const airing = nowAndNext(channel.current, channel.next)
              return <li className="lineup-channel-row" key={channel.id} tabIndex={0} aria-label={`${channel.number ?? 'No number'}, ${channel.name}${channel.group ? `, ${channel.group}` : ''}${airing ? `, ${airing}` : ''}`}>
                <span className="lineup-channel-number">{channel.number ?? '—'}</span>
                <span className="lineup-channel-name">{channel.name}</span>
                {channel.group && <span className="lineup-channel-group">{channel.group}</span>}
                {airing && <span className="lineup-channel-airing">{airing}</span>}
              </li>
            })}
          </ul>
          {moreFailed && <ErrorNotice message={loadFailedMessage('more channels', 'lineup-more-failed', 'Press Show more channels to try again.')} />}
          {view.channels.length < view.total && <button className="button button-secondary" type="button" disabled={loadingMore} onClick={() => { void showMore() }}>{loadingMore ? 'Loading…' : 'Show more channels'}</button>}
          <button className="button button-secondary" type="button" disabled={loadingMore} onClick={() => { void printSummary() }}><Printer size={18} aria-hidden="true" /> Print summary</button>
        </>}
    </div>
    {view && view.total > 0 && <PrintSummary channels={view.channels} total={view.total} />}
    </>
  )
}
