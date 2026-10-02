import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from 'react'
import { ArrowLeft, RefreshCw } from 'lucide-react'
import { fetchLiveNowItem, fetchOneGuideCategory } from '../app/oneGuide'
import type { OneGuideFetcher, OneGuideItem } from '../app/oneGuide'
import { PageHeader } from '../components/PageHeader'
import { focusActiveNavItem } from '../components/SideNav'

const fetchWrestling: OneGuideFetcher = () => fetchOneGuideCategory('wrestling')

const sections: Array<{ status: OneGuideItem['Status']; title: string }> = [
  { status: 'Live', title: 'On Now' },
  { status: 'StartingSoon', title: 'Starting Soon' },
  { status: 'Upcoming', title: 'Coming Up' },
]

function formatTime(value: string): string {
  return new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC' }).format(new Date(value))
}

/** Browses accepted-guide Wrestling programmes by the status computed by the One Guide API. */
export function OneGuideCategoryPage({ fetchItems = fetchWrestling }: { fetchItems?: OneGuideFetcher }) {
  const [items, setItems] = useState<OneGuideItem[] | null | undefined>(undefined)
  const [selected, setSelected] = useState<OneGuideItem | null>(null)
  const [detailsPending, setDetailsPending] = useState(false)
  const [detailError, setDetailError] = useState(false)
  const [retry, setRetry] = useState(0)
  const cardRefs = useRef<Array<HTMLButtonElement | null>>([])
  const returnFocus = useRef<HTMLButtonElement | null>(null)
  const detailBackRef = useRef<HTMLButtonElement | null>(null)
  const detailsRequest = useRef<AbortController | null>(null)

  useEffect(() => {
    let active = true
    setItems(undefined)
    void fetchItems().then((result) => { if (active) setItems(result) }).catch(() => { if (active) setItems(null) })
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

  const visibleItems = items?.filter((item) => item.Status !== 'Past') ?? []
  const closeDetails = () => {
    cancelDetailsRequest()
    setSelected(null)
    window.setTimeout(() => returnFocus.current?.focus(), 0)
  }

  const handleCardKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, index: number) => {
    const lastIndex = cardRefs.current.length - 1
    if (event.key === 'ArrowLeft') {
      event.preventDefault()
      focusActiveNavItem()
      return
    }
    let nextIndex: number | null = null
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight') nextIndex = Math.min(index + 1, lastIndex)
    if (event.key === 'ArrowUp') nextIndex = Math.max(index - 1, 0)
    if (nextIndex !== null) {
      event.preventDefault()
      cardRefs.current[nextIndex]?.focus()
    }
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
    <div className="page-stack live-now-page category-page">
      <PageHeader eyebrow="One Guide" title="Wrestling" description="Browse wrestling from your accepted guide by when it airs." />
      {items === undefined ? <p className="live-now-message" role="status">Loading Wrestling…</p> :
        items === null ? <section className="live-now-message live-now-error" role="alert">
          <h2>Wrestling is unavailable</h2><p>The guide could not be loaded. Check that ChannelForge is running, then try again.</p>
          <button className="button button-secondary" type="button" onClick={() => setRetry((value) => value + 1)} onKeyDown={(event) => {
            if (event.key === 'ArrowLeft') {
              event.preventDefault()
              focusActiveNavItem()
            }
          }}><RefreshCw size={18} aria-hidden="true" /> Retry</button>
        </section> : visibleItems.length === 0 ? <section className="live-now-message" aria-live="polite">
          <h2>No wrestling programmes are coming up</h2><p>Your accepted guide has no current or future Wrestling programmes.</p>
        </section> : <>
          <p className="live-now-count" aria-live="polite">{visibleItems.length} {visibleItems.length === 1 ? 'programme' : 'programmes'} in Wrestling</p>
          {sections.map((section) => {
            const sectionItems = visibleItems.filter((item) => item.Status === section.status)
            return <section className="category-section" key={section.status} aria-labelledby={`wrestling-${section.status}`}>
              <h2 id={`wrestling-${section.status}`}>{section.title}<span className="category-section-count">{sectionItems.length}</span></h2>
              {sectionItems.length === 0 ? <p className="category-section-empty">Nothing scheduled in this section.</p> :
                <div className="live-now-list" role="list" aria-label={section.title}>
                  {sectionItems.map((item) => {
                    const index = visibleItems.indexOf(item)
                    return <div className="live-now-card-wrap" role="listitem" key={item.ItemId}>
                      <button className="live-now-card" type="button" ref={(node) => { cardRefs.current[index] = node }} onKeyDown={(event) => handleCardKeyDown(event, index)} onClick={(event) => { void openDetails(item, event.currentTarget) }}>
                        <span className="live-now-card-status">{item.Status === 'Live' ? 'LIVE NOW' : item.Status === 'StartingSoon' ? 'STARTING SOON' : 'COMING UP'}</span>
                        <span className="live-now-card-title">{item.Title}</span>
                        {item.Subtitle && <span className="live-now-card-subtitle">{item.Subtitle}</span>}
                        {item.Promotion && <span className="live-now-card-meta">{item.Promotion.Name}</span>}
                        <span className="live-now-card-time">{formatTime(item.StartUtc)}–{formatTime(item.StopUtc)} UTC</span>
                        <span className="live-now-card-action">Press Enter for details</span>
                      </button>
                    </div>
                  })}
                </div>}
            </section>
          })}
        </>}
      {detailError && <p className="live-now-inline-error" role="alert">Details are unavailable right now. Choose the programme again to retry.</p>}
      {selected && <div className="live-now-dialog-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) closeDetails() }}>
        <section className="live-now-dialog" role="dialog" aria-modal="true" aria-labelledby="wrestling-detail-title">
          <button ref={detailBackRef} className="live-now-back" type="button" onClick={closeDetails}><ArrowLeft size={20} aria-hidden="true" /> Back</button>
          <p className="live-now-card-status">{selected.Status === 'Live' ? 'LIVE NOW' : selected.Status === 'StartingSoon' ? 'STARTING SOON' : selected.Status.toUpperCase()}</p>
          <h2 id="wrestling-detail-title">{selected.Title}</h2>
          {selected.Promotion && <p>{selected.Promotion.Name}</p>}
          {selected.Subtitle && <p className="live-now-detail-subtitle">{selected.Subtitle}</p>}
          <p>{formatTime(selected.StartUtc)}–{formatTime(selected.StopUtc)}</p>
          {selected.Description && <p>{selected.Description}</p>}
          <p className="live-now-detail-note">Guide information only. Playback is not available here.</p>
        </section>
      </div>}
    </div>
  )
}
