import { afterEach, describe, expect, it, vi } from 'vitest'
import { submitGuidedSetupSourceSetProposal } from '../app/guidedSetupProposal'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('browser Guided Setup proposal errors', () => {
  it.each([
    ['package-data-unavailable', 'ChannelForge is missing required analysis data. Repair or reinstall the application, then analyze again.'],
    ['invalid-playlist', 'A selected playlist is not valid M3U. Choose a valid M3U or M3U8 file, then analyze again.'],
    ['invalid-guide', 'A selected guide is not valid XMLTV. Choose a valid XMLTV file, then analyze again.'],
    ['unsupported-source', 'Use a local source file or a public HTTPS URL without credentials, query parameters, or fragments.'],
    ['source-unavailable', 'A public HTTPS source could not be retrieved. Check its URL and connection, then try again.'],
  ])('maps %s to bounded actionable copy', async (code, message) => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      Error: code,
      Message: 'C:\\private\\provider.local.json?token=secret',
    }), { status: 422, headers: { 'Content-Type': 'application/json' } })))

    await expect(submitGuidedSetupSourceSetProposal([
      { sourceKey: 'playlist-1', label: 'Playlist 1', url: 'https://example.invalid/channels.m3u' },
    ])).rejects.toThrow(message)
  })

  it('hides an unknown server error message instead of rendering raw details', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      Error: 'unexpected-internal-error',
      Message: 'C:\\private\\provider.local.json?token=secret',
    }), { status: 500, headers: { 'Content-Type': 'application/json' } })))

    const sources = [{ sourceKey: 'playlist-1', label: 'Playlist 1', url: 'https://example.invalid/channels.m3u' }]
    await expect(submitGuidedSetupSourceSetProposal(sources)).rejects.toThrow('ChannelForge could not safely analyze these sources. Check the selected files or retry later.')
    await expect(submitGuidedSetupSourceSetProposal(sources)).rejects.not.toThrow('C:\\private')
  })
})
