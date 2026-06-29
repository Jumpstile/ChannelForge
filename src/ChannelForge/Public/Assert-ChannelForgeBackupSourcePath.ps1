function Assert-ChannelForgeBackupSourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Throwing guardrail wrapper around Test-ChannelForgeBackupSourcePath
    # (see issue #5 verification follow-up). Existence/type checks alone
    # (Assert-ChannelForgePathExists) don't catch a backup source that
    # exists but is dangerously broad, such as an entire drive root.
    if (-not (Test-ChannelForgeBackupSourcePath -Path $Path)) {
        throw "Refusing to back up a drive root or well-known system directory: $Path"
    }
}
