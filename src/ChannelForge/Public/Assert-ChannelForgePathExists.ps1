function Assert-ChannelForgePathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('Leaf', 'Container')]
        [string]$PathType = 'Leaf',

        [string]$Description = 'Required path'
    )

    # Fail-safe guardrail for any operation that reads from, or copies out
    # of, a path outside ChannelForge's own source-of-truth data (see issue
    # #5). Checking existence up front turns a missing path into a clear
    # error instead of a silently empty/corrupt downstream operation
    # (e.g. an empty backup archive).
    if (-not (Test-Path -LiteralPath $Path -PathType $PathType)) {
        throw "$Description not found: $Path"
    }
}
