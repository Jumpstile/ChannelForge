import { useEffect, useState } from 'react'
import { StatusBanner } from './StatusBanner'
import { fetchWebStatus, type WebStatusFetcher } from '../app/webStatus'

type DashboardState = 'loading' | 'ready' | 'unavailable'

type StatusDashboardProps = {
  fetchStatus?: WebStatusFetcher
}

export function StatusDashboard({ fetchStatus = fetchWebStatus }: StatusDashboardProps) {
  const [state, setState] = useState<DashboardState>('loading')
  const [lineupAccepted, setLineupAccepted] = useState(false)

  useEffect(() => {
    let mounted = true

    void fetchStatus()
      .then((snapshot) => {
        if (!mounted) return
        if (snapshot === null) {
          setState('unavailable')
          return
        }
        setLineupAccepted(snapshot.lineupAccepted)
        setState('ready')
      })
      .catch(() => {
        if (mounted) setState('unavailable')
      })

    return () => {
      mounted = false
    }
  }, [fetchStatus])

  if (state === 'loading') {
    return (
      <StatusBanner status="Not checked" title="Checking ChannelForge status">
        <p>Checking whether your local ChannelForge server is ready.</p>
        <p><strong>Read-only status.</strong> This page can show status, but it cannot change your lineup yet.</p>
      </StatusBanner>
    )
  }

  if (state === 'unavailable') {
    return (
      <StatusBanner status="Warning" title="ChannelForge status is unavailable">
        <p>We could not read the local server status. Check that ChannelForge is running, then refresh this page.</p>
        <p><strong>Read-only status.</strong> This page can show status, but it cannot change your lineup yet.</p>
      </StatusBanner>
    )
  }

  return (
    <StatusBanner status="Ready" title="ChannelForge is running">
      <p>{lineupAccepted ? 'An accepted lineup is available.' : 'No lineup has been accepted yet.'}</p>
      <p>{lineupAccepted ? 'Open Guided Setup to review.' : 'Open Guided Setup to begin.'}</p>
      <p><strong>Read-only status.</strong> This page can show status, but it cannot change your lineup yet.</p>
    </StatusBanner>
  )
}
