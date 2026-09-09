import { useState } from 'react'
import { AppShell } from './app/AppShell'
import { acceptSavedLineup, prepareSavedLineupPlan } from './app/setupPicker'
import type { NavigationId } from './app/navigation'
import {
  acceptedLineupStatusAfterMatchStateChange,
  createInitialPlaylistGuideMatchState,
  isPlaylistGuideReviewAvailable,
  type AcceptedLineupStatus,
  type PlaylistGuideMatchState,
  type SavedLineupAcceptor,
  type SavedLineupPlan,
  type SavedLineupPlanner,
  type SavedLineupResult,
  type SetupMatcher,
  type SetupPicker,
} from './app/setupSelection'
import { GuidedSetupPage } from './pages/GuidedSetupPage'
import { LineupReviewPage } from './pages/LineupReviewPage'
import { SavedLineupPage } from './pages/SavedLineupPage'
import { StateGalleryPage } from './pages/StateGalleryPage'
import { WorkbenchPage } from './pages/WorkbenchPage'

type AppProps = {
  picker?: SetupPicker
  matcher?: SetupMatcher
  planner?: SavedLineupPlanner
  acceptor?: SavedLineupAcceptor
  pickerAvailable?: boolean
}

function App({ picker, matcher, planner = prepareSavedLineupPlan, acceptor = acceptSavedLineup, pickerAvailable }: AppProps = {}) {
  const [activePage, setActivePage] = useState<NavigationId>('workbench')
  const [matchState, setMatchState] = useState<PlaylistGuideMatchState>(createInitialPlaylistGuideMatchState)
  const [savedPlan, setSavedPlan] = useState<SavedLineupPlan | null>(null)
  const [saveResult, setSaveResult] = useState<SavedLineupResult | null>(null)
  const [acceptedLineupStatus, setAcceptedLineupStatus] = useState<AcceptedLineupStatus>('unavailable')
  const reviewAvailable = isPlaylistGuideReviewAvailable(matchState)
  const savedLineupAvailable = acceptedLineupStatus === 'present'

  const handleNavigate = (page: NavigationId) => {
    if (page === 'build' && !reviewAvailable) return
    if (page === 'accepted' && !savedLineupAvailable) return
    setActivePage(page)
  }

  const handleMatchStateChange = (nextState: PlaylistGuideMatchState) => {
    setMatchState(nextState)
    setSavedPlan(null)
    setSaveResult(null)
    setAcceptedLineupStatus((currentStatus) => acceptedLineupStatusAfterMatchStateChange(currentStatus, nextState.status))
  }

  const handlePlanChange = (plan: SavedLineupPlan | null) => {
    setSavedPlan(plan)
    if (plan?.acceptedLineupStatus === 'present' || plan?.acceptedLineupStatus === 'none') {
      setAcceptedLineupStatus(plan.acceptedLineupStatus)
    }
  }

  const handleSavedLineupChange = (result: SavedLineupResult) => {
    setSaveResult(result)
    if (result.saveStatus === 'saved') {
      setAcceptedLineupStatus(result.acceptedLineupStatus)
    }
  }

  return (
    <AppShell activePage={activePage} navigationAvailability={{ build: reviewAvailable, accepted: savedLineupAvailable }} onNavigate={handleNavigate}>
      {activePage === 'gallery' ? (
        <StateGalleryPage onBack={() => setActivePage('workbench')} />
      ) : activePage === 'setup' ? (
        <GuidedSetupPage picker={picker} matcher={matcher} pickerAvailable={pickerAvailable} matchState={matchState} onMatchStateChange={handleMatchStateChange} onOpenReview={() => setActivePage('build')} />
      ) : activePage === 'build' && reviewAvailable ? (
        <LineupReviewPage
          acceptor={acceptor}
          matchState={matchState}
          onBack={() => setActivePage('setup')}
          onPlanChange={handlePlanChange}
          onSavedLineupChange={handleSavedLineupChange}
          planner={planner}
          plan={savedPlan}
          saveResult={saveResult}
        />
      ) : activePage === 'accepted' && savedLineupAvailable ? (
        <SavedLineupPage acceptedEntryCount={saveResult?.acceptedEntryCount ?? savedPlan?.acceptedEntryCount ?? null} onBack={() => setActivePage('build')} />
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
