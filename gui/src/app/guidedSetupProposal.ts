export const proposalRequestLimits = {
  maxM3UBytes: 4 * 1024 * 1024,
  maxXMLTVBytes: 12 * 1024 * 1024,
} as const

export type GuidedSetupProposal = {
  Version: 'guided-setup/proposal/v1'
  Status: 'PROPOSAL_READY'
  Proposal: {
    ChannelCount: number
    ExactGuideMatchCount: number
    AmbiguityCount: number
    UnmatchedPlaylistCount: number
    GuideOnlyCount: number
    GuideStatus: 'NO_GUIDE_SELECTED' | 'XMLTV_SELECTED'
    CandidateManifestHash: string
    BuildIdentity: string
  }
  Warnings: Array<{ Code: string; Message: string }>
  Safety: {
    PublicationState: 'CandidateOnly'
    AcceptedStateMutation: 'none'
    ProviderMutation: 'none'
    DownstreamMutation: 'none'
    GuidePublication: 'none'
    CanPublish: false
  }
}

export type GuidedSetupProposalSubmitter = (playlist: File, guide?: File | null) => Promise<GuidedSetupProposal>

function bytesToBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunkSize = 0x8000
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize))
  }
  return btoa(binary)
}

async function readFileBase64(file: File, maximumBytes: number): Promise<string> {
  if (file.size === 0) throw new Error('Choose a non-empty file.')
  if (file.size > maximumBytes) throw new Error('The selected file is too large to analyze safely.')
  return bytesToBase64(new Uint8Array(await file.arrayBuffer()))
}

export async function submitGuidedSetupProposal(playlist: File, guide: File | null = null): Promise<GuidedSetupProposal> {
  const playlistBase64 = await readFileBase64(playlist, proposalRequestLimits.maxM3UBytes)
  const request: { schemaVersion: 1; m3u: { contentBase64: string }; xmltv?: { contentBase64: string } } = {
    schemaVersion: 1,
    m3u: { contentBase64: playlistBase64 },
  }
  if (guide) request.xmltv = { contentBase64: await readFileBase64(guide, proposalRequestLimits.maxXMLTVBytes) }

  const response = await fetch('/api/guided-setup/proposal', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  })
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupProposal> & { Message?: string } | null
  if (!response.ok) throw new Error(payload?.Message || 'The playlist or guide could not be analyzed safely.')
  if (payload?.Version !== 'guided-setup/proposal/v1' || payload.Status !== 'PROPOSAL_READY' || !payload.Proposal || !payload.Safety) {
    throw new Error('The proposal response was not recognized.')
  }
  return payload as GuidedSetupProposal
}
