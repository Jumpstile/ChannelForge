import type { ReactNode } from 'react'
import { CircleHelp, ShieldCheck } from 'lucide-react'
import { demoWorkspaceIdentity } from './workspaceIdentity'
import type { NavigationId } from './navigation'
import { SideNav } from '../components/SideNav'
import { WorkspaceIdentity } from '../components/WorkspaceIdentity'
import { StatusBadge } from '../components/StatusBadge'
import { TopBar } from '../components/TopBar'

type AppShellProps = {
  activePage: NavigationId
  onNavigate: (page: NavigationId) => void
  children: ReactNode
}

export function AppShell({ activePage, onNavigate, children }: AppShellProps) {
  return (
    <div className="app-frame">
      <SideNav activePage={activePage} onNavigate={onNavigate} />
      <div className="app-content">
        <TopBar>
          <WorkspaceIdentity identity={demoWorkspaceIdentity} />
          <div className="top-bar-status" aria-label="Workspace status">
            <StatusBadge status="Not configured" />
            <button className="icon-button" type="button" aria-label="Open help">
              <CircleHelp size={18} aria-hidden="true" />
            </button>
          </div>
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
