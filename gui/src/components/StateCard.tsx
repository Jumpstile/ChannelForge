import type { UiStatus } from './StatusBadge'
import { StatusBadge } from './StatusBadge'

export type GalleryState = {
  id: string
  status: UiStatus
  title: string
  summary: string
  nextAction: string
}

export function StateCard({ state }: { state: GalleryState }) {
  return (
    <article className="state-card">
      <div className="state-card-header">
        <StatusBadge status={state.status} />
        <span className="state-card-id">{state.id}</span>
      </div>
      <h2>{state.title}</h2>
      <p>{state.summary}</p>
      <div className="state-card-action">
        <span className="state-card-action-label">Next safe action</span>
        <span>{state.nextAction}</span>
      </div>
    </article>
  )
}
