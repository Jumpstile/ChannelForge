import { failureFromError, type FriendlyMessage } from './friendlyError'

// The browser asks the server whether sign-in is required. Sign-in mode off answers 404, so nothing changes there.
// Any other answer (including a server that cannot be reached) is treated as "not required": the server still enforces its own rules.
export type AuthState = { required: false } | { required: true; signedIn: boolean; mustChange?: boolean }

export type SignInResult = { kind: 'ok'; mustChange?: boolean } | { kind: 'wrong' } | { kind: 'wait'; seconds: number } | { kind: 'failed'; message: FriendlyMessage }
export type ChangePasswordResult = { kind: 'ok' } | { kind: 'wait'; seconds: number } | { kind: 'failed'; message: FriendlyMessage }

export type AuthApi = {
  fetchAuthState: () => Promise<AuthState>
  signIn: (password: string) => Promise<SignInResult>
  signOut: () => Promise<boolean>
  changePassword: (currentPassword: string, newPassword: string) => Promise<ChangePasswordResult>
}

export const minimumPasswordLength = 12

type ServerAnswer = { error?: string; message?: string }

async function readAnswer(response: Response): Promise<ServerAnswer> {
  try {
    const body: unknown = await response.json()
    if (typeof body !== 'object' || body === null) return {}
    const record = body as Record<string, unknown>
    return {
      error: typeof record.Error === 'string' ? record.Error : undefined,
      message: typeof record.Message === 'string' ? record.Message : undefined,
    }
  } catch {
    return {}
  }
}

function retryAfterSeconds(response: Response): number {
  const seconds = Number.parseInt(response.headers?.get('Retry-After') ?? '', 10)
  return Number.isFinite(seconds) && seconds > 0 ? seconds : 30
}

// A temporary password may only be used to choose a new one. Only a true answer is carried, so a plain sign-in looks as before.
async function readMustChange(response: Response): Promise<{ mustChange?: true }> {
  try {
    const body: unknown = await response.json()
    return typeof body === 'object' && body !== null && (body as Record<string, unknown>).MustChange === true ? { mustChange: true } : {}
  } catch {
    return {}
  }
}

function postJson(path: string, body: unknown, request: typeof fetch): Promise<Response> {
  return request(path, {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export async function fetchAuthState(request: typeof fetch = fetch): Promise<AuthState> {
  try {
    const response = await request('/api/auth/session', { method: 'GET', headers: { Accept: 'application/json' } })
    if (response.status !== 200) return { required: false }
    const body: unknown = await response.json()
    if (typeof body === 'object' && body !== null && typeof (body as Record<string, unknown>).SignedIn === 'boolean') {
      const mustChange = (body as Record<string, unknown>).MustChange === true
      return { required: true, signedIn: (body as Record<string, boolean>).SignedIn, ...(mustChange ? { mustChange } : {}) }
    }
  } catch {
    // Fall through: no usable answer means the page behaves as it does with sign-in off.
  }
  return { required: false }
}

function failedMessage(headline: string, whatHappened: string, whatToDo: string, code: string, serverMessage?: string): FriendlyMessage {
  return { headline, whatHappened, whatToDo, details: { code, message: serverMessage, cause: 'The server answered the request with an error, or the answer could not be read.' } }
}

export async function signIn(password: string, request: typeof fetch = fetch): Promise<SignInResult> {
  try {
    const response = await postJson('/api/auth/sign-in', { password }, request)
    if (response.status === 200) return { kind: 'ok', ...(await readMustChange(response)) }
    if (response.status === 401) return { kind: 'wrong' }
    if (response.status === 429) return { kind: 'wait', seconds: retryAfterSeconds(response) }
    const answer = await readAnswer(response)
    return {
      kind: 'failed',
      message: failedMessage('ChannelForge could not sign you in', 'The server did not accept the request, so you are not signed in.', 'Try again in a moment. If it keeps happening, restart ChannelForge.', answer.error ?? `http-${response.status}`, answer.message),
    }
  } catch (error) {
    const failure = failureFromError(error, 'unreachable')
    return {
      kind: 'failed',
      message: failedMessage('ChannelForge could not sign you in', 'ChannelForge could not reach its server, so you are not signed in.', 'Make sure the server is running, then try again.', 'unreachable', failure.raw),
    }
  }
}

export async function signOut(request: typeof fetch = fetch): Promise<boolean> {
  try {
    const response = await postJson('/api/auth/sign-out', {}, request)
    return response.status === 200
  } catch {
    return false
  }
}

export async function changePassword(currentPassword: string, newPassword: string, request: typeof fetch = fetch): Promise<ChangePasswordResult> {
  const headline = 'Your password was not changed'
  try {
    const response = await postJson('/api/auth/change-password', { currentPassword, newPassword }, request)
    if (response.status === 200) return { kind: 'ok' }
    if (response.status === 429) return { kind: 'wait', seconds: retryAfterSeconds(response) }
    const answer = await readAnswer(response)
    const code = answer.error ?? `http-${response.status}`
    if (response.status === 401 && code === 'sign-in-failed') {
      return { kind: 'failed', message: failedMessage(headline, 'The current password you typed did not work.', 'Check the current password and try again.', code, answer.message) }
    }
    if (response.status === 401) {
      return { kind: 'failed', message: failedMessage(headline, 'You are no longer signed in.', 'Reload this page and sign in again.', code, answer.message) }
    }
    if (response.status === 400) {
      return { kind: 'failed', message: failedMessage(headline, answer.message ?? 'The new password was not accepted.', 'Choose a different new password and try again.', code, answer.message) }
    }
    return { kind: 'failed', message: failedMessage(headline, answer.message ?? 'The server could not save the new password. Your old password still works.', 'Try again. If it keeps happening, check the server.', code, answer.message) }
  } catch (error) {
    const failure = failureFromError(error, 'unreachable')
    return { kind: 'failed', message: failedMessage(headline, 'ChannelForge could not reach its server. Your old password still works.', 'Make sure the server is running, then try again.', 'unreachable', failure.raw) }
  }
}

export const authApi: AuthApi = { fetchAuthState, signIn, signOut, changePassword }

// "1 minute and 30 seconds", never a bare number.
export function formatWait(totalSeconds: number): string {
  const seconds = Math.max(0, Math.ceil(totalSeconds))
  const minutes = Math.floor(seconds / 60)
  const rest = seconds % 60
  const part = (count: number, unit: string) => `${count} ${unit}${count === 1 ? '' : 's'}`
  if (minutes === 0) return part(rest, 'second')
  return rest === 0 ? part(minutes, 'minute') : `${part(minutes, 'minute')} and ${part(rest, 'second')}`
}

// True when the page came over plain http from an address other than this computer.
export function isPlainHttpOnNetwork(location: Pick<Location, 'protocol' | 'hostname'> = window.location): boolean {
  if (location.protocol !== 'http:') return false
  return !['localhost', '127.0.0.1', '[::1]', '::1'].includes(location.hostname.toLowerCase())
}
