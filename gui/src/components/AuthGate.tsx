import { useEffect, useState } from 'react'
import App from '../App'
import { authApi, isPlainHttpOnNetwork, type AuthApi, type AuthState } from '../app/auth'
import { SignInPage } from './SignInPage'

type GateState = 'checking' | 'open' | 'signed-out' | 'signed-in'

// Asks the server once whether sign-in is required. With sign-in off the app renders exactly as before.
export function AuthGate({ api = authApi }: { api?: AuthApi }) {
  const [state, setState] = useState<GateState>('checking')
  const [signOutFailed, setSignOutFailed] = useState(false)
  const [mustChange, setMustChange] = useState(false)
  const httpWarning = isPlainHttpOnNetwork()

  useEffect(() => {
    let current = true
    api.fetchAuthState().then((auth: AuthState) => {
      if (!current) return
      setMustChange(auth.required && auth.signedIn && auth.mustChange === true)
      setState(!auth.required ? 'open' : auth.signedIn ? 'signed-in' : 'signed-out')
    })
    return () => {
      current = false
    }
  }, [api])

  if (state === 'checking') return null
  if (state === 'open') return <App />
  if (state === 'signed-out') {
    return (
      <SignInPage
        httpWarning={httpWarning}
        onSignedIn={(mustChangeNow) => {
          setMustChange(mustChangeNow === true)
          setState('signed-in')
        }}
        signIn={api.signIn}
      />
    )
  }

  const handleSignOut = async () => {
    if (await api.signOut()) {
      setSignOutFailed(false)
      setState('signed-out')
    } else setSignOutFailed(true)
  }
  const changePassword: AuthApi['changePassword'] = async (currentPassword, newPassword) => {
    const result = await api.changePassword(currentPassword, newPassword)
    if (result.kind === 'ok') setMustChange(false)
    return result
  }
  return <App account={{ changePassword, httpWarning, mustChange, onSignOut: handleSignOut, signOutFailed }} />
}
