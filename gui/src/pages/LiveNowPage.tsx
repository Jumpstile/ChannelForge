import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from 'react'
import { ArrowLeft, RefreshCw } from 'lucide-react'
import { fetchLiveNow, fetchLiveNowItem } from '../app/oneGuide'
import type { OneGuideFetcher, OneGuideItem } from '../app/oneGuide'
import { PageHeader } from '../components/PageHeader'
import { focusActiveNavItem } from '../components/SideNav'

type LiveNowPageProps = { fetchItems?: OneGuideFetcher }

function formatTime(value: string): string {
  return new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC' }).format(new Date(value))
}

export function LiveNowPage({ fetchItems = fetchLiveNow }: LiveNowPageProps) {
  const [items, setItems] = useState<OneGuideItem[] | null | undefined>(undefined)
  const [selected, setSelected] = useState<OneGuideItem | null>(null)
  const [detailsPending, setDetailsPending] = useState(false)
  const [detailError, setDetailError] = useState(false)
  const [retry, setRetry] = useState(0)
  const cardRefs = useRef<Array<HTMLButtonElement | null>>([])
  const returnFocus = useRef<HTMLButtonElement | null>(null)
  const detailBackRef = useRef<HTMLButtonElement | null>(null)
  // Only the newest details request owns the dialog; superseding, dismissing, or unmounting aborts the rest.
  const detailsRequest = useRef<AbortController | null>(null)

  useEffect(() => {
    let active = true
    setItems(undefined)
    void fetchItems().then((result) => { if (active) setItems(result) })
    return () => { active = false }
  }, [fetchItems, retry])

  useEffect(() => {
    if (selected) detailBackRef.current?.focus()
  }, [selected])

  useEffect(() => () => detailsRequest.current?.abort(), [])

  const cancelDetailsRequest = () => {
    detailsRequest.current?.abort()
    detailsRequest.current = null
    setDetailsPending(false)
  }

  const openDetails = async (item: OneGuideItem, button: HTMLButtonElement) => {
    cancelDetailsRequest()
    const controller = new AbortController()
    detailsRequest.current = controller
    returnFocus.current = button
    setDetailError(false)
    setDetailsPending(true)
    const detail = await fetchLiveNowItem(item.ItemId, (input, init) => fetch(input, { ...init, signal: controller.signal }))
    if (detailsRequest.current !== controller) return
    detailsRequest.current = null
    setDetailsPending(false)
    if (detail) setSelected(detail)
    else setDetailError(true)
  }

  const handleCardKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, index: number) => {
    const lastIndex = cardRefs.current.length - 1
    const verticalStep = window.innerWidth <= 840 ? 1 : 2
    if (event.key === 'ArrowLeft' && index % verticalStep === 0) {
      event.preventDefault()
      focusActiveNavItem()
      return
    }
    let nextIndex: number | null = null
    if (event.key === 'ArrowDown') nextIndex = Math.min(index + verticalStep, lastIndex)
    if (event.key === 'ArrowRight') nextIndex = Math.min(index + 1, lastIndex)
    if (event.key === 'ArrowUp') nextIndex = Math.max(index - verticalStep, 0)
    if (event.key === 'ArrowLeft') nextIndex = Math.max(index - 1, 0)
    if (nextIndex !== null) {
      event.preventDefault()
      cardRefs.current[nextIndex]?.focus()
    }
  }

  const closeDetails = () => {
    cancelDetailsRequest()
    setSelected(null)
    window.setTimeout(() => returnFocus.current?.focus(), 0)
  }

  useEffect(() => {
    if (!selected && !detailsPending) return
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key === 'Escape' || event.key === 'Backspace' || event.key === 'BrowserBack') {
        event.preventDefault()
        closeDetails()
      }
      if (selected && event.key === 'Tab') {
        event.preventDefault()
        detailBackRef.current?.focus()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [selected, detailsPending])

  return (
    <div className="page-stack live-now-page">
      <PageHeader eyebrow="One Guide" title="Live Now" description="See what is on now from your accepted guide." />
      {items === undefined ? <p className="live-now-message" role="status">Loading Live Now…</p> :
        items === null ? <section className="live-now-message live-now-error" role="alert">
          <h2>Live Now is unavailable</h2><p>The guide could not be loaded. Check that ChannelForge is running, then try again.</p>
          <button className="button button-secondary" type="button" onClick={() => setRetry((value) => value + 1)}><RefreshCw size={18} aria-hidden="true" /> Retry</button>
        </section> : items.length === 0 ? <section className="live-now-message" aria-live="polite">
          <h2>Nothing is on right now</h2><p>Your accepted guide has no programmes airing at this time.</p>
        </section> : <>
          <p className="live-now-count" aria-live="polite">{items.length} {items.length === 1 ? 'programme' : 'programmes'} on now</p>
          <div className="live-now-list" role="list" aria-label="Programmes on now">
            {items.map((item, index) => <div className="live-now-card-wrap" role="listitem" key={item.ItemId}>
              <button className="live-now-card" type="button" ref={(node) => { cardRefs.current[index] = node }} onKeyDown={(event) => handleCardKeyDown(event, index)} onClick={(event) => { void openDetails(item, event.currentTarget) }}>
                <span className="live-now-card-status"><span aria-hidden="true" className="live-now-indicator" /> LIVE</span>
                <span className="live-now-card-title">{item.Title}</span>
                {item.Subtitle && <span className="live-now-card-subtitle">{item.Subtitle}</span>}
                <span className="live-now-card-meta">{item.Offerings[0]?.SourceLabel ?? 'Accepted guide'}{item.CategoryKeys.length > 0 && ` · ${item.CategoryKeys.filter((key) => key !== 'live-now').join(', ')}`}</span>
                <span className="live-now-card-time">{formatTime(item.StartUtc)}–{formatTime(item.StopUtc)} UTC</span>
                <span className="live-now-card-action">Press Enter for details</span>
              </button>
            </div>)}
          </div>
        </>}
      {detailError && <p className="live-now-inline-error" role="alert">Details are unavailable right now. Choose the programme again to retry.</p>}
      {selected && <div className="live-now-dialog-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) closeDetails() }}>
        <section className="live-now-dialog" role="dialog" aria-modal="true" aria-labelledby="live-now-detail-title">
          <button ref={detailBackRef} className="live-now-back" type="button" onClick={closeDetails}><ArrowLeft size={20} aria-hidden="true" /> Back</button>
          <p className="live-now-card-status"><span aria-hidden="true" className="live-now-indicator" /> {selected.Status === 'Live' ? 'LIVE NOW' : selected.Status === 'StartingSoon' ? 'STARTING SOON' : selected.Status.toUpperCase()}</p>
          <h2 id="live-now-detail-title">{selected.Title}</h2>
          {selected.Subtitle && <p className="live-now-detail-subtitle">{selected.Subtitle}</p>}
          <p>{formatTime(selected.StartUtc)}–{formatTime(selected.StopUtc)} · {selected.Offerings[0]?.SourceLabel ?? 'Accepted guide'}</p>
          {selected.Description && <p>{selected.Description}</p>}
          <p className="live-now-detail-note">Guide information only. Playback is not available here.</p>
        </section>
      </div>}
    </div>
  )
}
