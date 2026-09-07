import { CheckCircle2, CircleAlert, CircleDashed, CircleX, Clock3, Info, LoaderCircle, ShieldAlert } from 'lucide-react'
import type { ReactNode } from 'react'
import type { UiStatus } from './StatusBadge'
import { StatusBadge } from './StatusBadge'

const bannerIcons = {
  'Not configured': CircleDashed,
  'Not checked': CircleDashed,
  Ready: CheckCircle2,
  Running: LoaderCircle,
  Waiting: Clock3,
  Success: CheckCircle2,
  Warning: CircleAlert,
  'Review needed': ShieldAlert,
  Blocked: CircleX,
  Failed: CircleX,
  Disabled: Info,
} as const

export function StatusBanner({ status, title, children }: { status: UiStatus; title: string; children: ReactNode }) {
  const Icon = bannerIcons[status]
  return (
    <section className={`status-banner status-banner-${status.toLowerCase().replaceAll(' ', '-')}`} aria-label={`${status}: ${title}`}>
      <div className="status-banner-icon"><Icon size={22} aria-hidden="true" /></div>
      <div className="status-banner-copy">
        <div className="status-banner-heading">
          <h2>{title}</h2>
          <StatusBadge status={status} />
        </div>
        <div className="status-banner-message">{children}</div>
      </div>
    </section>
  )
}
