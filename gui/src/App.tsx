import { useState } from 'react'
import { AppShell } from './app/AppShell'
import type { NavigationId } from './app/navigation'
import { StateGalleryPage } from './pages/StateGalleryPage'
import { WorkbenchPage } from './pages/WorkbenchPage'

function App() {
  const [activePage, setActivePage] = useState<NavigationId>('workbench')

  return (
    <AppShell activePage={activePage} onNavigate={setActivePage}>
      {activePage === 'gallery' ? (
        <StateGalleryPage onBack={() => setActivePage('workbench')} />
      ) : (
        <WorkbenchPage onOpenGallery={() => setActivePage('gallery')} />
      )}
    </AppShell>
  )
}

export default App
