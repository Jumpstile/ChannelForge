import { LiveNowPage } from './pages/LiveNowPage'
import { OneGuideCategoryPage } from './pages/OneGuideCategoryPage'
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
import { ChannelLineupPage } from './pages/ChannelLineupPage'
import { GlossaryPage } from './pages/GlossaryPage'
import { GuidedSetupPage } from './pages/GuidedSetupPage'
import { LineupReviewPage } from './pages/LineupReviewPage'
import { SavedLineupPage } from './pages/SavedLineupPage'
import { StateGalleryPage } from './pages/StateGalleryPage'
import { WorkbenchPage } from './pages/WorkbenchPage'
import { TimelineGridPage } from './pages/TimelineGridPage'

type AppProps = {
  picker?: SetupPicker
  matcher?: SetupMatcher
  planner?: SavedLineupPlanner
  acceptor?: SavedLineupAcceptor
  pickerAvailable?: boolean
}

function App({ picker, matcher, planner = prepareSavedLineupPlan, acceptor = acceptSavedLineup, pickerAvailable }: AppProps = {}) {
  const [activePage, setCurrentPage] = useState<NavigationId>('workbench')
  const [history, setHistory] = useState<NavigationId[]>([])
  const [matchState, setMatchState] = useState<PlaylistGuideMatchState>(createInitialPlaylistGuideMatchState)
  const [savedPlan, setSavedPlan] = useState<SavedLineupPlan | null>(null)
  const [saveResult, setSaveResult] = useState<SavedLineupResult | null>(null)
  const [acceptedLineupStatus, setAcceptedLineupStatus] = useState<AcceptedLineupStatus>('unavailable')
  const reviewAvailable = isPlaylistGuideReviewAvailable(matchState)
  const savedLineupAvailable = acceptedLineupStatus === 'present'

  const setActivePage = (page: NavigationId) => {
    if (page === activePage) return
    setHistory((earlier) => [...earlier, activePage])
    setCurrentPage(page)
  }

  const handleHome = () => {
    setHistory([])
    setCurrentPage('workbench')
  }

  const isAvailable = (page: NavigationId) => !(page === 'build' && !reviewAvailable) && !(page === 'accepted' && !savedLineupAvailable)

  const handleBack = () => {
    const remaining = [...history]
    while (remaining.length > 0 && !isAvailable(remaining[remaining.length - 1])) remaining.pop()
    const previous = remaining.pop()
    if (previous === undefined) return handleHome()
    setHistory(remaining)
    setCurrentPage(previous)
  }

  const handleNavigate = (page: NavigationId) => {
    if (!isAvailable(page)) return
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
    <AppShell activePage={activePage} navigationAvailability={{ build: reviewAvailable, accepted: savedLineupAvailable }} onNavigate={handleNavigate} onHome={handleHome} onBack={handleBack}>
      {activePage === 'gallery' ? (
        <StateGalleryPage />
      ) : activePage === 'live-now' ? (
        <LiveNowPage />
      ) : activePage === 'wrestling' ? (
        <OneGuideCategoryPage />
      ) : activePage === 'timeline' ? (
        <TimelineGridPage />
      ) : activePage === 'channels' ? (
        <ChannelLineupPage onOpenSetup={() => setActivePage('setup')} />
      ) : activePage === 'learn' ? (
        <GlossaryPage />
      ) : activePage === 'setup' ? (
        <GuidedSetupPage picker={picker} matcher={matcher} pickerAvailable={pickerAvailable} matchState={matchState} onMatchStateChange={handleMatchStateChange} onOpenReview={() => setActivePage('build')} />
      ) : activePage === 'build' && reviewAvailable ? (
        <LineupReviewPage
          acceptor={acceptor}
          matchState={matchState}
          onPlanChange={handlePlanChange}
          onSavedLineupChange={handleSavedLineupChange}
          planner={planner}
          plan={savedPlan}
          saveResult={saveResult}
        />
      ) : activePage === 'accepted' && savedLineupAvailable ? (
        <SavedLineupPage acceptedEntryCount={saveResult?.acceptedEntryCount ?? savedPlan?.acceptedEntryCount ?? null} />
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
