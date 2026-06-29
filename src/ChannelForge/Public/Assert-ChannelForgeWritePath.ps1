function Assert-ChannelForgeWritePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$AllowedRoot
    )

    # Throwing guardrail for every write site (see issue #5, ADR 0004).
    # There is no default AllowedRoot: every caller must declare which
    # approved area a write belongs under, so intent is explicit at the
    # call site instead of assumed.
    if (-not (Test-ChannelForgeWritePath -Path $Path -AllowedRoot $AllowedRoot)) {
        throw "Refusing to write outside the approved location. '$Path' must stay under: $AllowedRoot"
    }
}
