import { useState } from 'react'
import { PageHeader } from '../components/PageHeader'
import { findTerm } from '../components/TermCoach'
import terms from '../app/terms.json'

export function GlossaryPage() {
  const [query, setQuery] = useState('')
  const needle = query.trim().toLowerCase()
  const matches = terms.terms.filter((term) => `${term.label} ${term.short} ${term.longer}`.toLowerCase().includes(needle))

  return (
    <div className="page-stack">
      <PageHeader eyebrow="Help" title="Learn the terms" description="Plain-language meanings for the words ChannelForge uses." />
      <label className="glossary-search">
        <span>Search terms</span>
        <input type="search" value={query} onChange={(event) => setQuery(event.target.value)} />
      </label>
      <p role="status" aria-live="polite">{matches.length} of {terms.terms.length} terms</p>
      <dl className="glossary-list">
        {matches.map((term) => (
          <div key={term.id} id={`term-${term.id}`}>
            <dt>{term.label}</dt>
            <dd>{term.short} {term.longer}</dd>
            {term.confusedWith.length > 0 && (
              <dd>Not the same as: {term.confusedWith.map((id) => findTerm(id)?.label ?? id).join(', ')}</dd>
            )}
          </div>
        ))}
      </dl>
    </div>
  )
}
