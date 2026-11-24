import { FriendlyError, type FriendlyMessage } from './friendlyError'

export const proposalRequestLimits = {
  maxM3UBytes: 4 * 1024 * 1024,
  maxXMLTVBytes: 12 * 1024 * 1024,
} as const

export type GuidedSetupCheck = {
  Kind: 'logos' | 'categories' | 'guides'
  Status: 'ok' | 'attention' | 'unavailable'
  Headline: string
  Details: string[]
}

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
  explicitlyUnbound?: true
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
  Checks?: GuidedSetupCheck[]
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
type GuidedSetupProposalErrorPayload = { Error?: unknown }

const filesUnchanged = 'Your playlist and guide files were not changed.'

const guidedSetupProposalErrorMessages = {
  'unsupported-content-type': {
    headline: 'The check could not start',
    whatHappened: `The page and ChannelForge did not agree on how to send your files. ${filesUnchanged}`,
    whatToDo: 'Refresh this page, choose your files again, and press Analyze.',
    details: { cause: 'The analysis request used a content type the server does not accept.' },
  },
  'request-too-large': {
    headline: 'Your files are too big to check together',
    whatHappened: `All the files you chose add up to more than ChannelForge can check at one time. ${filesUnchanged}`,
    whatToDo: 'Remove some files, or use smaller ones, and press Analyze again.',
    details: { cause: 'The combined size of the analysis request is above the safe limit.' },
  },
  'file-too-large': {
    headline: 'One of your files is too big',
    whatHappened: `A file you chose is larger than ChannelForge can check safely. ${filesUnchanged}`,
    whatToDo: 'Choose a smaller file and press Analyze again.',
    details: { cause: 'A single source is above the per-file size limit.' },
  },
  'invalid-proposal-request': {
    headline: 'The check could not start',
    whatHappened: `ChannelForge did not accept the request the page sent. ${filesUnchanged}`,
    whatToDo: 'Choose your files again and press Analyze. If it keeps happening, run Update ChannelForge.cmd.',
    details: { cause: 'The server rejected the analysis request as malformed.' },
  },
  'missing-request-body': {
    headline: 'The check could not start',
    whatHappened: `ChannelForge received an empty request. ${filesUnchanged}`,
    whatToDo: 'Choose your files again and press Analyze.',
    details: { cause: 'The analysis request arrived with no body.' },
  },
  'request-length-mismatch': {
    headline: 'The check was interrupted',
    whatHappened: `Only part of your request reached ChannelForge. ${filesUnchanged}`,
    whatToDo: 'Press Analyze again. If it keeps happening, restart ChannelForge and try once more.',
    details: { cause: 'The size announced for the request did not match the data received.' },
  },
  'unsupported-source': {
    headline: 'That web address cannot be used',
    whatHappened: 'ChannelForge only accepts a file on this computer, or a public https:// address with no password, no ? part and no # part.',
    whatToDo: 'Choose a file, or paste a plain public https:// address, then press Analyze.',
    details: { cause: 'A source URL is not HTTPS, or contains credentials, a query string, or a fragment.' },
  },
  'package-data-unavailable': {
    headline: 'ChannelForge is missing some of its own files',
    whatHappened: `The installed program is missing files it needs to read your playlist. ${filesUnchanged}`,
    whatToDo: 'Run Update ChannelForge.cmd, or reinstall ChannelForge from the same package. Then press Analyze again.',
    details: { cause: 'Data files shipped with the program could not be found by the server, so the analysis could not run.' },
  },
  'source-unavailable': {
    headline: 'ChannelForge could not download a web address',
    whatHappened: `A playlist or guide web address did not answer. ${filesUnchanged}`,
    whatToDo: 'Check that the address is spelled right and that you are online, then press Analyze again.',
    details: { cause: 'A public HTTPS source could not be retrieved.' },
  },
  'invalid-playlist': {
    headline: 'A playlist is not in a format ChannelForge can read',
    whatHappened: `One of your playlists is not a valid M3U list. ${filesUnchanged}`,
    whatToDo: 'Choose a playlist file that ends in .m3u or .m3u8, then press Analyze again.',
    details: { cause: 'A selected playlist failed M3U validation.' },
  },
  'invalid-guide': {
    headline: 'A guide is not in a format ChannelForge can read',
    whatHappened: `One of your guides is not a valid XMLTV guide. ${filesUnchanged}`,
    whatToDo: 'Choose a guide file in XMLTV format (often .xml), or remove the guide, then press Analyze again.',
    details: { cause: 'A selected guide failed XMLTV validation.' },
  },
  'proposal-unavailable': {
    headline: 'ChannelForge could not check these files',
    whatHappened: `The check stopped before it finished. ${filesUnchanged}`,
    whatToDo: 'Make sure the files open in another program, then press Analyze again. If it keeps happening, open Details and share it when you ask for help.',
    details: { cause: 'The server reported an error this page does not recognize, or sent no readable error.' },
  },
} satisfies Record<string, FriendlyMessage>

function guidedSetupProposalError(payload: GuidedSetupProposalErrorPayload | null): FriendlyError {
  const code = payload?.Error
  if (typeof code === 'string' && Object.hasOwn(guidedSetupProposalErrorMessages, code)) {
    const known = guidedSetupProposalErrorMessages[code as keyof typeof guidedSetupProposalErrorMessages]
    return new FriendlyError({ ...known, details: { ...known.details, code } })
  }
  const unknown = guidedSetupProposalErrorMessages['proposal-unavailable']
  return new FriendlyError({ ...unknown, details: { ...unknown.details, code: typeof code === 'string' ? code.slice(0, 64) : undefined } })
}

function sourceProblem(headline: string, whatHappened: string, whatToDo: string, code: string, cause: string): FriendlyError {
  return new FriendlyError({ headline, whatHappened, whatToDo, details: { code, cause } })
}

function acceptanceFailed(serverMessage?: string): FriendlyError {
  return new FriendlyError({
    headline: 'ChannelForge could not accept this lineup',
    whatHappened: 'The accept step stopped before it finished. ChannelForge cannot tell from this answer whether anything was saved.',
    whatToDo: 'Refresh this page and look at your lineup before trying again. If it keeps happening, open Details and share it when you ask for help.',
    details: { code: 'acceptance-failed', cause: 'The server refused or could not finish accepting the reviewed proposal.', message: serverMessage || undefined },
  })
}

const responseNotRecognized = (what: 'analysis' | 'acceptance'): FriendlyError => sourceProblem(
  'ChannelForge answered in a way this page does not understand',
  what === 'analysis' ? filesUnchanged : 'ChannelForge may or may not have saved your lineup.',
  'Refresh this page and try again. If it keeps happening, run Update ChannelForge.cmd.',
  `${what}-response-not-recognized`,
  'The server reply did not have the expected version or fields. The page and the server may be from different ChannelForge versions.',
)


function bytesToBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunkSize = 0x8000
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize))
  }
  return btoa(binary)
}

const guideTooLarge = () => sourceProblem(
  'This guide is too big for the browser',
  `The guide is over 12 MB. ${filesUnchanged}`,
  'Use the desktop app or the command line for a guide this big. It is trimmed on your computer without uploading.',
  'guide-too-large-for-browser',
  'The guide file is above the 12 MB browser upload limit.',
)

async function readFileBase64(file: File, maximumBytes: number, tooLarge: () => FriendlyError = () => guidedSetupProposalError({ Error: 'file-too-large' })): Promise<string> {
  if (file.size === 0) throw sourceProblem('A file you chose is empty', filesUnchanged, 'Choose a file that has something in it, then press Analyze.', 'empty-file', 'The selected file is 0 bytes long.')
  if (file.size > maximumBytes) throw tooLarge()
  return bytesToBase64(new Uint8Array(await file.arrayBuffer()))
}

export async function submitGuidedSetupProposal(playlist: File, guide: File | null = null): Promise<GuidedSetupProposal> {
  const playlistBase64 = await readFileBase64(playlist, proposalRequestLimits.maxM3UBytes)
  const request: { schemaVersion: 1; m3u: { contentBase64: string }; xmltv?: { contentBase64: string } } = {
    schemaVersion: 1,
    m3u: { contentBase64: playlistBase64 },
  }
  if (guide) request.xmltv = { contentBase64: await readFileBase64(guide, proposalRequestLimits.maxXMLTVBytes, guideTooLarge) }

  const response = await fetch('/api/guided-setup/proposal', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  })
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupProposal> & GuidedSetupProposalErrorPayload | null
  if (!response.ok) throw guidedSetupProposalError(payload)
  if (
    payload?.Version !== 'guided-setup/proposal/v1' ||
    payload.Status !== 'PROPOSAL_READY' ||
    !payload.Proposal ||
    !payload.Safety ||
    typeof payload.Proposal.ProposalId !== 'string' ||
    typeof payload.Proposal.CanAccept !== 'boolean'
  ) {
    throw responseNotRecognized('analysis')
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
  if (!response.ok) throw acceptanceFailed(payload?.Message)
  if (payload?.Version !== 'guided-setup/acceptance/v1' || payload.Status !== 'ACCEPTED' || !payload.Proposal || !payload.Safety) {
    throw responseNotRecognized('acceptance')
  }
  return payload as GuidedSetupAcceptance
}

async function encodeSource(source: GuidedSetupSourceDraft, maximumBytes: number, tooLarge?: () => FriendlyError): Promise<{ contentBase64: string } | { url: string }> {
  if (source.file) return { contentBase64: await readFileBase64(source.file, maximumBytes, tooLarge) }
  const url = source.url?.trim() ?? ''
  if (!url) throw sourceProblem(`${source.label} has no file or web address`, filesUnchanged, 'Choose a file or paste a public https:// address for it, then press Analyze.', 'source-missing', `${source.label} has neither a file nor a URL.`)
  return { url }
}

export async function submitGuidedSetupSourceSetProposal(
  playlists: GuidedSetupSourceDraft[],
  guides: GuidedSetupSourceDraft[] = [],
  bindings: GuidedSetupBindingDraft[] = [],
): Promise<GuidedSetupSourceSetProposal> {
  if (playlists.length === 0) throw sourceProblem('Add a playlist first', filesUnchanged, 'Add at least one playlist, then press Analyze.', 'no-playlist', 'The analysis request contained no playlists.')
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
      ...(await encodeSource(source, proposalRequestLimits.maxXMLTVBytes, guideTooLarge)),
    }))),
    bindings: bindings.map((binding) => ({
      guideRef: binding.guideRef,
      playlistRefs: binding.playlistRefs,
      appliesToAll: binding.appliesToAll,
      ...(binding.explicitlyUnbound ? { explicitlyUnbound: true } : {}),
    })),
  }
  const response = await fetch('/api/guided-setup/proposal', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  })
  const payload = (await response.json().catch(() => null)) as Partial<GuidedSetupSourceSetProposal> & GuidedSetupProposalErrorPayload | null
  if (!response.ok) throw guidedSetupProposalError(payload)
  if (
    payload?.Version !== 'guided-setup/proposal/v2' ||
    payload.Status !== 'PROPOSAL_READY' ||
    !payload.Proposal ||
    !payload.Safety ||
    typeof payload.Proposal.ProposalId !== 'string' ||
    typeof payload.Proposal.CanAccept !== 'boolean'
  ) {
    throw responseNotRecognized('analysis')
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
  if (!response.ok) throw acceptanceFailed(payload?.Message)
  if (payload?.Version !== 'guided-setup/acceptance/v2' || payload.Status !== 'ACCEPTED' || !payload.Proposal || !payload.Safety) {
    throw responseNotRecognized('acceptance')
  }
  return payload as GuidedSetupSourceSetAcceptance
}
