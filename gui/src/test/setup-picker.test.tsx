import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { GuidedSetupPage } from '../pages/GuidedSetupPage'
import type { SetupPicker, SetupSelectionKind, SetupSelectionResult } from '../app/setupSelection'

function selectedResult(kind: SetupSelectionKind): SetupSelectionResult {
  return {
    kind,
    outcome: 'selected',
    selectionStatus: 'selected',
    validationStatus: 'ready-to-inspect',
    reasonCode: null,
    ...(kind === 'playlist'
      ? {
          playlistContent: {
            contentStatus: 'checked',
            entryCount: 2,
            reasonCode: null,
          },
        }
      : {}),
  }
}

function cancelledResult(kind: SetupSelectionKind): SetupSelectionResult {
  return {
    kind,
    outcome: 'cancelled',
    selectionStatus: 'not-selected',
    validationStatus: 'not-checked',
    reasonCode: null,
  }
}

describe('native picker bridge flow', () => {
  it('enables setup items sequentially only after pre-parse checks are ready', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>(async (kind) => selectedResult(kind))
    render(<GuidedSetupPage picker={picker} pickerAvailable />)
    expect(screen.getByRole('heading', { name: 'Selection available' })).toBeInTheDocument()
    expect(screen.getByText('Selection checks confirm only that the item exists, has the expected type, and can be accessed now. Playlist content is checked for safe M3U structure only; guide contents remain unchecked.')).toBeInTheDocument()
    expect(screen.getByText('The playlist is checked for safe M3U structure only. Stream URLs are not opened or displayed.')).toBeInTheDocument()
    expect(screen.getAllByText('Selection enabled')).toHaveLength(3)

    expect(screen.getByRole('button', { name: 'Choose workspace' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeDisabled()

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('Workspace is ready to inspect.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeEnabled()

    await user.click(screen.getByRole('button', { name: 'Add playlist' }))
    expect(screen.getByText('Playlist is ready to inspect.')).toBeInTheDocument()
    expect(screen.getByText('Playlist content checked. 2 channel entries found.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeEnabled()

    await user.click(screen.getByRole('button', { name: 'Add guide' }))
    expect(screen.getByText('Guide is ready to inspect.')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Guided setup steps' })).getAllByText('Ready to inspect')).toHaveLength(3)
    expect(picker).toHaveBeenNthCalledWith(1, 'workspace')
    expect(picker).toHaveBeenNthCalledWith(2, 'playlist')
    expect(picker).toHaveBeenNthCalledWith(3, 'guide')
  })

  it('keeps guide selection gated when playlist content needs attention', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>()
      .mockResolvedValueOnce(selectedResult('workspace'))
      .mockResolvedValueOnce({
        kind: 'playlist',
        outcome: 'selected',
        selectionStatus: 'selected',
        validationStatus: 'ready-to-inspect',
        reasonCode: null,
        playlistContent: {
          contentStatus: 'needs-attention',
          entryCount: null,
          reasonCode: 'missing-header',
        },
      })
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    await user.click(screen.getByRole('button', { name: 'Add playlist' }))

    expect(screen.getByText('Playlist content needs attention. The file must start with #EXTM3U.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeDisabled()
  })

  it('shows checking while a fake picker is pending', async () => {
    const user = userEvent.setup()
    let resolvePicker!: (result: SetupSelectionResult) => void
    const pickerPromise = new Promise<SetupSelectionResult>((resolve) => {
      resolvePicker = resolve
    })
    const picker = vi.fn<SetupPicker>(() => pickerPromise)
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('Checking workspace...')).toBeInTheDocument()
    expect(screen.getByText('Checking')).toBeInTheDocument()

    resolvePicker(selectedResult('workspace'))
    await waitFor(() => expect(screen.getByText('Workspace is ready to inspect.')).toBeInTheDocument())
  })

  it('shows playlist content checking while content scan is pending', async () => {
    const user = userEvent.setup()
    let resolvePicker!: (result: SetupSelectionResult) => void
    const pickerPromise = new Promise<SetupSelectionResult>((resolve) => {
      resolvePicker = resolve
    })
    const picker = vi.fn<SetupPicker>()
      .mockResolvedValueOnce(selectedResult('workspace'))
      .mockReturnValueOnce(pickerPromise)
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    await user.click(screen.getByRole('button', { name: 'Add playlist' }))
    expect(screen.getByText('Checking playlist content...')).toBeInTheDocument()
    expect(within(screen.getByRole('status', { name: 'Add playlist selection status' })).getAllByText('Checking')).toHaveLength(2)

    resolvePicker(selectedResult('playlist'))
    await waitFor(() => expect(screen.getByText('Playlist content checked. 2 channel entries found.')).toBeInTheDocument())
  })

  it('preserves prior state on cancellation and maps attention reasons to fixed copy', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>()
      .mockResolvedValueOnce(selectedResult('workspace'))
      .mockResolvedValueOnce(cancelledResult('workspace'))
      .mockResolvedValueOnce({
        kind: 'workspace',
        outcome: 'selected',
        selectionStatus: 'selected',
        validationStatus: 'needs-attention',
        reasonCode: 'not-readable',
      })
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('Workspace is ready to inspect.')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Selection cancelled. Try again.')

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('Workspace needs attention.')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Workspace cannot be opened. Try again.')
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeDisabled()
  })

  it('maps rejected picker reasons to fixed UI copy without native values', async () => {
    const user = userEvent.setup()
    const picker = vi.fn<SetupPicker>().mockResolvedValue({
      kind: 'workspace',
      outcome: 'rejected',
      selectionStatus: 'not-selected',
      validationStatus: 'not-checked',
      reasonCode: 'wrong-kind',
    })
    render(<GuidedSetupPage picker={picker} pickerAvailable />)

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Choose a folder for the workspace. Try again.')
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
    expect(screen.getByText('Playlist is ready to inspect.')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Choose workspace' }))
    expect(screen.getByText('No playlist is selected.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add playlist' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Add guide' })).toBeDisabled()
  })

})
