import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { GuidedSetupPage } from '../pages/GuidedSetupPage'
import type { GuidedSetupSourceSetAcceptance, GuidedSetupSourceSetProposal, GuidedSetupSourceSetSubmitter } from '../app/guidedSetupProposal'

const readyProposal: GuidedSetupSourceSetProposal = {
  Version: 'guided-setup/proposal/v2',
  Status: 'PROPOSAL_READY',
  Proposal: {
    ProposalId: 'a'.repeat(32),
    PlaylistCount: 2,
    GuideCount: 1,
    BoundGuideCount: 1,
    UnboundGuideCount: 0,
    ChannelCount: 2,
    ExactGuideMatchCount: 1,
    AmbiguityCount: 0,
    UnmatchedPlaylistCount: 1,
    GuideOnlyCount: 0,
    GuideStatus: 'XMLTV_SELECTED',
    CanAccept: true,
    BlockingReasons: [],
  },
  Warnings: [{ Code: 'unmatched-playlist-entry', Message: 'Some playlist entries have no exact guide match.' }],
  Safety: {
    PublicationState: 'CandidateOnly',
    AcceptedStateMutation: 'none',
    ProviderMutation: 'none',
    DownstreamMutation: 'none',
    GuidePublication: 'none',
    CanPublish: false,
    CanAccept: true,
  },
}

const accepted: GuidedSetupSourceSetAcceptance = {
  Version: 'guided-setup/acceptance/v2',
  Status: 'ACCEPTED',
  EnrollmentStatus: 'SAVED',
  Message: 'Sources saved for restart-safe refresh.',
  Proposal: { ChannelCount: 2, GuideStatus: 'XMLTV_ACCEPTED' },
  Safety: {
    AcceptedStateMutation: 'accepted-lineup',
    ProviderMutation: 'none',
    DownstreamMutation: 'none',
    SchedulerMutation: 'none',
  },
}

describe('browser Guided Setup proposal and acceptance', () => {
  it('reviews multiple browser sources, submits explicit guide bindings, and accepts only after acknowledgement', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupSourceSetSubmitter>().mockResolvedValue(readyProposal)
    const acceptanceSubmitter = vi.fn<(proposalId: string) => Promise<GuidedSetupSourceSetAcceptance>>().mockResolvedValue(accepted)
    render(<GuidedSetupPage pickerAvailable={false} sourceSetProposalSubmitter={submitter} sourceSetAcceptanceSubmitter={acceptanceSubmitter} />)

    const playlist = new File(['#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one\n'], 'channels.m3u', { type: 'audio/x-mpegurl' })
    const secondPlaylist = new File(['#EXTM3U\n#EXTINF:-1,Two\nhttps://example.invalid/two\n'], 'channels-two.m3u', { type: 'audio/x-mpegurl' })
    const guide = new File(['<?xml version="1.0"?><tv></tv>'], 'guide.xml', { type: 'application/xml' })
    const playlistInputs = screen.getAllByLabelText('Choose playlist')
    await user.upload(playlistInputs[0], playlist)
    await user.click(screen.getByRole('button', { name: 'Add another playlist' }))
    await user.upload(screen.getAllByLabelText('Choose playlist')[1], secondPlaylist)
    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    await user.upload(screen.getByLabelText('Choose guide'), guide)
    await user.click(screen.getByLabelText('All playlists'))
    expect(screen.getByText('Selected for all playlists. This guide will be applied to every playlist only after you accept the reviewed proposal.')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Analyze source set' }))

    expect(submitter).toHaveBeenCalledTimes(1)
    expect(submitter.mock.calls[0][0]).toEqual(expect.arrayContaining([
      expect.objectContaining({ sourceKey: 'playlist-1', file: playlist }),
      expect.objectContaining({ file: secondPlaylist }),
    ]))
    expect(submitter.mock.calls[0][1]).toEqual([expect.objectContaining({ file: guide })])
    expect(submitter.mock.calls[0][2]).toEqual([{ guideRef: expect.any(String), playlistRefs: [], appliesToAll: true }])
    expect(await screen.findByText('Review ready. Nothing has been accepted yet.')).toBeInTheDocument()
    expect(screen.getByText('Unmatched playlists').parentElement).toHaveTextContent(/Unmatched playlists\s*1/)
    expect(screen.getByText('Some playlist entries have no exact guide match.')).toBeInTheDocument()
    expect(screen.queryByText('a'.repeat(64))).not.toBeInTheDocument()
    const acceptButton = screen.getByRole('button', { name: 'Accept reviewed proposal' })
    expect(acceptButton).toBeDisabled()

    await user.click(screen.getByLabelText(/I reviewed these results/))
    expect(acceptButton).toBeEnabled()
    await user.click(acceptButton)

    expect(acceptanceSubmitter).toHaveBeenCalledWith('a'.repeat(32))
    expect(await screen.findByText('Accepted lineup confirmed.')).toBeInTheDocument()
    expect(screen.getByText('The reviewed source set is now the accepted local state.')).toBeInTheDocument()
  })

  it('keeps acceptance disabled when the proposal has an ambiguity blocker', async () => {
    const user = userEvent.setup()
    const blockedProposal = {
      ...readyProposal,
      Proposal: { ...readyProposal.Proposal, AmbiguityCount: 1, CanAccept: false, BlockingReasons: ['ambiguous-guide-match'] },
    }
    const submitter = vi.fn<GuidedSetupSourceSetSubmitter>().mockResolvedValue(blockedProposal)
    const acceptanceSubmitter = vi.fn<(proposalId: string) => Promise<GuidedSetupSourceSetAcceptance>>()
    render(<GuidedSetupPage pickerAvailable={false} sourceSetProposalSubmitter={submitter} sourceSetAcceptanceSubmitter={acceptanceSubmitter} />)

    await user.upload(screen.getByLabelText('Choose playlist'), new File(['#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one\n'], 'channels.m3u'))
    await user.click(screen.getByRole('button', { name: 'Analyze source set' }))
    await user.click(screen.getByLabelText(/I reviewed these results/))

    expect(screen.getByText('Acceptance is blocked until the review blockers are resolved.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Accept reviewed proposal' })).toBeDisabled()
    expect(acceptanceSubmitter).not.toHaveBeenCalled()
  })

  it('requires a playlist file or URL before analysis', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupSourceSetSubmitter>()
    render(<GuidedSetupPage pickerAvailable={false} sourceSetProposalSubmitter={submitter} />)
    await user.click(screen.getByRole('button', { name: 'Analyze source set' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Complete every playlist with a local file or public HTTPS URL.')
    expect(submitter).not.toHaveBeenCalled()
  })
  it('shows the configured playlist count and focuses an actionable analysis failure', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupSourceSetSubmitter>().mockRejectedValue(new Error('A selected playlist is not valid M3U. Choose a valid M3U or M3U8 file, then analyze again.'))
    render(<GuidedSetupPage pickerAvailable={false} sourceSetProposalSubmitter={submitter} />)

    expect(screen.getByRole('heading', { name: 'Workspace ready' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Choose workspace' })).not.toBeInTheDocument()
    expect(screen.getByText('Add at least one playlist to analyze.')).toBeInTheDocument()
    await user.upload(screen.getByLabelText('Choose playlist'), new File(['#EXTM3U\n'], 'one.m3u'))
    expect(screen.getByText('Ready to analyze 1 playlist.')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Add another playlist' }))
    await user.upload(screen.getAllByLabelText('Choose playlist')[1], new File(['#EXTM3U\n'], 'two.m3u'))
    expect(screen.getByText('Ready to analyze 2 playlists.')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Analyze source set' }))

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('A selected playlist is not valid M3U.')
    expect(alert).toHaveFocus()
    expect(screen.getByText('Analysis stopped; 2 playlists remain selected.')).toBeInTheDocument()
    expect(screen.getByText('one.m3u')).toBeInTheDocument()
    expect(screen.getByText('two.m3u')).toBeInTheDocument()
  })

  it('defaults one guide to the sole playlist and preserves an explicit unbind across analysis', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupSourceSetSubmitter>().mockResolvedValue(readyProposal)
    render(<GuidedSetupPage pickerAvailable={false} sourceSetProposalSubmitter={submitter} />)

    await user.upload(screen.getByLabelText('Choose playlist'), new File(['#EXTM3U\n#EXTINF:-1,One\nhttps://example.invalid/one\n'], 'one.m3u'))
    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    await user.upload(screen.getByLabelText('Choose guide'), new File(['<tv></tv>'], 'guide.xml'))
    expect(screen.getByRole('checkbox', { name: 'Playlist 1' })).toBeChecked()
    expect(screen.getByText(/Selected for 1 playlist/)).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Analyze source set' }))
    await screen.findByText('Review ready. Nothing has been accepted yet.')
    expect(submitter.mock.calls[0][2]).toEqual([
      expect.objectContaining({ playlistRefs: ['playlist-1'], appliesToAll: false }),
    ])

    await user.click(screen.getByRole('checkbox', { name: 'Playlist 1' }))
    expect(screen.getByText(/Explicitly unbound/)).toBeInTheDocument()
    for (let index = 1; index <= 2; index += 1) {
      await user.click(screen.getByRole('button', { name: 'Analyze source set' }))
      await screen.findByText('Review ready. Nothing has been accepted yet.')
      expect(submitter.mock.calls[index][2]).toEqual([
        expect.objectContaining({ playlistRefs: [], appliesToAll: false, explicitlyUnbound: true }),
      ])
    }
  })

  it('sends multiple selected playlists as an explicit non-ALL guide binding', async () => {
    const user = userEvent.setup()
    const submitter = vi.fn<GuidedSetupSourceSetSubmitter>().mockResolvedValue(readyProposal)
    render(<GuidedSetupPage pickerAvailable={false} sourceSetProposalSubmitter={submitter} />)

    await user.upload(screen.getByLabelText('Choose playlist'), new File(['#EXTM3U\n'], 'one.m3u'))
    await user.click(screen.getByRole('button', { name: 'Add another playlist' }))
    await user.upload(screen.getAllByLabelText('Choose playlist')[1], new File(['#EXTM3U\n'], 'two.m3u'))
    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    await user.upload(screen.getByLabelText('Choose guide'), new File(['<tv></tv>'], 'guide.xml'))
    await user.click(screen.getByRole('checkbox', { name: 'Playlist 1' }))
    await user.click(screen.getByRole('checkbox', { name: 'Playlist 2' }))

    expect(screen.getByText(/Selected for 2 playlists/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Analyze source set' }))
    await screen.findByText('Review ready. Nothing has been accepted yet.')
    expect(submitter.mock.calls[0][2]).toEqual([
      expect.objectContaining({ playlistRefs: ['playlist-1', expect.stringMatching(/^playlist-2-/)], appliesToAll: false }),
    ])
  })
})
