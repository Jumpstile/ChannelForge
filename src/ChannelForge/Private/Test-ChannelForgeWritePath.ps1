function Test-ChannelForgeWritePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$AllowedRoot
    )

    # Path-safety guardrail (see ADR 0004 and PRINCIPLES.md "Safety first").
    # A write target is only safe if its resolved full path is the allowed
    # root itself or a descendant of it. Resolving full paths first means
    # ".." segments and relative paths cannot be used to escape the root.
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($AllowedRoot)) {
        return $false
    }

    try {
        $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $false
    }

    if ($resolvedPath -ieq $resolvedRoot) {
        return $true
    }

    $rootWithSeparator = $resolvedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    return $resolvedPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}
