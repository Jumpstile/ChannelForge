import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { WorkspaceIdentity } from '../components/WorkspaceIdentity'

 describe('workspace identity display', () => {
  it('shows a safe label and digest placeholder without a filesystem path', () => {
    render(<WorkspaceIdentity identity={{ label: 'Fixture workspace', digest: 'root-ab12…34ef' }} />)

    expect(screen.getByLabelText('Workspace Fixture workspace')).toBeInTheDocument()
    expect(screen.getByText('root-ab12…34ef')).toBeInTheDocument()
    expect(screen.queryByText(/^[A-Za-z]:\\/)).not.toBeInTheDocument()
    expect(screen.queryByText(/^\\\\/)).not.toBeInTheDocument()
  })
})
