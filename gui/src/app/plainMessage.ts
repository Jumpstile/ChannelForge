// A short, plain version of a raw message for the top of a notice; null when the message is empty or looks technical.
const MAX_LENGTH = 120
const TECHNICAL = [
  /^[{[<]/,
  /^\s*at\s.+[(:]/m,
  /\bat line\b|Exception|Traceback|stack ?trace/i,
  /[A-Za-z]:[\\/]|\\\\|(?:^|\s)~?\/[\w.-]+\/|\w\/[\w.-]+\.\w{1,5}\b/,
  /[a-z][a-z0-9+.-]*:\/\/|\bwww\./i,
  /[0-9a-f]{12,}|[A-Za-z0-9_-]{25,}/i,
]

export function plainMessageSummary(raw: string | undefined): string | null {
  if (!raw || TECHNICAL.some((pattern) => pattern.test(raw.trim()))) return null
  const text = raw.replace(/[\u0000-\u001f\u007f-\u009f]+/g, ' ').replace(/\s+/g, ' ').trim()
  const visible = text.replace(/\s/g, '')
  if (!visible || (visible.replace(/\p{L}/gu, '').length / visible.length) > 0.3) return null
  if (text.length <= MAX_LENGTH) return text
  const cut = text.slice(0, MAX_LENGTH + 1)
  const space = cut.lastIndexOf(' ')
  return `${(space > 0 ? cut.slice(0, space) : cut.slice(0, MAX_LENGTH)).replace(/[\s.,;:]+$/, '')}...`
}
