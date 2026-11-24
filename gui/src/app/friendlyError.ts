// One shared shape for user-facing errors: plain words first, technical text under Details.
export type FriendlyMessage = {
  headline: string
  whatHappened: string
  whatToDo: string
  details: { code?: string; message?: string; cause: string }
}

// Thrown by app code so a page can show the full message, not just a string.
export class FriendlyError extends Error {
  readonly friendly: FriendlyMessage
  constructor(friendly: FriendlyMessage) {
    super(friendly.headline)
    this.friendly = friendly
  }
}

// Turns anything that was thrown into a FriendlyMessage. Unknown errors never show a bare code.
export function toFriendlyMessage(error: unknown, fallback: FriendlyMessage): FriendlyMessage {
  if (error instanceof FriendlyError) return error.friendly
  const message = error instanceof Error && error.message ? error.message : undefined
  return { ...fallback, details: { ...fallback.details, message } }
}

// What the code can tell apart when a read fails. 'unknown' means the caller could not tell why.
// raw is the real technical text (HTTP status, thrown error message); the full text is always under Details, and a short plain one-sentence version may also be quoted up front (see plainMessage.ts).
export type LoadFailureKind = 'unreachable' | 'refused' | 'server-error' | 'not-understood' | 'changed' | 'unknown'
export type LoadFailure = { loadFailure: LoadFailureKind; raw?: string }

export const loadFailure = (kind: LoadFailureKind, raw?: string): LoadFailure => (raw ? { loadFailure: kind, raw } : { loadFailure: kind })
export const isLoadFailure = (value: unknown): value is LoadFailure => typeof value === 'object' && value !== null && 'loadFailure' in value
// A null or missing result carries no reason, so it reads as 'unknown'.
export const failureOf = (value: unknown): LoadFailure => (isLoadFailure(value) ? value : loadFailure('unknown'))
// Something was thrown: keep its message as the raw text.
export const failureFromError = (error: unknown, kind: LoadFailureKind = 'unknown'): LoadFailure => loadFailure(kind, error instanceof Error ? error.message : undefined)

// A non-200 answer: not allowed, a server error, or something this screen has no use for (for example an older server without the route).
export function failureForStatus(status: number): LoadFailure {
  const raw = `HTTP status ${status}`
  if (status === 401 || status === 403) return loadFailure('refused', raw)
  return loadFailure(status >= 500 ? 'server-error' : 'not-understood', raw)
}

const loadFailureText: Record<Exclude<LoadFailureKind, 'unknown'>, { why: string; next: string; cause: string }> = {
  unreachable: {
    why: 'ChannelForge could not reach its server. The server is most likely not running.',
    next: 'Start ChannelForge if it is closed, then try again.',
    cause: 'The request to the local ChannelForge server did not get an answer.',
  },
  refused: {
    why: 'The server refused the request, so this screen is not allowed to read it.',
    next: 'Restart ChannelForge, then try again.',
    cause: 'The server answered that the request was not allowed (HTTP 401 or 403).',
  },
  'server-error': {
    why: 'The server reported an error while it was working on this.',
    next: 'Wait a moment and try again. If it keeps happening, restart ChannelForge.',
    cause: 'The server answered with an error status (HTTP 500 or higher).',
  },
  'not-understood': {
    why: 'ChannelForge received information from the server that this version of the screen does not understand. This usually means ChannelForge was updated, or was only partly updated.',
    next: 'Restart ChannelForge. If this keeps happening, update ChannelForge.',
    cause: 'The server answered, but the answer was not in a shape this version of the screen accepts, or the server does not offer this page.',
  },
  changed: {
    why: 'The saved lineup changed while ChannelForge was loading it.',
    next: 'Try again.',
    cause: 'The server reported that the saved lineup has a newer version than the one the page started with.',
  },
}

// The plain reason for screens that write a message of their own (for example a failed Refresh); null when no reason is known.
export const failureWhy = (failure: LoadFailure): string | null => (failure.loadFailure === 'unknown' ? null : loadFailureText[failure.loadFailure].why)

// For read-only page loads (GET requests): nothing is written, so "nothing was changed" is true.
// whatToDo is a hint for 'unreachable' and 'unknown'; every other kind gets its own next step.
export function loadFailedMessage(what: string, code: string, whatToDo = 'Make sure ChannelForge is still running, then try again.', failure: LoadFailure = loadFailure('unknown')): FriendlyMessage {
  const kind = failure.loadFailure
  const known = kind === 'unknown' ? null : loadFailureText[kind]
  return {
    headline: `ChannelForge could not load ${what}`,
    whatHappened: `${known ? known.why : failure.raw ? 'The request failed before ChannelForge got a usable answer. Open Details for the technical information.' : 'ChannelForge could not tell why. Open Details for the technical information.'} This page only reads information, so nothing was changed.`,
    whatToDo: known && kind !== 'unreachable' ? known.next : whatToDo,
    details: { code, message: failure.raw, cause: known ? known.cause : 'The request to the local ChannelForge server failed or the answer could not be read, and ChannelForge could not tell which. The server may be stopped, or may be a different version from this page.' },
  }
}
