import { forwardRef, useState } from 'react'
import type { FriendlyMessage } from '../app/friendlyError'

// Plain words first; technical text only behind the Details button (same toggle pattern as the Guided Setup checks).
export const ErrorNotice = forwardRef<HTMLDivElement, { message: FriendlyMessage }>(function ErrorNotice({ message }, ref) {
  const [open, setOpen] = useState(false)
  const { headline, whatHappened, whatToDo, details } = message
  return (
    <div className="setup-picker-error error-notice" ref={ref} role="alert" tabIndex={-1}>
      <p className="error-notice-headline">{headline}</p>
      <p className="error-notice-body">{whatHappened}</p>
      <p className="error-notice-body"><strong>What to do:</strong> {whatToDo}</p>
      <div>
        <button aria-expanded={open} className="button button-secondary" type="button" onClick={() => setOpen(!open)}>{open ? 'Hide details' : 'Details'}</button>
      </div>
      {open ? (
        <dl className="error-notice-details">
          {details.code ? <><dt>Error code</dt><dd><code>{details.code}</code></dd></> : null}
          <dt>What this means</dt><dd>{details.cause}</dd>
          {details.message ? <><dt>Full message</dt><dd>{details.message}</dd></> : null}
        </dl>
      ) : null}
    </div>
  )
})
