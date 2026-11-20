import { CheckCircle2, CircleAlert, CircleDashed, CircleDot, CircleOff, CircleX, Clock3, Info, LoaderCircle, ShieldAlert } from 'lucide-react'

export type UiStatus = 'Not configured' | 'Not checked' | 'Ready' | 'Running' | 'Waiting' | 'Success' | 'Warning' | 'Review needed' | 'Blocked' | 'Failed' | 'Disabled'

const statusIcons = {
  'Not configured': CircleDashed,
  'Not checked': CircleDot,
  Ready: CheckCircle2,
  Running: LoaderCircle,
  Waiting: Clock3,
  Success: CheckCircle2,
  Warning: CircleAlert,
  'Review needed': ShieldAlert,
  Blocked: CircleX,
  Failed: CircleX,
  Disabled: CircleOff,
} as const

const statusClasses = {
  'Not configured': 'neutral',
  'Not checked': 'neutral',
  Ready: 'ready',
  Running: 'running',
  Waiting: 'waiting',
  Success: 'ready',
  Warning: 'warning',
  'Review needed': 'review',
  Blocked: 'error',
  Failed: 'error',
  Disabled: 'disabled',
} as const

export function StatusBadge({ status }: { status: UiStatus }) {
  const Icon = statusIcons[status] ?? Info
  return (
    <span className={`status-badge status-${statusClasses[status]}`}>
      <Icon className={status === 'Running' ? 'status-icon-spinning' : undefined} size={15} aria-hidden="true" />
      <span>{status}</span>
    </span>
  )
}
