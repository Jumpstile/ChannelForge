import { useId } from 'react'
import terms from '../app/terms.json'

export type Term = (typeof terms.terms)[number]

export function findTerm(id: string): Term | undefined {
  return terms.terms.find((term) => term.id === id)
}

export function TermCoach({ term }: { term: string }) {
  const helpId = useId()
  const entry = findTerm(term)
  if (!entry) return <span>{term}</span>
  return (
    <span className="term-coach">
      <button type="button" className="term-coach-trigger" aria-describedby={helpId}>{entry.label}</button>
      <span id={helpId} role="tooltip" className="term-coach-help">{entry.short}</span>
    </span>
  )
}
