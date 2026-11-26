import { useEffect, useState, type FormEvent } from 'react'
import { formatWait, type SignInResult } from '../app/auth'
import { HttpWarning } from './HttpWarning'
import { ErrorNotice } from './ErrorNotice'
import { PageHeader } from './PageHeader'
import { TopBar } from './TopBar'
import type { FriendlyMessage } from '../app/friendlyError'

type SignInPageProps = {
  signIn: (password: string) => Promise<SignInResult>
  onSignedIn: () => void
  httpWarning: boolean
}

export function SignInPage({ signIn, onSignedIn, httpWarning }: SignInPageProps) {
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [wrong, setWrong] = useState(false)
  const [waitLeft, setWaitLeft] = useState(0)
  const [waited, setWaited] = useState(false)
  const [failure, setFailure] = useState<FriendlyMessage | null>(null)

  useEffect(() => {
    if (waitLeft <= 0) return
    const timer = setTimeout(() => setWaitLeft((seconds) => seconds - 1), 1000)
    return () => clearTimeout(timer)
  }, [waitLeft])

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (busy || waitLeft > 0 || password === '') return
    // The password leaves page state the moment it is sent.
    const typed = password
    setPassword('')
    setBusy(true)
    setWrong(false)
    setWaited(false)
    setFailure(null)
    const result = await signIn(typed)
    setBusy(false)
    if (result.kind === 'ok') return onSignedIn()
    if (result.kind === 'wrong') setWrong(true)
    else if (result.kind === 'wait') {
      setWaitLeft(result.seconds)
      setWaited(true)
    } else setFailure(result.message)
  }

  return (
    <div className="auth-frame">
      <TopBar>{null}</TopBar>
      <main className="main-content page-stack">
        <PageHeader eyebrow="ChannelForge" title="Sign in" description="Type the ChannelForge password to continue." />
        {httpWarning ? <HttpWarning /> : null}
        <form className="auth-card" onSubmit={submit}>
          <label className="auth-field">
            <span>Password</span>
            <input autoComplete="current-password" autoFocus name="password" onChange={(event) => setPassword(event.target.value)} type="password" value={password} />
          </label>
          <button className="button button-primary" disabled={busy || waitLeft > 0} type="submit">Sign in</button>
        </form>
        {wrong ? <p className="setup-picker-error" role="alert">That password did not work.</p> : null}
        {waited ? (
          <p className="setup-picker-error" role="alert">
            {waitLeft > 0 ? `Too many tries. Please wait ${formatWait(waitLeft)}, then try again.` : 'You can try again now.'}
          </p>
        ) : null}
        {failure ? <ErrorNotice message={failure} /> : null}
        <p className="page-description">First time here? Open the first-run page that the server console names, and choose your password there.</p>
      </main>
    </div>
  )
}
