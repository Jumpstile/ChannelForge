import { useState } from 'react'
import { AppShell } from './app/AppShell'
import type { NavigationId } from './app/navigation'
import {
  createInitialPlaylistGuideMatchState,
  isPlaylistGuideReviewAvailable,
  type PlaylistGuideMatchState,
  type SetupMatcher,
  type SetupPicker,
} from './app/setupSelection'
import { GuidedSetupPage } from './pages/GuidedSetupPage'
import { LineupReviewPage } from './pages/LineupReviewPage'
import { StateGalleryPage } from './pages/StateGalleryPage'
import { WorkbenchPage } from './pages/WorkbenchPage'

type AppProps = {
  picker?: SetupPicker
  matcher?: SetupMatcher
  pickerAvailable?: boolean
}

function App({ picker, matcher, pickerAvailable }: AppProps = {}) {
  const [activePage, setActivePage] = useState<NavigationId>('workbench')
  const [matchState, setMatchState] = useState<PlaylistGuideMatchState>(createInitialPlaylistGuideMatchState)
  const reviewAvailable = isPlaylistGuideReviewAvailable(matchState)

  const handleNavigate = (page: NavigationId) => {
    if (page === 'build' && !reviewAvailable) return
    setActivePage(page)
  }

  return (
    <AppShell activePage={activePage} navigationAvailability={{ build: reviewAvailable }} onNavigate={handleNavigate}>
      {activePage === 'gallery' ? (
        <StateGalleryPage onBack={() => setActivePage('workbench')} />
      ) : activePage === 'setup' ? (
        <GuidedSetupPage picker={picker} matcher={matcher} pickerAvailable={pickerAvailable} matchState={matchState} onMatchStateChange={setMatchState} onOpenReview={() => setActivePage('build')} />
      ) : activePage === 'build' && reviewAvailable ? (
        <LineupReviewPage matchState={matchState} onBack={() => setActivePage('setup')} />
      ) : (
        <WorkbenchPage
          onOpenGallery={() => setActivePage('gallery')}
          onOpenSetup={() => setActivePage('setup')}
        />
      )}
    </AppShell>
  )
}

export default App
