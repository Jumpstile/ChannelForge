import type { ReactNode } from 'react'
import { CircleHelp, ShieldCheck } from 'lucide-react'
import { HomeBackBar } from '../components/HomeBackBar'
import { demoWorkspaceIdentity } from './workspaceIdentity'
import type { NavigationId } from './navigation'
import { SideNav } from '../components/SideNav'
import { WorkspaceIdentity } from '../components/WorkspaceIdentity'
import { TopBar } from '../components/TopBar'
import { HttpWarning } from '../components/HttpWarning'
import type { ChangePasswordResult } from './auth'

// Present only when the server requires sign-in and this browser is signed in.
export type AccountControls = {
  changePassword: (currentPassword: string, newPassword: string) => Promise<ChangePasswordResult>
  httpWarning: boolean
  onSignOut: () => void
  signOutFailed: boolean
}

type AppShellProps = {
  activePage: NavigationId
  onNavigate: (page: NavigationId) => void
  onHome: () => void
  onBack: () => void
  navigationAvailability?: Partial<Record<NavigationId, boolean>>
  account?: AccountControls
  children: ReactNode
}

export function AppShell({ activePage, onNavigate, onHome, onBack, navigationAvailability, account, children }: AppShellProps) {
  return (
    <div className="app-frame">
      <SideNav activePage={activePage} navigationAvailability={navigationAvailability} onNavigate={onNavigate} />
      <div className="app-content">
        <TopBar>
          <WorkspaceIdentity identity={demoWorkspaceIdentity} />
          <div className="top-bar-status" aria-label="Workspace actions">
            {account ? (
              <>
                <button className="button button-secondary" type="button" onClick={() => onNavigate('account')}>Change password</button>
                <button className="button button-secondary" type="button" onClick={account.onSignOut}>Sign out</button>
              </>
            ) : null}
            <button className="icon-button" type="button" aria-label="Open help">
              <CircleHelp size={18} aria-hidden="true" />
            </button>
          </div>
        </TopBar>
        <HomeBackBar onHome={onHome} onBack={onBack} />
        {account?.httpWarning ? <HttpWarning /> : null}
        {account?.signOutFailed ? <p className="setup-picker-error" role="alert">ChannelForge could not sign you out. Try again.</p> : null}
        <main className="main-content">{children}</main>
        <footer className="app-footer">
          <span className="privacy-note">
            <ShieldCheck size={16} aria-hidden="true" />
            Local workspace
          </span>
          <span>ChannelForge GUI foundation</span>
        </footer>
      </div>
    </div>
  )
}
