function Assert-ChannelForgeReadPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$AllowedRoot
    )

    # Throwing guardrail for read sites that accept a configured path (e.g.
    # provider.json's local_playlist - see issue #7 Phase 1). Reuses the
    # same full-path containment check as Assert-ChannelForgeWritePath:
    # resolving full paths first means "..", an absolute path elsewhere on
    # disk, a UNC path, or a drive root/system path can never satisfy the
    # check unless they happen to truly resolve under AllowedRoot. There is
    # no default root, so every caller must declare where a configured
    # read path is allowed to come from.
    if (-not (Test-ChannelForgeWritePath -Path $Path -AllowedRoot $AllowedRoot)) {
        throw "Refusing to read from outside the approved location. '$Path' must stay under: $AllowedRoot"
    }
}
