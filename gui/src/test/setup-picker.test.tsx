import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { GuidedSetupPage } from '../pages/GuidedSetupPage'
import type { SetupPicker, SetupSelectionKind, SetupSelectionResult } from '../app/setupSelection'

function selectedResult(kind: SetupSelectionKind): SetupSelectionResult {
  return {
    kind,
    outcome: 'selected',
    selectionStatus: 'selected',
    validationStatus: 'not-checked',
    errorCode: null,
  }
}

function cancelledResult(kind: SetupSelectionKind): SetupSelectionResult {
  return {
    kind,
    outcome: 'cancelled',
    selectionStatus: 'not-selected',
    validationStatus: 'not-checked',
    errorCode: null,
  }
}

describe('native picker bridge flow', () => {
  it('enables setup items sequentially and keeps validation unchecked', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>(async (kind) => selectedResult(kind))
    render(<GuidedSetupPage picker={picker} pickerAvailable />)
    expect(screen.getByRole('heading', { name: 'Selection available' })).toBeInTheDocument()
    expect(screen.getByText('Native selection is connected. Files are not read, parsed, or validated yet.')).toBeInTheDocument()
    expect(screen.getAllByText('Selection enabled')).toHaveLength(3)

    expect(screen.getByRole('button', { name: 'Choose workspace' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeDisabled()

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('Workspace selected.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeEnabled()

    await user.click(screen.getByRole('button', { name: 'Add playlist' }))
    expect(screen.getByText('Playlist selected.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeEnabled()

    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    expect(screen.getByText('Guide selected.')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Guided setup steps' })).getAllByText('Not checked')).toHaveLength(3)
    expect(picker).toHaveBeenNthCalledWith(1, 'workspace')
    expect(picker).toHaveBeenNthCalledWith(2, 'playlist')
    expect(picker).toHaveBeenNthCalledWith(3, 'guide')
  })

  it('keeps cancellation safe and maps picker errors to fixed UI copy', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>()
      .mockResolvedValueOnce(cancelledResult('workspace'))
      .mockResolvedValueOnce({
        kind: 'workspace',
        outcome: 'rejected',
        selectionStatus: 'not-selected',
        validationStatus: 'not-checked',
        errorCode: 'wrong-kind',
      })
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('No workspace is selected.')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Selection cancelled. Try again.')

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByRole('alert')).toHaveTextContent('That selection cannot be used here. Try again.')
    expect(screen.getByRole('alert')).not.toHaveTextContent(/(?:[A-Za-z]:[\\/]|https?:\/\/|token|password|secret|credential)/i)
  })

  it('resets downstream display state when an earlier selection changes', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>()
      .mockResolvedValueOnce(selectedResult('workspace'))
      .mockResolvedValueOnce(selectedResult('playlist'))
      .mockResolvedValueOnce(selectedResult('workspace'))
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    await user.click(screen.getByRole('button', { name: 'Add playlist' }))
    expect(screen.getByText('Playlist selected.')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('No playlist is selected.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeDisabled()
  })
})
