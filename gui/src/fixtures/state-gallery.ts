import type { GalleryState } from '../components/StateCard'

export const stateGalleryFixtures: GalleryState[] = [
  {
    id: 'empty',
    status: 'Not configured',
    title: 'Add your playlist and guide',
    summary: 'No playlist or guide has been added yet. Setup is coming next.',
    nextAction: 'Add playlist and guide',
  },
  {
    id: 'loading',
    status: 'Not checked',
    title: 'Waiting for a check',
    summary: 'ChannelForge has not checked your playlist and guide yet.',
    nextAction: 'Wait',
  },
  {
    id: 'running',
    status: 'Running',
    title: 'Checking your playlist and guide',
    summary: 'ChannelForge is checking your playlist and guide now.',
    nextAction: 'Wait for the check',
  },
  {
    id: 'ready',
    status: 'Ready',
    title: 'Ready to build your lineup',
    summary: 'Your playlist and guide passed their checks.',
    nextAction: 'Continue',
  },
  {
    id: 'warning',
    status: 'Warning',
    title: 'Your lineup is ready with a warning',
    summary: 'Your lineup can continue, but one condition needs your attention.',
    nextAction: 'Read the warning',
  },
  {
    id: 'review-needed',
    status: 'Review needed',
    title: 'Please review your lineup',
    summary: 'ChannelForge needs your decision before it can continue.',
    nextAction: 'Review the lineup',
  },
  {
    id: 'blocked',
    status: 'Blocked',
    title: 'Nothing changed',
    summary: 'ChannelForge stopped before saving changes.',
    nextAction: 'Resolve the problem',
  },
  {
    id: 'failed',
    status: 'Failed',
    title: 'The check failed safely',
    summary: 'Your current lineup was not changed.',
    nextAction: 'Read why',
  },
  {
    id: 'success',
    status: 'Success',
    title: 'Your lineup is ready',
    summary: 'The check completed successfully.',
    nextAction: 'Review the result',
  },
  {
    id: 'disabled',
    status: 'Disabled',
    title: 'Automatic updates are off',
    summary: 'ChannelForge will not run checks on its own.',
    nextAction: 'Learn more',
  },
]
