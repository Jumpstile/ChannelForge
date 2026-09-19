import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { GuidedSetupPage } from '../pages/GuidedSetupPage'
import type { GuidedSetupProposalSubmitter } from '../app/guidedSetupProposal'

const readyProposal = {
  Version: 'guided-setup/proposal/v1' as const,
  Status: 'PROPOSAL_READY' as const,
  Proposal: {
    ChannelCount: 2,
    ExactGuideMatchCount: 1,
    AmbiguityCount: 0,
    UnmatchedPlaylistCount: 1,
    GuideOnlyCount: 0,
    GuideStatus: 'XMLTV_SELECTED' as const,
    CandidateManifestHash: 'a'.repeat(64),
    BuildIdentity: 'b'.repeat(64),
  },
  Warnings: [{ Code: 'unmatched-playlist-entry', Message: 'Some playlist entries have no exact guide match.' }],
  Safety: {
    PublicationState: 'CandidateOnly' as const,
    AcceptedStateMutation: 'none' as const,
    ProviderMutation: 'none' as const,
    DownstreamMutation: 'none' as const,
    GuidePublication: 'none' as const,
    CanPublish: false as const,
  },
}

describe('browser Guided Setup proposal', () => {
  it('sends one playlist and an optional guide to the candidate-only submitter', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupProposalSubmitter>().mockResolvedValue(readyProposal)
    render(<GuidedSetupPage pickerAvailable={false} proposalSubmitter={submitter} />)

    const playlist = new File(['#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one\n'], 'channels.m3u', { type: 'audio/x-mpegurl' })
    const guide = new File(['<?xml version="1.0"?><tv></tv>'], 'guide.xml', { type: 'application/xml' })
    await user.upload(screen.getByLabelText('Choose playlist'), playlist)
    await user.upload(screen.getByLabelText('Choose guide (optional)'), guide)
    await user.click(screen.getByRole('button', { name: 'Analyze proposal' }))

    expect(submitter).toHaveBeenCalledWith(playlist, guide)
    expect(await screen.findByText('Candidate proposal ready. Nothing was published.')).toBeInTheDocument()
    expect(screen.getByText('Some playlist entries have no exact guide match.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /accept|publish/i })).not.toBeInTheDocument()
  })

  it('keeps the proposal action disabled until the required playlist is selected', () => {
    const submitter = vi.fn<GuidedSetupProposalSubmitter>()
    render(<GuidedSetupPage pickerAvailable={false} proposalSubmitter={submitter} />)
    expect(screen.getByRole('button', { name: 'Analyze proposal' })).toBeDisabled()
  })
})
