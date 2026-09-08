export type NavigationId = 'workbench' | 'setup' | 'sources' | 'validation' | 'build' | 'accepted' | 'schedule' | 'learn' | 'gallery'

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
      { id: 'setup', label: 'Guided Setup', description: 'Choose a workspace, playlist, and guide', available: true },
      { id: 'sources', label: 'Playlist', description: 'Add playlist', available: false },
      { id: 'validation', label: 'Guide', description: 'Add guide', available: false },
    ],
  },
  {
    label: 'Decide',
    items: [
      { id: 'build', label: 'Lineup', description: 'Review your lineup', available: false },
      { id: 'accepted', label: 'Saved lineup', description: 'See what you saved', available: false },
    ],
  },
  {
    label: 'Operate',
    items: [
      { id: 'schedule', label: 'Automatic updates', description: 'Review automatic updates', available: false },
    ],
  },
  {
    label: 'Help',
    items: [
      { id: 'learn', label: 'Learn', description: 'Understand ChannelForge terms', available: false },
    ],
  },
]
