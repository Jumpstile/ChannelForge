export const proposalRequestLimits = {
  maxM3UBytes: 4 * 1024 * 1024,
  maxXMLTVBytes: 12 * 1024 * 1024,
} as const

export type GuidedSetupProposal = {
  Version: 'guided-setup/proposal/v1'
  Status: 'PROPOSAL_READY'
  Proposal: {
    ProposalId: string
    ChannelCount: number
    ExactGuideMatchCount: number
    AmbiguityCount: number
    UnmatchedPlaylistCount: number
    GuideOnlyCount: number
    GuideStatus: 'NO_GUIDE_SELECTED' | 'XMLTV_SELECTED'
    CanAccept: boolean
    BlockingReasons: string[]
  }
  Warnings: Array<{ Code: string; Message: string }>
  Safety: {
    PublicationState: 'CandidateOnly'
    AcceptedStateMutation: 'none'
    ProviderMutation: 'none'
    DownstreamMutation: 'none'
    GuidePublication: 'none'
    CanPublish: false
    CanAccept: boolean
  }
}

export type GuidedSetupAcceptance = {
  Version: 'guided-setup/acceptance/v1'
  Status: 'ACCEPTED'
  Proposal: {
    ChannelCount: number
    GuideStatus: 'NO_GUIDE_SELECTED' | 'XMLTV_ACCEPTED'
  }
  Safety: {
    AcceptedStateMutation: 'accepted-lineup'
    ProviderMutation: 'none'
    DownstreamMutation: 'none'
    SchedulerMutation: 'none'
  }
}

export type GuidedSetupProposalSubmitter = (playlist: File, guide?: File | null) => Promise<GuidedSetupProposal>
export type GuidedSetupSourceDraft = {
  sourceKey: string
  label: string
  priority?: number
  file?: File | null
  url?: string
}

export type GuidedSetupBindingDraft = {
  guideRef: string
  playlistRefs: string[]
  appliesToAll: boolean
}

export type GuidedSetupSourceSetProposal = {
  Version: 'guided-setup/proposal/v2'
  Status: 'PROPOSAL_READY'
  Proposal: {
    ProposalId: string
    PlaylistCount: number
    GuideCount: number
    BoundGuideCount: number
    UnboundGuideCount: number
    ChannelCount: number
    ExactGuideMatchCount: number
    AmbiguityCount: number
    UnmatchedPlaylistCount: number
    GuideOnlyCount: number
    GuideStatus: 'NO_GUIDE_SELECTED' | 'XMLTV_SELECTED' | 'XMLTV_UNBOUND_ACTIONABLE'
    CanAccept: boolean
    BlockingReasons: string[]
  }
  Warnings: Array<{ Code: string; Message: string }>
  Safety: {
    PublicationState: 'CandidateOnly'
    AcceptedStateMutation: 'none'
    ProviderMutation: 'none'
    DownstreamMutation: 'none'
    GuidePublication: 'none'
    CanPublish: false
    CanAccept: boolean
  }
}

export type GuidedSetupSourceSetAcceptance = {
  Version: 'guided-setup/acceptance/v2'
  Status: 'ACCEPTED'
  EnrollmentStatus: 'SAVED' | string
  Message: string
  Proposal: {
    ChannelCount: number
    GuideStatus: 'NO_GUIDE_SELECTED' | 'XMLTV_ACCEPTED' | 'XMLTV_ACCEPTED_WITH_UNBOUND'
  }
  Safety: {
    AcceptedStateMutation: 'accepted-lineup'
    ProviderMutation: 'none'
    DownstreamMutation: 'none'
    SchedulerMutation: 'none'
  }
}

export type GuidedSetupSourceSetSubmitter = (
  playlists: GuidedSetupSourceDraft[],
  guides: GuidedSetupSourceDraft[],
  bindings: GuidedSetupBindingDraft[],
) => Promise<GuidedSetupSourceSetProposal>

export type GuidedSetupAcceptanceSubmitter = (proposalId: string) => Promise<GuidedSetupAcceptance>
type GuidedSetupProposalErrorCode =
  | 'unsupported-content-type'
  | 'request-too-large'
  | 'file-too-large'
  | 'invalid-proposal-request'
  | 'missing-request-body'
  | 'request-length-mismatch'
  | 'unsupported-source'
  | 'package-data-unavailable'
  | 'source-unavailable'
  | 'invalid-playlist'
  | 'invalid-guide'
  | 'proposal-unavailable'

type GuidedSetupProposalErrorPayload = { Error?: unknown }

const guidedSetupProposalErrorMessages: Record<GuidedSetupProposalErrorCode, string> = {
  'unsupported-content-type': 'The analysis request used an unsupported format. Refresh Guided Setup and try again.',
  'request-too-large': 'The selected source set exceeds the safe analysis size limit. Reduce the file sizes and try again.',
  'file-too-large': 'A selected source exceeds the safe analysis size limit. Choose a smaller file and try again.',
  'invalid-proposal-request': 'The analysis request was not accepted. Choose the sources again and retry.',
  'missing-request-body': 'The analysis request was empty. Choose the sources again and retry.',
  'request-length-mismatch': 'The analysis request was incomplete. Choose the sources again and retry.',
  'unsupported-source': 'Use a local source file or a public HTTPS URL without credentials, query parameters, or fragments.',
  'package-data-unavailable': 'ChannelForge is missing required analysis data. Repair or reinstall the application, then analyze again.',
  'source-unavailable': 'A public HTTPS source could not be retrieved. Check its URL and connection, then try again.',
  'invalid-playlist': 'A selected playlist is not valid M3U. Choose a valid M3U or M3U8 file, then analyze again.',
  'invalid-guide': 'A selected guide is not valid XMLTV. Choose a valid XMLTV file, then analyze again.',
  'proposal-unavailable': 'ChannelForge could not safely analyze these sources. Check the selected files or retry later.',
}

function guidedSetupProposalErrorMessage(payload: GuidedSetupProposalErrorPayload | null): string {
  const code = payload?.Error
  return typeof code === 'string' && Object.hasOwn(guidedSetupProposalErrorMessages, code)
    ? guidedSetupProposalErrorMessages[code as GuidedSetupProposalErrorCode]
    : guidedSetupProposalErrorMessages['proposal-unavailable']
}


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
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupProposal> & GuidedSetupProposalErrorPayload | null
  if (!response.ok) throw new Error(guidedSetupProposalErrorMessage(payload))
  if (
    payload?.Version !== 'guided-setup/proposal/v1' ||
    payload.Status !== 'PROPOSAL_READY' ||
    !payload.Proposal ||
    !payload.Safety ||
    typeof payload.Proposal.ProposalId !== 'string' ||
    typeof payload.Proposal.CanAccept !== 'boolean'
  ) {
    throw new Error('The proposal response was not recognized.')
  }
  return payload as GuidedSetupProposal
}

export async function acceptGuidedSetupProposal(proposalId: string): Promise<GuidedSetupAcceptance> {
  const response = await fetch('/api/guided-setup/accept', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({ schemaVersion: 1, proposalId, acknowledged: true }),
  })
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupAcceptance> & { Message?: string } | null
  if (!response.ok) throw new Error(payload?.Message || 'The reviewed proposal could not be accepted safely.')
  if (payload?.Version !== 'guided-setup/acceptance/v1' || payload.Status !== 'ACCEPTED' || !payload.Proposal || !payload.Safety) {
    throw new Error('The acceptance response was not recognized.')
  }
  return payload as GuidedSetupAcceptance
}

async function encodeSource(source: GuidedSetupSourceDraft, maximumBytes: number): Promise<{ contentBase64: string } | { url: string }> {
  if (source.file) return { contentBase64: await readFileBase64(source.file, maximumBytes) }
  const url = source.url?.trim() ?? ''
  if (!url) throw new Error(`Add a file or HTTPS URL for ${source.label}.`)
  return { url }
}

export async function submitGuidedSetupSourceSetProposal(
  playlists: GuidedSetupSourceDraft[],
  guides: GuidedSetupSourceDraft[] = [],
  bindings: GuidedSetupBindingDraft[] = [],
): Promise<GuidedSetupSourceSetProposal> {
  if (playlists.length === 0) throw new Error('Add at least one playlist before analyzing the proposal.')
  const request = {
    schemaVersion: 2 as const,
    playlists: await Promise.all(playlists.map(async (source, index) => ({
      sourceKey: source.sourceKey,
      label: source.label,
      priority: source.priority ?? index + 1,
      ...(await encodeSource(source, proposalRequestLimits.maxM3UBytes)),
    }))),
    guides: await Promise.all(guides.map(async (source, index) => ({
      sourceKey: source.sourceKey,
      label: source.label,
      priority: source.priority ?? index + 1,
      ...(await encodeSource(source, proposalRequestLimits.maxXMLTVBytes)),
    }))),
    bindings: bindings.map((binding) => ({
      guideRef: binding.guideRef,
      playlistRefs: binding.playlistRefs,
      appliesToAll: binding.appliesToAll,
    })),
  }
  const response = await fetch('/api/guided-setup/proposal', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  })
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupSourceSetProposal> & GuidedSetupProposalErrorPayload | null
  if (!response.ok) throw new Error(guidedSetupProposalErrorMessage(payload))
  if (
    payload?.Version !== 'guided-setup/proposal/v2' ||
    payload.Status !== 'PROPOSAL_READY' ||
    !payload.Proposal ||
    !payload.Safety ||
    typeof payload.Proposal.ProposalId !== 'string' ||
    typeof payload.Proposal.CanAccept !== 'boolean'
  ) {
    throw new Error('The proposal response was not recognized.')
  }
  return payload as GuidedSetupSourceSetProposal
}

export async function acceptGuidedSetupSourceSetProposal(proposalId: string): Promise<GuidedSetupSourceSetAcceptance> {
  const response = await fetch('/api/guided-setup/accept', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({ schemaVersion: 2, proposalId, acknowledged: true }),
  })
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupSourceSetAcceptance> & { Message?: string } | null
  if (!response.ok) throw new Error(payload?.Message || 'The reviewed proposal could not be accepted safely.')
  if (payload?.Version !== 'guided-setup/acceptance/v2' || payload.Status !== 'ACCEPTED' || !payload.Proposal || !payload.Safety) {
    throw new Error('The acceptance response was not recognized.')
  }
  return payload as GuidedSetupSourceSetAcceptance
}
