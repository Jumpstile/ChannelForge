import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fetchAuthState, formatWait, isPlainHttpOnNetwork, signIn, type AuthApi } from '../app/auth'
import { AuthGate } from '../components/AuthGate'
import { SignInPage } from '../components/SignInPage'
import { ChangePasswordPage } from '../pages/ChangePasswordPage'

const secret = 'correct horse battery staple'

// This test environment has no browser storage, so each test gets a plain in-memory one it can read back.
function memoryStorage() {
  const items = new Map<string, string>()
  return {
    get length() {
      return items.size
    },
    key: (index: number) => [...items.keys()][index] ?? null,
    getItem: (key: string) => items.get(key) ?? null,
    setItem: (key: string, value: string) => void items.set(key, String(value)),
    removeItem: (key: string) => void items.delete(key),
    clear: () => items.clear(),
    dump: () => JSON.stringify([...items.entries()]),
  }
}
let local = memoryStorage()
let session = memoryStorage()

beforeEach(() => {
  local = memoryStorage()
  session = memoryStorage()
  vi.stubGlobal('localStorage', local)
  vi.stubGlobal('sessionStorage', session)
})

function reply(status: number, body: unknown = {}, headers: Record<string, string> = {}) {
  return { status, json: vi.fn().mockResolvedValue(body), headers: { get: (name: string) => headers[name] ?? null } } as unknown as Response
}

function api(overrides: Partial<AuthApi> = {}): AuthApi {
  return {
    fetchAuthState: vi.fn().mockResolvedValue({ required: true, signedIn: false }),
    signIn: vi.fn().mockResolvedValue({ kind: 'ok' }),
    signOut: vi.fn().mockResolvedValue(true),
    changePassword: vi.fn().mockResolvedValue({ kind: 'ok' }),
    ...overrides,
  }
}

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('auth client', () => {
  it('treats a 404 (sign-in off) as not required', async () => {
    await expect(fetchAuthState(vi.fn().mockResolvedValue(reply(404)) as unknown as typeof fetch)).resolves.toEqual({ required: false })
  })

  it('reads the signed-in answer when sign-in is required', async () => {
    await expect(fetchAuthState(vi.fn().mockResolvedValue(reply(200, { SignedIn: false })) as unknown as typeof fetch)).resolves.toEqual({ required: true, signedIn: false })
  })

  it('sends the password only in the POST body, never in the URL', async () => {
    const request = vi.fn().mockResolvedValue(reply(200, { SignedIn: true }))
    await signIn(secret, request as unknown as typeof fetch)
    expect(request.mock.calls[0][0]).toBe('/api/auth/sign-in')
    expect(request.mock.calls[0][0]).not.toContain(secret)
    expect(request.mock.calls[0][1].body).toBe(JSON.stringify({ password: secret }))
  })

  it('says waits in plain words', () => {
    expect(formatWait(1)).toBe('1 second')
    expect(formatWait(90)).toBe('1 minute and 30 seconds')
    expect(formatWait(900)).toBe('15 minutes')
  })

  it('warns only for plain http from another address', () => {
    expect(isPlainHttpOnNetwork({ protocol: 'http:', hostname: '192.168.1.20' })).toBe(true)
    expect(isPlainHttpOnNetwork({ protocol: 'http:', hostname: 'localhost' })).toBe(false)
    expect(isPlainHttpOnNetwork({ protocol: 'http:', hostname: '127.0.0.1' })).toBe(false)
    expect(isPlainHttpOnNetwork({ protocol: 'https:', hostname: '192.168.1.20' })).toBe(false)
  })
})

describe('Sign-in page', () => {
  it('signs in and clears the password from the page', async () => {
    const onSignedIn = vi.fn()
    const signInMock = vi.fn().mockResolvedValue({ kind: 'ok' })
    const { container } = render(<SignInPage httpWarning={false} onSignedIn={onSignedIn} signIn={signInMock} />)
    const user = userEvent.setup()
    await user.type(screen.getByLabelText('Password'), secret)
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    await waitFor(() => expect(onSignedIn).toHaveBeenCalled())
    expect(signInMock).toHaveBeenCalledWith(secret)
    expect((screen.getByLabelText('Password') as HTMLInputElement).value).toBe('')
    expect(container.innerHTML).not.toContain(secret)
    expect(local.dump()).not.toContain(secret)
    expect(session.dump()).not.toContain(secret)
  })

  it('shows the plain wrong-password message and clears the field', async () => {
    const signInMock = vi.fn().mockResolvedValue({ kind: 'wrong' })
    const { container } = render(<SignInPage httpWarning={false} onSignedIn={vi.fn()} signIn={signInMock} />)
    const user = userEvent.setup()
    await user.type(screen.getByLabelText('Password'), secret)
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByText('That password did not work.')).toBeVisible()
    expect((screen.getByLabelText('Password') as HTMLInputElement).value).toBe('')
    expect(container.innerHTML).not.toContain(secret)
  })

  it('tells the person how long to wait and disables the button until then', async () => {
    const signInMock = vi.fn().mockResolvedValue({ kind: 'wait', seconds: 2 })
    render(<SignInPage httpWarning={false} onSignedIn={vi.fn()} signIn={signInMock} />)
    const user = userEvent.setup()
    await user.type(screen.getByLabelText('Password'), secret)
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByText('Too many tries. Please wait 2 seconds, then try again.')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Sign in' })).toBeDisabled()
    await waitFor(() => expect(screen.getByRole('button', { name: 'Sign in' })).toBeEnabled(), { timeout: 4000 })
    expect(screen.getByText('You can try again now.')).toBeVisible()
  })

  it('shows the plain failure with the technical text behind Details', async () => {
    const signInMock = vi.fn().mockResolvedValue({
      kind: 'failed',
      message: { headline: 'ChannelForge could not sign you in', whatHappened: 'No answer.', whatToDo: 'Try again.', details: { code: 'unreachable', cause: 'No answer from the server.', message: 'fetch failed' } },
    })
    render(<SignInPage httpWarning={false} onSignedIn={vi.fn()} signIn={signInMock} />)
    const user = userEvent.setup()
    await user.type(screen.getByLabelText('Password'), secret)
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByText('ChannelForge could not sign you in')).toBeVisible()
    expect(screen.queryByText('fetch failed')).toBeNull()
    await user.click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('fetch failed')).toBeVisible()
  })

  it('shows the HTTP warning only when asked', () => {
    const { rerender } = render(<SignInPage httpWarning={false} onSignedIn={vi.fn()} signIn={vi.fn()} />)
    expect(screen.queryByText(/plain HTTP/)).toBeNull()
    rerender(<SignInPage httpWarning onSignedIn={vi.fn()} signIn={vi.fn()} />)
    expect(screen.getByText(/plain HTTP/)).toBeVisible()
    expect(screen.getByLabelText('Password')).toBeEnabled()
  })
})

describe('Change-password page', () => {
  async function fill(user: UserEvent, current: string, next: string, repeat: string) {
    await user.type(screen.getByLabelText('Current password'), current)
    await user.type(screen.getByLabelText('New password'), next)
    await user.type(screen.getByLabelText('Type the new password again'), repeat)
    await user.click(screen.getByRole('button', { name: 'Change password' }))
  }

  it('shows the rules before submit and refuses a short password without sending', async () => {
    const change = vi.fn()
    render(<ChangePasswordPage changePassword={change} />)
    expect(screen.getByText('Use at least 12 characters.')).toBeVisible()
    expect(screen.getByText('Easy, common passwords are refused.')).toBeVisible()
    await fill(userEvent.setup(), 'old-password-here', 'short', 'short')
    expect(screen.getByRole('alert')).toHaveTextContent('at least 12 characters')
    expect(change).not.toHaveBeenCalled()
  })

  it('refuses two different new passwords without sending', async () => {
    const change = vi.fn()
    render(<ChangePasswordPage changePassword={change} />)
    await fill(userEvent.setup(), 'old-password-here', 'a-long-new-password', 'a-long-new-passwordX')
    expect(screen.getByRole('alert')).toHaveTextContent('not the same')
    expect(change).not.toHaveBeenCalled()
  })

  it('says other browsers were signed out and this one stays, and clears every field', async () => {
    const change = vi.fn().mockResolvedValue({ kind: 'ok' })
    const { container } = render(<ChangePasswordPage changePassword={change} />)
    await fill(userEvent.setup(), 'old-password-here', 'a-long-new-password', 'a-long-new-password')
    expect(await screen.findByText(/Other browsers that were signed in are now signed out\. This browser stays signed in\./)).toBeVisible()
    expect(change).toHaveBeenCalledWith('old-password-here', 'a-long-new-password')
    for (const label of ['Current password', 'New password', 'Type the new password again']) expect((screen.getByLabelText(label) as HTMLInputElement).value).toBe('')
    expect(container.innerHTML).not.toContain('a-long-new-password')
    expect(local.dump()).not.toContain('a-long-new-password')
  })

  it('shows a server refusal in plain words with Details kept', async () => {
    const change = vi.fn().mockResolvedValue({
      kind: 'failed',
      message: { headline: 'Your password was not changed', whatHappened: 'That password is too common.', whatToDo: 'Choose a different new password and try again.', details: { code: 'password-rule', cause: 'The server answered with an error.', message: 'That password is too common.' } },
    })
    render(<ChangePasswordPage changePassword={change} />)
    await fill(userEvent.setup(), 'old-password-here', 'passwordpassword', 'passwordpassword')
    expect(await screen.findByText('Your password was not changed')).toBeVisible()
    await userEvent.setup().click(screen.getByRole('button', { name: 'Details' }))
    expect(screen.getByText('password-rule')).toBeVisible()
  })

  it('shows a wait message for a 429', async () => {
    const change = vi.fn().mockResolvedValue({ kind: 'wait', seconds: 60 })
    render(<ChangePasswordPage changePassword={change} />)
    await fill(userEvent.setup(), 'old-password-here', 'a-long-new-password', 'a-long-new-password')
    expect(await screen.findByText('Too many tries. Please wait 1 minute, then try again.')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Change password' })).toBeDisabled()
  })
})

describe('Auth gate', () => {
  it('shows nothing new when sign-in is off', async () => {
    render(<AuthGate api={api({ fetchAuthState: vi.fn().mockResolvedValue({ required: false }) })} />)
    expect(await screen.findByRole('heading', { name: /Workbench|ChannelForge/i, level: 1 })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Sign out' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Change password' })).toBeNull()
    expect(screen.queryByLabelText('Password')).toBeNull()
  })

  it('shows the sign-in page when sign-in is required and there is no session', async () => {
    render(<AuthGate api={api()} />)
    expect(await screen.findByLabelText('Password')).toBeVisible()
    expect(screen.queryByRole('navigation', { name: 'Workflow pages' })).toBeNull()
  })

  it('shows the app with Sign out and Change password when signed in, and sign-out returns to sign-in', async () => {
    const mock = api({ fetchAuthState: vi.fn().mockResolvedValue({ required: true, signedIn: true }) })
    render(<AuthGate api={mock} />)
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: 'Change password' }))
    expect(await screen.findByRole('heading', { name: 'Change password', level: 1 })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Sign out' }))
    await act(async () => {})
    expect(mock.signOut).toHaveBeenCalled()
    expect(await screen.findByLabelText('Password')).toBeVisible()
  })

  it('tells the person when sign-out did not work and keeps them signed in', async () => {
    const mock = api({ fetchAuthState: vi.fn().mockResolvedValue({ required: true, signedIn: true }), signOut: vi.fn().mockResolvedValue(false) })
    render(<AuthGate api={mock} />)
    await userEvent.setup().click(await screen.findByRole('button', { name: 'Sign out' }))
    expect(await screen.findByText('ChannelForge could not sign you out. Try again.')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Sign out' })).toBeVisible()
  })
})
