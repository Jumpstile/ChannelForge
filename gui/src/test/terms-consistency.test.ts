/// <reference types="node" />
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import terms from '../app/terms.json'

const readDoc = (name: string) => readFileSync(`../docs/user/Concepts/${name}`, 'utf8') // tests run from gui/
const channelIds = readDoc('Channel-IDs.md')
const providers = readDoc('Providers.md')
const sources = readDoc('Sources.md')
const xmltv = readDoc('XMLTV.md')

const pageSources = import.meta.glob(['../App.tsx', '../pages/*.tsx', '../components/*.tsx'], { query: '?raw', import: 'default', eager: true }) as Record<string, string>

describe('terms consistency', () => {
  it('defines every term used by a TermCoach in the UI', () => {
    const ids = new Set(terms.terms.map((term) => term.id))
    const used = Object.values(pageSources).flatMap((text) => [...text.matchAll(/<TermCoach\s+term="([^"]+)"/g)].map((match) => match[1]))
    for (const id of used) expect(ids, `TermCoach uses unknown term "${id}"`).toContain(id)
  })

  it('uses the same words as the user docs for a checked list of terms', () => {
    const checked: Array<[string, string, string]> = [
      ['xmltv-guide', 'XMLTV', xmltv],
      ['provider', 'provider', providers],
      ['source', 'source', sources],
      ['channel-id', 'channel id', channelIds],
    ]
    for (const [id, word, doc] of checked) {
      const term = terms.terms.find((entry) => entry.id === id)
      expect(term, `missing term ${id}`).toBeDefined()
      expect(`${term!.label} ${term!.short}`.toLowerCase()).toContain(word.toLowerCase())
      expect(doc.toLowerCase()).toContain(word.toLowerCase())
    }
  })
})
