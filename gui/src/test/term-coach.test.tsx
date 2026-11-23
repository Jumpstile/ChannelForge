import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import terms from '../app/terms.json'
import schema from '../app/terms.schema.json'
import { TermCoach } from '../components/TermCoach'

describe('terms registry', () => {
  it('has unique ids, all required fields, and confused-with ids that exist', () => {
    const required = schema.properties.terms.items.required
    const ids = terms.terms.map((term) => term.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const term of terms.terms) {
      for (const key of required) expect(term).toHaveProperty(key)
      for (const other of term.confusedWith) expect(ids).toContain(other)
    }
  })
})

describe('TermCoach', () => {
  it('shows the registry definition to keyboard and screen reader users', async () => {
    render(<TermCoach term="xmltv-guide" />)
    const trigger = screen.getByRole('button', { name: 'XMLTV guide' })
    await userEvent.tab()
    expect(trigger).toHaveFocus()
    const help = document.getElementById(trigger.getAttribute('aria-describedby') ?? '')
    expect(help).toHaveTextContent(/schedule data/i)
  })
})
