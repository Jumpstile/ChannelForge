import { afterEach, describe, expect, it, vi } from 'vitest'
import { FriendlyError } from '../app/friendlyError'
import { submitGuidedSetupSourceSetProposal } from '../app/guidedSetupProposal'

afterEach(() => {
  vi.unstubAllGlobals()
})

const sources = [{ sourceKey: 'playlist-1', label: 'Playlist 1', url: 'https://example.invalid/channels.m3u' }]

describe('browser Guided Setup proposal errors', () => {
  it.each([
    ['package-data-unavailable', 'The installed program is missing files it needs to read your playlist. Your playlist and guide files were not changed.', 'Update ChannelForge.cmd'],
    ['invalid-playlist', 'One of your playlist files does not look like a channel playlist.', 'different playlist file'],
    ['invalid-guide', 'One of your guide files does not look like a TV guide.', 'different guide file'],
    ['unsupported-source', 'ChannelForge only accepts a file on this computer', 'https://'],
    ['source-unavailable', 'A playlist or guide web address did not answer.', 'online'],
  ])('shows plain words first and keeps the code in Details for %s', async (code, whatHappened, whatToDo) => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      Error: code,
      Message: 'C:\\private\\provider.local.json?token=secret',
    }), { status: 422, headers: { 'Content-Type': 'application/json' } })))

    const error = await submitGuidedSetupSourceSetProposal(sources).catch((caught: unknown) => caught)
    if (!(error instanceof FriendlyError)) throw error
    const { friendly } = error
    expect(friendly.whatHappened).toContain(whatHappened)
    expect(friendly.whatToDo).toContain(whatToDo)
    expect(friendly.details.code).toBe(code)
    expect(JSON.stringify(friendly)).not.toContain('C:\\private')
  })

  it('hides an unknown server error message instead of rendering raw details', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      Error: 'unexpected-internal-error',
      Message: 'C:\\private\\provider.local.json?token=secret',
    }), { status: 500, headers: { 'Content-Type': 'application/json' } })))

    const error = await submitGuidedSetupSourceSetProposal(sources).catch((caught: unknown) => caught)
    if (!(error instanceof FriendlyError)) throw error
    expect(error.friendly).toMatchObject({ headline: 'ChannelForge could not check these files', details: { code: 'unexpected-internal-error' } })
    expect(JSON.stringify(error.friendly)).not.toContain('C:\\private')
  })
})
