function Resolve-ChannelForgeProviderConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderDirectory,

        [Parameter(Mandatory)]
        [string]$TrackedFileName,

        [string]$OverridePath
    )

    # Precedence (issue #20): explicit override > exactly one non-recursive
    # *.local.json > tracked fallback. This function only selects which file
    # to use; it never reads or validates its contents. Callers must read
    # the selected path directly (e.g. via Read-ChannelForgeProvider) with no
    # try/catch-to-fallback around that read - a selected file that is
    # missing, malformed, or fails schema/URL validation must fail the build,
    # never silently fall through to the tracked file.
    if ($OverridePath) {
        # An absolute drive-qualified path or a UNC path must be rejected
        # before combining: Join-Path followed by [System.IO.Path]::GetFullPath
        # does not re-root an embedded "C:\..." or "\\server\..." segment on
        # Windows, so it would otherwise still resolve as a literal (and
        # always-confined-looking) subpath of $ProviderDirectory, silently
        # defeating the containment check below. Reject it explicitly first.
        if ([System.IO.Path]::IsPathRooted($OverridePath)) {
            throw "Refusing to read from outside the approved location. '$OverridePath' must stay under: $ProviderDirectory"
        }

        # ".." traversal is caught here: combine against the allowed root,
        # then confine the full resolved path.
        $combinedOverride = Join-Path $ProviderDirectory $OverridePath
        Assert-ChannelForgeReadPath -Path $combinedOverride -AllowedRoot $ProviderDirectory

        if (Test-Path -LiteralPath $combinedOverride -PathType Container) {
            throw "Provider override path must be a file, not a directory: $OverridePath"
        }

        if (-not (Test-Path -LiteralPath $combinedOverride -PathType Leaf)) {
            throw "Provider override file not found: $OverridePath"
        }

        if ([System.IO.Path]::GetExtension($combinedOverride) -ne '.json') {
            throw "Provider override file must be a .json file: $OverridePath"
        }

        return [System.IO.Path]::GetFullPath($combinedOverride)
    }

    # No override: discovery is non-recursive (Get-ChildItem without
    # -Recurse) and confined to $ProviderDirectory itself, matching the
    # *.local.json convention already documented in SECURITY.md.
    $localMatches = @()
    if (Test-Path -LiteralPath $ProviderDirectory -PathType Container) {
        $localMatches = @(Get-ChildItem -LiteralPath $ProviderDirectory -Filter '*.local.json' -File)
    }

    if ($localMatches.Count -gt 1) {
        $names = ($localMatches | Sort-Object Name | ForEach-Object Name) -join ', '
        throw "Multiple local provider files found in '$ProviderDirectory': $names. Keep exactly one, or pass an explicit -ProviderPath override."
    }

    if ($localMatches.Count -eq 1) {
        return $localMatches[0].FullName
    }

    return (Join-Path $ProviderDirectory $TrackedFileName)
}
