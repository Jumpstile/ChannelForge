import type { GalleryState } from '../components/StateCard'

export const stateGalleryFixtures: GalleryState[] = [
  {
    id: 'empty',
    status: 'Not configured',
    title: 'Your workspace is ready for setup',
    summary: 'No sources have been connected. Start with the guided path when the setup slice is available.',
    nextAction: 'Start guided setup',
  },
  {
    id: 'loading',
    status: 'Not checked',
    title: 'Waiting for a validation result',
    summary: 'ChannelForge has not checked this workspace yet.',
    nextAction: 'Validate sources',
  },
  {
    id: 'running',
    status: 'Running',
    title: 'Checking source evidence',
    summary: 'The operation is in progress. The shell will show forward progress and a safe cancel action.',
    nextAction: 'Wait for the current stage',
  },
  {
    id: 'ready',
    status: 'Ready',
    title: 'Ready to build a candidate',
    summary: 'Required inputs have passed their checks and no blocking review is present.',
    nextAction: 'Build candidate',
  },
  {
    id: 'warning',
    status: 'Warning',
    title: 'Ready with a warning',
    summary: 'The operation can continue, but one non-blocking condition should be understood.',
    nextAction: 'Read the warning',
  },
  {
    id: 'review-needed',
    status: 'Review needed',
    title: 'A human decision is required',
    summary: 'The evidence is not strong enough for ChannelForge to decide safely on its own.',
    nextAction: 'Review the evidence',
  },
  {
    id: 'blocked',
    status: 'Blocked',
    title: 'Nothing changed',
    summary: 'ChannelForge stopped before the unsafe step and preserved the current accepted state.',
    nextAction: 'Resolve the blocking condition',
  },
  {
    id: 'failed',
    status: 'Failed',
    title: 'The operation failed safely',
    summary: 'The last-known-good result remains protected while the failure is investigated.',
    nextAction: 'Open the failure explanation',
  },
  {
    id: 'success',
    status: 'Success',
    title: 'The result is ready to inspect',
    summary: 'The operation completed with validated evidence and a clear next step.',
    nextAction: 'Review the result',
  },
  {
    id: 'disabled',
    status: 'Disabled',
    title: 'Scheduling is off',
    summary: 'No unattended action is enabled for this workspace.',
    nextAction: 'Learn about scheduling',
  },
]
