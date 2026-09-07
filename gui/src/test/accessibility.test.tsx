import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import App from '../App'

describe('shell accessibility scaffolding', () => {
  it('provides landmark regions, a named workflow navigation, and a main heading', () => {
    render(<App />)

    expect(screen.getByRole('navigation', { name: 'Workflow pages' })).toBeInTheDocument()
    expect(screen.getByRole('main')).toBeInTheDocument()
    expect(screen.getByRole('contentinfo')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'Your lineup workbench' })).toBeInTheDocument()
  })
})
