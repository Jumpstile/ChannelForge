import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { WorkspaceIdentity } from '../components/WorkspaceIdentity'

 describe('workspace identity display', () => {
  it('shows the workspace name without internal identity tokens or filesystem paths', () => {
    render(<WorkspaceIdentity identity={{ label: 'Fixture workspace' }} />)

    expect(screen.getByLabelText('Workspace Fixture workspace')).toBeInTheDocument()
    expect(screen.queryByText(/^root-/)).not.toBeInTheDocument()
    expect(screen.queryByText(/^[A-Za-z]:\\/)).not.toBeInTheDocument()
    expect(screen.queryByText(/^\\\\/)).not.toBeInTheDocument()
  })
})
