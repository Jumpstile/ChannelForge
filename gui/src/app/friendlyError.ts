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

// For read-only page loads (GET requests): nothing is written, so "nothing was changed" is true.
export function loadFailedMessage(what: string, code: string, whatToDo = 'Make sure ChannelForge is still running, then try again.'): FriendlyMessage {
  return {
    headline: `ChannelForge could not load ${what}`,
    whatHappened: 'This page only reads information, so nothing was changed.',
    whatToDo,
    details: { code, cause: 'The request to the local ChannelForge server failed or the answer could not be read. The server may be stopped, or may be a different version from this page.' },
  }
}
