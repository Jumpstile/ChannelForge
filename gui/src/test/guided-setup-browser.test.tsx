import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { GuidedSetupPage } from '../pages/GuidedSetupPage'
import type { GuidedSetupAcceptanceSubmitter, GuidedSetupProposalSubmitter } from '../app/guidedSetupProposal'

const readyProposal = {
  Version: 'guided-setup/proposal/v1' as const,
  Status: 'PROPOSAL_READY' as const,
  Proposal: {
    ProposalId: 'a'.repeat(32),
    ChannelCount: 2,
    ExactGuideMatchCount: 1,
    AmbiguityCount: 0,
    UnmatchedPlaylistCount: 1,
    GuideOnlyCount: 0,
    GuideStatus: 'XMLTV_SELECTED' as const,
    CanAccept: true,
    BlockingReasons: [],
  },
  Warnings: [{ Code: 'unmatched-playlist-entry', Message: 'Some playlist entries have no exact guide match.' }],
  Safety: {
    PublicationState: 'CandidateOnly' as const,
    AcceptedStateMutation: 'none' as const,
    ProviderMutation: 'none' as const,
    DownstreamMutation: 'none' as const,
    GuidePublication: 'none' as const,
    CanPublish: false as const,
    CanAccept: true,
  },
}

const accepted = {
  Version: 'guided-setup/acceptance/v1' as const,
  Status: 'ACCEPTED' as const,
  Proposal: { ChannelCount: 2, GuideStatus: 'XMLTV_ACCEPTED' as const },
  Safety: {
    AcceptedStateMutation: 'accepted-lineup' as const,
    ProviderMutation: 'none' as const,
    DownstreamMutation: 'none' as const,
    SchedulerMutation: 'none' as const,
  },
}

describe('browser Guided Setup proposal and acceptance', () => {
  it('reviews browser files, hides candidate hashes, and accepts only after acknowledgement', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupProposalSubmitter>().mockResolvedValue(readyProposal)
    const acceptanceSubmitter = vi.fn<GuidedSetupAcceptanceSubmitter>().mockResolvedValue(accepted)
    render(<GuidedSetupPage pickerAvailable={false} proposalSubmitter={submitter} acceptanceSubmitter={acceptanceSubmitter} />)

    const playlist = new File(['#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one\n'], 'channels.m3u', { type: 'audio/x-mpegurl' })
    const guide = new File(['<?xml version="1.0"?><tv></tv>'], 'guide.xml', { type: 'application/xml' })
    await user.upload(screen.getByLabelText('Choose playlist'), playlist)
    await user.upload(screen.getByLabelText('Choose guide (optional)'), guide)
    await user.click(screen.getByRole('button', { name: 'Analyze proposal' }))

    expect(submitter).toHaveBeenCalledWith(playlist, guide)
    expect(await screen.findByText('Review ready. Nothing has been accepted yet.')).toBeInTheDocument()
    expect(screen.getByText('Some playlist entries have no exact guide match.')).toBeInTheDocument()
    expect(screen.queryByText('a'.repeat(64))).not.toBeInTheDocument()
    const acceptButton = screen.getByRole('button', { name: 'Accept reviewed proposal' })
    expect(acceptButton).toBeDisabled()

    await user.click(screen.getByLabelText(/I reviewed these results/))
    expect(acceptButton).toBeEnabled()
    await user.click(acceptButton)

    expect(acceptanceSubmitter).toHaveBeenCalledWith('a'.repeat(32))
    expect(await screen.findByText('Accepted lineup confirmed.')).toBeInTheDocument()
    expect(screen.getByText('The reviewed lineup is now the accepted local state.')).toBeInTheDocument()
  })

  it('keeps acceptance disabled when the proposal has an ambiguity blocker', async () => {
    const user = userEvent.setup()
    const blockedProposal = {
      ...readyProposal,
      Proposal: { ...readyProposal.Proposal, AmbiguityCount: 1, CanAccept: false, BlockingReasons: ['ambiguous-guide-match'] },
    }
    const submitter = vi.fn<GuidedSetupProposalSubmitter>().mockResolvedValue(blockedProposal)
    const acceptanceSubmitter = vi.fn<GuidedSetupAcceptanceSubmitter>()
    render(<GuidedSetupPage pickerAvailable={false} proposalSubmitter={submitter} acceptanceSubmitter={acceptanceSubmitter} />)

    await user.upload(screen.getByLabelText('Choose playlist'), new File(['#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one\n'], 'channels.m3u'))
    await user.click(screen.getByRole('button', { name: 'Analyze proposal' }))
    await user.click(screen.getByLabelText(/I reviewed these results/))

    expect(screen.getByText('Acceptance is blocked until the review blockers are resolved.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Accept reviewed proposal' })).toBeDisabled()
    expect(acceptanceSubmitter).not.toHaveBeenCalled()
  })

  it('keeps the proposal action disabled until the required playlist is selected', () => {
    const submitter = vi.fn<GuidedSetupProposalSubmitter>()
    render(<GuidedSetupPage pickerAvailable={false} proposalSubmitter={submitter} />)
    expect(screen.getByRole('button', { name: 'Analyze proposal' })).toBeDisabled()
  })
})
