import { useEffect, useState } from 'react'
import { Printer, RefreshCw } from 'lucide-react'
import { fetchLineupPage, matchReasonText, NO_EXPLANATION, NO_MATCH_DETAILS } from '../app/lineup'
import type { LineupChannel, LineupFetcher, LineupProgramme, MatchEvidence } from '../app/lineup'
import { failureOf, isLoadFailure, loadFailedMessage, loadFailure, type LoadFailure } from '../app/friendlyError'
import { ErrorNotice } from '../components/ErrorNotice'
import { focusActiveNavItem } from '../components/SideNav'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'

type ChannelLineupPageProps = { fetchPage?: LineupFetcher; onOpenSetup: () => void }

type LineupView = { channels: LineupChannel[]; total: number; generation: string; savedAtUtc: string | null }

// "Saved on November 24, 2026" in the user's local format; nothing when the date is missing or not a real date.
const savedOn = (savedAtUtc: string | null | undefined): string => {
  const date = savedAtUtc ? new Date(savedAtUtc) : null
  return date && !Number.isNaN(date.getTime()) ? ` Saved on ${date.toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}.` : ''
}

const nowAndNext = (current: LineupProgramme | null, next: LineupProgramme | null): string => {
  const parts = [current && `Now: ${current.title}`, next && `Next: ${next.title}`].filter(Boolean)
  return parts.join(' · ')
}

// Plain-words problems for one channel, from the status fields the server returns.
const channelProblems = (channel: LineupChannel): string[] => [
  ...(channel.logoStatus === 'missing' ? ['Logo missing'] : []),
  ...(channel.guideState === 'none' ? ['No program guide linked'] : []),
]

const groupChannels = (channels: LineupChannel[]): Map<string, LineupChannel[]> => {
  const groups = new Map<string, LineupChannel[]>()
  for (const channel of channels) {
    const name = channel.group || 'No group'
    groups.set(name, [...(groups.get(name) ?? []), channel])
  }
  return groups
}

// Lowercase, with extra spaces removed, so "  sports   one " finds "Sports One".
const squash = (text: string): string => text.trim().replace(/\s+/g, ' ').toLowerCase()

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

// Provider text (guide ID, guide source) is shown as plain React text only, cut with a visible ellipsis when long.
const cut = (value: string, max = 80): string => (value.length > max ? `${value.slice(0, max)}…` : value)

// One plain line about the saved guide match, with the technical values in a Details fold. A channel with no saved evidence still gets a line when other channels have it.
function GuideReason({ evidence }: { evidence: MatchEvidence | undefined }) {
  return (
    <div className="lineup-channel-guide">
      <p>{evidence ? matchReasonText(evidence.reasonCode) : NO_EXPLANATION}</p>
      {evidence && <details>
        <summary>Details</summary>
        <p>Reason: {cut(evidence.reasonCode)}</p>
        <p>Guide ID: {evidence.guideId ? cut(evidence.guideId) : 'none'}</p>
        <p>Guide source: {evidence.guideSourceId ? cut(evidence.guideSourceId) : 'none'}</p>
      </details>}
    </div>
  )
}

export function ChannelLineupPage({ fetchPage = fetchLineupPage, onOpenSetup }: ChannelLineupPageProps) {
  const [view, setView] = useState<LineupView | null | undefined>(undefined)
  const [loadingMore, setLoadingMore] = useState(false)
  const [moreFailed, setMoreFailed] = useState<LoadFailure | null>(null)
  const [failure, setFailure] = useState<LoadFailure>(loadFailure('unknown'))
  const [retry, setRetry] = useState(0)
  const [printRequested, setPrintRequested] = useState(false)
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    setView(undefined)
    void fetchPage(0, null).then((page) => {
      if (!active) return
      if (page === null || page === 'changed' || isLoadFailure(page)) {
        setFailure(page === 'changed' ? loadFailure('changed') : failureOf(page))
        setView(null)
      } else setView({ channels: page.items, total: page.total, generation: page.generation, savedAtUtc: page.savedAtUtc ?? null })
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
    setMoreFailed(null)
    const page = await fetchPage(view.channels.length, view.generation)
    setLoadingMore(false)
    if (page === 'changed') setRetry((value) => value + 1)
    else if (page === null || isLoadFailure(page)) setMoreFailed(failureOf(page))
    else setView({ ...view, channels: [...view.channels, ...page.items], total: page.total, generation: page.generation })
  }

  // Loads every remaining page so the printout holds the whole lineup, then asks for the print dialog.
  const printSummary = async () => {
    if (!view) return
    setLoadingMore(true)
    setMoreFailed(null)
    let channels = view.channels
    while (channels.length < view.total) {
      const page = await fetchPage(channels.length, view.generation)
      if (page === 'changed') { setLoadingMore(false); setRetry((value) => value + 1); return }
      if (page === null || isLoadFailure(page) || page.items.length === 0) { setMoreFailed(failureOf(page)); break }
      channels = [...channels, ...page.items]
    }
    setLoadingMore(false)
    setView({ ...view, channels })
    setPrintRequested(true)
  }

  const setupButton = <button className="button button-primary" type="button" onClick={onOpenSetup}>Go to Setup</button>
  const groups = view ? groupChannels(view.channels) : new Map<string, LineupChannel[]>()
  const needle = squash(query)
  const shown = view ? view.channels.filter((channel) => (group === null || (channel.group || 'No group') === group) && squash(channel.name).includes(needle)) : []
  const filtering = needle !== '' || group !== null
  const clearFilters = () => { setQuery(''); setGroup(null) }
  // Match details are all-or-nothing for a lineup in practice: with none on any loaded channel, say so once instead of on every row.
  const hasEvidence = view ? view.channels.some((channel) => channel.matchEvidence !== undefined) : false

  return (
    <>
    <div className="page-stack lineup-screen">
      <PageHeader eyebrow="Decide" title="Your channel lineup" description={`The channels you saved, in the order they were saved. A channel's Group is the heading it is filed under in the playlist, such as a category like Movies or Sports. This page only shows them.${view ? savedOn(view.savedAtUtc) : ''}`} />
      {view === undefined ? <p role="status">Loading your channels…</p> :
        view === null ? <section className="empty-state" onKeyDown={(event) => {
          if (event.key === 'ArrowLeft') {
            event.preventDefault()
            focusActiveNavItem()
          }
        }}>
          <ErrorNotice message={loadFailedMessage('your saved lineup', 'lineup-load-failed', 'Start ChannelForge if it is closed, and make sure you have saved a lineup. Then try again.', failure)} />
          <div className="empty-state-action">
            <button className="button button-secondary" type="button" onClick={() => setRetry((value) => value + 1)}><RefreshCw size={18} aria-hidden="true" /> Try again</button>
            {setupButton}
          </div>
        </section> : view.total === 0 ? <EmptyState title="No channels saved yet" action={setupButton}>Set up a playlist and save your lineup. Your channels will show up here.</EmptyState> : <>
          <div className="lineup-filters">
            <label>Search by channel name <input type="search" value={query} onChange={(event) => setQuery(event.target.value)} /></label>
            <label>Group <select value={group ?? ''} onChange={(event) => setGroup(event.target.value === '' ? null : event.target.value)}>
              <option value="">All groups ({view.channels.length})</option>
              {[...groups].map(([name, items]) => <option key={name} value={name}>{name} ({items.length})</option>)}
            </select></label>
          </div>
          <p role="status" aria-live="polite">{filtering ? `Found ${shown.length} of ${view.channels.length} loaded channels` : `Showing ${view.channels.length} of ${view.total} channels`}</p>
          {filtering && view.channels.length < view.total && <p className="lineup-match-note">Not all channels are loaded yet ({view.channels.length} of {view.total}), so search and groups only look at the loaded ones. Press Show more channels to load the rest.</p>}
          {filtering && shown.length === 0 && <EmptyState title="No channels match" action={<button className="button button-secondary" type="button" onClick={clearFilters}>Clear search and group</button>}>Nothing in the loaded channels matches. Clear the search and group to see every channel again.</EmptyState>}
          {!hasEvidence && <p className="lineup-match-note">{NO_MATCH_DETAILS}</p>}
          <ul className="lineup-channel-list" aria-label="Channels in your lineup">
            {shown.map((channel) => {
              const airing = nowAndNext(channel.current, channel.next)
              const problems = channelProblems(channel)
              return <li className="lineup-channel-row" key={channel.id} tabIndex={0} aria-label={`${channel.number ?? 'No number'}, ${channel.name}${channel.group ? `, ${channel.group}` : ''}${airing ? `, ${airing}` : ''}${problems.length ? `, ${problems.join(', ')}` : ''}`}>
                <span className="lineup-channel-number">{channel.number ?? '—'}</span>
                <span className="lineup-channel-name">{channel.name}</span>
                {channel.group && <span className="lineup-channel-group">{channel.group}</span>}
                {airing && <span className="lineup-channel-airing">{airing}</span>}
                {hasEvidence && <GuideReason evidence={channel.matchEvidence} />}
                {problems.length > 0 && <div className="lineup-channel-problems">
                  {problems.map((text) => <p key={text}><StatusBadge status="Warning" /> {text}</p>)}
                  <button className="button button-secondary" type="button" onClick={onOpenSetup}>Fix in Guided Setup</button>
                  <details>
                    <summary>Details</summary>
                    <p>Logo status: {channel.logoStatus}. Guide state: {channel.guideState}. Attention: {channel.attention.join(', ') || 'none'}.</p>
                  </details>
                </div>}
                {channel.logoStatus === 'pinned' && <div className="lineup-channel-pinned">
                  <p>Logo pinned (will not be replaced)</p>
                  <details>
                    <summary>Details</summary>
                    <p>You pinned this logo. ChannelForge keeps it when the lineup is refreshed. Remove the pin to let ChannelForge choose a logo again.</p>
                  </details>
                </div>}
              </li>
            })}
          </ul>
          {moreFailed && <ErrorNotice message={loadFailedMessage('more channels', 'lineup-more-failed', 'Press Show more channels to try again.', moreFailed)} />}
          {view.channels.length < view.total && <button className="button button-secondary" type="button" disabled={loadingMore} onClick={() => { void showMore() }}>{loadingMore ? 'Loading…' : 'Show more channels'}</button>}
          <button className="button button-secondary" type="button" disabled={loadingMore} onClick={() => { void printSummary() }}><Printer size={18} aria-hidden="true" /> Print summary</button>
        </>}
    </div>
    {view && view.total > 0 && <PrintSummary channels={view.channels} total={view.total} />}
    </>
  )
}
