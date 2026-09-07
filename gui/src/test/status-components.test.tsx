import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { StateCard } from '../components/StateCard'
import { stateGalleryFixtures } from '../fixtures/state-gallery'

 describe('status components', () => {
  it('renders every deterministic gallery state with a visible label and next action', () => {
    render(
      <div>
        {stateGalleryFixtures.map((state) => <StateCard key={state.id} state={state} />)}
      </div>,
    )

    expect(screen.getAllByText(/next safe action/i)).toHaveLength(stateGalleryFixtures.length)
    for (const state of stateGalleryFixtures) {
      expect(screen.getByText(state.status)).toBeInTheDocument()
      expect(screen.getByText(state.title)).toBeInTheDocument()
      expect(screen.getByText(state.nextAction)).toBeInTheDocument()
    }
  })
})
