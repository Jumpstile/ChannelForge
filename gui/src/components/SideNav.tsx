import { useEffect, type KeyboardEvent as ReactKeyboardEvent } from 'react'
import { ArrowRight, Circle } from 'lucide-react'
import type { NavigationId } from '../app/navigation'
import { navigationGroups } from '../app/navigation'

type SideNavProps = {
  activePage: NavigationId
  onNavigate: (page: NavigationId) => void
  navigationAvailability?: Partial<Record<NavigationId, boolean>>
}

const dpadKeys: Record<string, true> = { ArrowUp: true, ArrowDown: true, ArrowLeft: true, ArrowRight: true }
const contentFocusSelector = 'button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'

function navButtons(): HTMLButtonElement[] {
  return Array.from(document.querySelectorAll<HTMLButtonElement>('.side-nav .nav-item:not([disabled])'))
}

/** Focuses the active workflow page button; the D-pad return target from page content. */
export function focusActiveNavItem(): void {
  (document.querySelector<HTMLButtonElement>('.side-nav .nav-item.is-active') ?? navButtons()[0])?.focus()
}

export function SideNav({ activePage, onNavigate, navigationAvailability }: SideNavProps) {
  // A remote D-pad has no Tab key: the first arrow press after launch lands focus on the active page button.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!Object.hasOwn(dpadKeys, event.key) || (document.activeElement && document.activeElement !== document.body)) return
      event.preventDefault()
      focusActiveNavItem()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  const handleNavKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>) => {
    if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
      const buttons = navButtons()
      const index = buttons.indexOf(event.currentTarget)
      const next = buttons[Math.min(Math.max(index + (event.key === 'ArrowDown' ? 1 : -1), 0), buttons.length - 1)]
      event.preventDefault()
      next?.focus()
    } else if (event.key === 'ArrowRight') {
      const target = document.querySelector<HTMLElement>('.main-content')?.querySelector<HTMLElement>(contentFocusSelector)
      if (target) {
        event.preventDefault()
        target.focus()
      }
    }
  }

  return (
    <aside className="side-nav" aria-label="ChannelForge workflow">
      <div className="side-nav-intro">
        <p className="eyebrow">Guided workbench</p>
        <p className="side-nav-copy">Build your TV lineup from a playlist and guide.</p>
      </div>
      <nav aria-label="Workflow pages">
        {navigationGroups.map((group) => (
          <div className="nav-group" key={group.label}>
            <p className="nav-group-label">{group.label}</p>
            <div className="nav-items">
              {group.items.map((item) => {
                const isActive = activePage === item.id
                const isAvailable = navigationAvailability?.[item.id] ?? item.available
                return (
                  <button
                    className={`nav-item${isActive ? ' is-active' : ''}`}
                    disabled={!isAvailable}
                    key={item.id}
                    onClick={() => onNavigate(item.id)}
                    onKeyDown={handleNavKeyDown}
                    title={isAvailable ? item.description : `${item.description} · Next slice`}
                  >
                    <Circle className="nav-item-dot" size={8} fill="currentColor" aria-hidden="true" />
                    <span className="nav-item-label">{item.label}</span>
                    {!isAvailable && <span className="nav-item-planned">Next</span>}
                    {isActive && <ArrowRight className="nav-item-arrow" size={15} aria-hidden="true" />}
                  </button>
                )
              })}
            </div>
          </div>
        ))}
      </nav>
      <div className="side-nav-footer">
        <p className="nav-group-label">Development view</p>
        <button className="gallery-link" type="button" onClick={() => onNavigate('gallery')}>
          View state gallery
          <ArrowRight size={15} aria-hidden="true" />
        </button>
      </div>
    </aside>
  )
}
