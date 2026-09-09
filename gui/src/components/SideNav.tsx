import { ArrowRight, Circle } from 'lucide-react'
import type { NavigationId } from '../app/navigation'
import { navigationGroups } from '../app/navigation'

type SideNavProps = {
  activePage: NavigationId
  onNavigate: (page: NavigationId) => void
  navigationAvailability?: Partial<Record<NavigationId, boolean>>
}

export function SideNav({ activePage, onNavigate, navigationAvailability }: SideNavProps) {
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
