import type { ReactNode } from 'react'

export function TopBar({ children }: { children: ReactNode }) {
  return (
    <header className="top-bar">
      <div className="brand-lockup" aria-label="ChannelForge">
        <span className="brand-mark" aria-hidden="true">CF</span>
        <span className="brand-name">ChannelForge</span>
      </div>
      <div className="top-bar-content">{children}</div>
    </header>
  )
}
