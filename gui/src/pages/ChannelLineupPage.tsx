import { useEffect, useState } from 'react'
import { RefreshCw } from 'lucide-react'
import { fetchLineupPage } from '../app/lineup'
import type { LineupChannel, LineupFetcher, LineupProgramme } from '../app/lineup'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'

type ChannelLineupPageProps = { fetchPage?: LineupFetcher; onOpenSetup: () => void }

type LineupView = { channels: LineupChannel[]; total: number; generation: string }

const nowAndNext = (current: LineupProgramme | null, next: LineupProgramme | null): string => {
  const parts = [current && `Now: ${current.title}`, next && `Next: ${next.title}`].filter(Boolean)
  return parts.join(' · ')
}

export function ChannelLineupPage({ fetchPage = fetchLineupPage, onOpenSetup }: ChannelLineupPageProps) {
  const [view, setView] = useState<LineupView | null | undefined>(undefined)
  const [loadingMore, setLoadingMore] = useState(false)
  const [moreFailed, setMoreFailed] = useState(false)
  const [retry, setRetry] = useState(0)

  useEffect(() => {
    let active = true
    setView(undefined)
    void fetchPage(0, null).then((page) => {
      if (!active) return
      setView(page === null || page === 'changed' ? null : { channels: page.items, total: page.total, generation: page.generation })
    })
    return () => { active = false }
  }, [fetchPage, retry])

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

  const setupButton = <button className="button button-primary" type="button" onClick={onOpenSetup}>Go to Setup</button>

  return (
    <div className="page-stack">
      <PageHeader eyebrow="Decide" title="Your channel lineup" description="The channels you saved, in the order they were saved. This page only shows them." />
      {view === undefined ? <p role="status">Loading your channels…</p> :
        view === null ? <section className="empty-state" role="alert">
          <h2>Your channels could not be loaded</h2>
          <p>Make sure ChannelForge is running and that you have saved a lineup. Then try again.</p>
          <div className="empty-state-action">
            <button className="button button-secondary" type="button" onClick={() => setRetry((value) => value + 1)}><RefreshCw size={18} aria-hidden="true" /> Try again</button>
            {setupButton}
          </div>
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
          {moreFailed && <p role="alert">More channels could not be loaded. Try again.</p>}
          {view.channels.length < view.total && <button className="button button-secondary" type="button" disabled={loadingMore} onClick={() => { void showMore() }}>{loadingMore ? 'Loading…' : 'Show more channels'}</button>}
        </>}
    </div>
  )
}
