export type NavigationId = 'workbench' | 'sources' | 'validation' | 'build' | 'accepted' | 'schedule' | 'learn' | 'gallery'

export type NavigationItem = {
  id: NavigationId
  label: string
  description: string
  available: boolean
}

export type NavigationGroup = {
  label: string
  items: NavigationItem[]
}

export const navigationGroups: NavigationGroup[] = [
  {
    label: 'Workspace',
    items: [
      { id: 'workbench', label: 'Workbench', description: 'See the safest next step', available: true },
    ],
  },
  {
    label: 'Setup',
    items: [
      { id: 'sources', label: 'Sources', description: 'Add playlist and guide sources', available: false },
      { id: 'validation', label: 'Validate & refresh', description: 'Check source readiness', available: false },
    ],
  },
  {
    label: 'Decide',
    items: [
      { id: 'build', label: 'Build & review', description: 'Compare a candidate lineup', available: false },
      { id: 'accepted', label: 'Accepted lineup', description: 'View the trusted generation', available: false },
    ],
  },
  {
    label: 'Operate',
    items: [
      { id: 'schedule', label: 'Schedule', description: 'Review local schedule health', available: false },
    ],
  },
  {
    label: 'Help',
    items: [
      { id: 'learn', label: 'Learn', description: 'Understand ChannelForge terms', available: false },
    ],
  },
]
