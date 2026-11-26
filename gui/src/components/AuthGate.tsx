import { useEffect, useState } from 'react'
import App from '../App'
import { authApi, isPlainHttpOnNetwork, type AuthApi, type AuthState } from '../app/auth'
import { SignInPage } from './SignInPage'

type GateState = 'checking' | 'open' | 'signed-out' | 'signed-in'

// Asks the server once whether sign-in is required. With sign-in off the app renders exactly as before.
export function AuthGate({ api = authApi }: { api?: AuthApi }) {
  const [state, setState] = useState<GateState>('checking')
  const [signOutFailed, setSignOutFailed] = useState(false)
  const httpWarning = isPlainHttpOnNetwork()

  useEffect(() => {
    let current = true
    api.fetchAuthState().then((auth: AuthState) => {
      if (current) setState(!auth.required ? 'open' : auth.signedIn ? 'signed-in' : 'signed-out')
    })
    return () => {
      current = false
    }
  }, [api])

  if (state === 'checking') return null
  if (state === 'open') return <App />
  if (state === 'signed-out') return <SignInPage httpWarning={httpWarning} onSignedIn={() => setState('signed-in')} signIn={api.signIn} />

  const handleSignOut = async () => {
    if (await api.signOut()) {
      setSignOutFailed(false)
      setState('signed-out')
    } else setSignOutFailed(true)
  }
  return <App account={{ changePassword: api.changePassword, httpWarning, onSignOut: handleSignOut, signOutFailed }} />
}
