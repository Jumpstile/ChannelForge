import type { ReactNode } from 'react'
import { CircleHelp, ShieldCheck } from 'lucide-react'
import type { AppearanceMode } from './appearance'
import { demoWorkspaceIdentity } from './workspaceIdentity'
import type { NavigationId } from './navigation'
import { AppearanceControl } from '../components/AppearanceControl'
import { SideNav } from '../components/SideNav'
import { WorkspaceIdentity } from '../components/WorkspaceIdentity'
import { StatusBadge } from '../components/StatusBadge'
import { TopBar } from '../components/TopBar'
type AppShellProps = {
  activePage: NavigationId
  appearanceMode: AppearanceMode
  onAppearanceModeChange: (mode: AppearanceMode) => void
  onNavigate: (page: NavigationId) => void
  navigationAvailability?: Partial<Record<NavigationId, boolean>>
  children: ReactNode
}

export function AppShell({ activePage, appearanceMode, onAppearanceModeChange, onNavigate, navigationAvailability, children }: AppShellProps) {
  return (
    <div className="app-frame">
      <SideNav activePage={activePage} navigationAvailability={navigationAvailability} onNavigate={onNavigate} />
      <div className="app-content">
        <TopBar>
          <WorkspaceIdentity identity={demoWorkspaceIdentity} />
          <div className="top-bar-status" aria-label="Workspace status">
            <StatusBadge status="Not configured" />
            <button className="icon-button" type="button" aria-label="Open help">
              <CircleHelp size={18} aria-hidden="true" />
            </button>
          </div>
          <AppearanceControl mode={appearanceMode} onChange={onAppearanceModeChange} />
        </TopBar>
        <main className="main-content">{children}</main>
        <footer className="app-footer">
          <span className="privacy-note">
            <ShieldCheck size={16} aria-hidden="true" />
            Local workspace · safe identity display
          </span>
          <span>ChannelForge GUI foundation</span>
        </footer>
      </div>
    </div>
  )
}
