function Test-ChannelForgeBackupSourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    # Defense-in-depth for backup sources (issue #5 verification follow-up).
    # This is a narrow heuristic, not an allowlist: it rejects backing up an
    # entire drive root or a well-known OS/system directory directly under a
    # drive root, which is almost always a misconfiguration rather than an
    # intentional IPTVBoss data path. It deliberately does not try to
    # enumerate every sensitive path on every platform; legitimate IPTVBoss
    # installs live on deeply nested application data paths (the default
    # parameter value in Backup-IPTVBoss.ps1 is one example), and a broader
    # allowlist would be more likely to reject real usage than catch a real
    # mistake.
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $false
    }

    $normalized = $resolved.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    $root = [System.IO.Path]::GetPathRoot($resolved).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    # Reject an entire drive/filesystem root (e.g. "C:\", "/").
    if ([string]::IsNullOrEmpty($normalized) -or $normalized -ieq $root) {
        return $false
    }

    $blockedTopLevelNames = @(
        'windows', 'program files', 'program files (x86)', 'programdata',
        'system32', 'boot', 'etc', 'proc', 'sys', 'root', 'bin', 'usr'
    )

    $parent = (Split-Path -Parent $normalized).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $leaf = Split-Path -Leaf $normalized

    if ($parent -ieq $root -and $blockedTopLevelNames -contains $leaf.ToLowerInvariant()) {
        return $false
    }

    return $true
}
