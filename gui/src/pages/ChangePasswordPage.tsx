import { useEffect, useState, type FormEvent } from 'react'
import { formatWait, minimumPasswordLength, type ChangePasswordResult } from '../app/auth'
import type { FriendlyMessage } from '../app/friendlyError'
import { ErrorNotice } from '../components/ErrorNotice'
import { PageHeader } from '../components/PageHeader'

type ChangePasswordPageProps = {
  changePassword: (currentPassword: string, newPassword: string) => Promise<ChangePasswordResult>
  mustChange?: boolean
}

export function ChangePasswordPage({ changePassword, mustChange }: ChangePasswordPageProps) {
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [repeat, setRepeat] = useState('')
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const [failure, setFailure] = useState<FriendlyMessage | null>(null)
  const [done, setDone] = useState(false)
  const [waitLeft, setWaitLeft] = useState(0)
  const [waited, setWaited] = useState(false)

  useEffect(() => {
    if (waitLeft <= 0) return
    const timer = setTimeout(() => setWaitLeft((seconds) => seconds - 1), 1000)
    return () => clearTimeout(timer)
  }, [waitLeft])

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (busy || waitLeft > 0) return
    setDone(false)
    setFailure(null)
    setWaited(false)
    if (current === '') return setProblem('Type your current password.')
    if (next.length < minimumPasswordLength) return setProblem(`The new password must be at least ${minimumPasswordLength} characters long.`)
    if (next !== repeat) return setProblem('The two new passwords are not the same. Type the new password again in both boxes.')
    setProblem(null)
    // Passwords leave page state the moment they are sent.
    const [oldPassword, newPassword] = [current, next]
    setCurrent('')
    setNext('')
    setRepeat('')
    setBusy(true)
    const result = await changePassword(oldPassword, newPassword)
    setBusy(false)
    if (result.kind === 'ok') setDone(true)
    else if (result.kind === 'wait') {
      setWaitLeft(result.seconds)
      setWaited(true)
    } else setFailure(result.message)
  }

  return (
    <div className="page-stack">
      <PageHeader eyebrow="Account" title="Change password" description="Choose a new password for ChannelForge." />
      {mustChange ? <p role="status">You are using a temporary password. Choose a new password before you continue.</p> : null}
      <ul className="auth-rules">
        <li>Use at least {minimumPasswordLength} characters.</li>
        <li>Easy, common passwords are refused.</li>
      </ul>
      <form className="auth-card" onSubmit={submit}>
        <label className="auth-field">
          <span>Current password</span>
          <input autoComplete="current-password" name="current" onChange={(event) => setCurrent(event.target.value)} type="password" value={current} />
        </label>
        <label className="auth-field">
          <span>New password</span>
          <input autoComplete="new-password" name="new" onChange={(event) => setNext(event.target.value)} type="password" value={next} />
        </label>
        <label className="auth-field">
          <span>Type the new password again</span>
          <input autoComplete="new-password" name="repeat" onChange={(event) => setRepeat(event.target.value)} type="password" value={repeat} />
        </label>
        <button className="button button-primary" disabled={busy || waitLeft > 0} type="submit">Change password</button>
      </form>
      {problem ? <p className="setup-picker-error" role="alert">{problem}</p> : null}
      {waited ? (
        <p className="setup-picker-error" role="alert">
          {waitLeft > 0 ? `Too many tries. Please wait ${formatWait(waitLeft)}, then try again.` : 'You can try again now.'}
        </p>
      ) : null}
      {failure ? <ErrorNotice message={failure} /> : null}
      {done ? <p role="status">Your password was changed. Other browsers that were signed in are now signed out. This browser stays signed in.</p> : null}
    </div>
  )
}
