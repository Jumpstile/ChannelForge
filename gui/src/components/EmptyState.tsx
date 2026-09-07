import type { ReactNode } from 'react'

export function EmptyState({ title, children, action }: { title: string; children: string; action?: ReactNode }) {
  return (
    <section className="empty-state">
      <div className="empty-state-mark" aria-hidden="true">—</div>
      <h2>{title}</h2>
      <p>{children}</p>
      {action && <div className="empty-state-action">{action}</div>}
    </section>
  )
}
