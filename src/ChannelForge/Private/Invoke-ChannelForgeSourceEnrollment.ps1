$script:ChannelForgeSourceEnrollmentVersion = 'source-enrollment/v1'

function Get-ChannelForgeSourceEnrollmentPaths {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $stateRoot = Join-Path $root 'state'
    return [pscustomobject][ordered]@{
        RepositoryRoot = $root
        StateRoot = $stateRoot
        EnrollmentPath = Join-Path $stateRoot 'source-enrollment.json'
        ManagedSourceRoot = Join-Path $stateRoot 'managed-sources'
        StagingRoot = Join-Path $stateRoot '.source-enrollment-staging'
    }
}

function Assert-ChannelForgeSourceEnrollmentDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Create
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\')) { throw 'FAIL_CLOSED: source enrollment does not support UNC roots.' }
    if (-not [System.IO.Directory]::Exists($full)) {
        if (-not $Create) { throw "SOURCE_ENROLLMENT_UNAVAILABLE: managed source directory is missing." }
        [System.IO.Directory]::CreateDirectory($full) | Out-Null
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'FAIL_CLOSED: source enrollment directory is a reparse point.'
    }
    return $full
}

function Assert-ChannelForgeSourceEnrollmentPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [switch]$AllowMissingLeaf
    )

    $root = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92, [char]47)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($root.StartsWith('\\') -or -not ($full -ceq $root -or $full.StartsWith("$root$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase))) {
        throw 'FAIL_CLOSED: source enrollment path escaped its allowed root.'
    }

    $relative = if ($full -ceq $root) { '' } else { $full.Substring($root.Length).TrimStart([char]92, [char]47) }
    $cursor = $root
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $cursor = Join-Path $cursor $part
        if ([System.IO.File]::Exists($cursor) -or [System.IO.Directory]::Exists($cursor)) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "FAIL_CLOSED: source enrollment path contains a reparse point: $part"
            }
        }
        elseif (-not ($AllowMissingLeaf -and $cursor -ceq $full)) {
            throw "SOURCE_ENROLLMENT_UNAVAILABLE: source enrollment path is missing: $part"
        }
    }
    return $full
}

function Get-ChannelForgeSourceEnrollmentHash {
    param(
        [Parameter(Mandatory)]$Enrollment
    )

    $projection = [ordered]@{}
    foreach ($property in @($Enrollment.PSObject.Properties)) {
        if ($property.Name -cne 'EnrollmentHash') { $projection[$property.Name] = $property.Value }
    }
    return Get-ChannelForgeDomainHash -Domain 'source-enrollment/v1' -InputObject $projection
}

function Get-ChannelForgeSourceEnrollmentSourceHash {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    if ($Bytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: managed source bytes cannot be empty.' }
    return Get-ChannelForgeDomainHash -Domain 'managed-source-bytes/v1' -Bytes $Bytes
}

function Get-ChannelForgeSourceEnrollmentSourceId {
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$ContentHash
    )

    return Get-ChannelForgeDomainHash -Domain 'managed-source-id/v1' -InputObject ([ordered]@{ Kind = $Kind; ContentHash = $ContentHash })
}

function Write-ChannelForgeSourceEnrollmentAtomicBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$AllowedRoot
    )

    Assert-ChannelForgeSourceEnrollmentDirectory -Path $AllowedRoot -Create | Out-Null
    $full = Assert-ChannelForgeSourceEnrollmentPath -Path $Path -AllowedRoot $AllowedRoot -AllowMissingLeaf
    $parent = Split-Path -Parent $full
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $parent -Create | Out-Null
    $temporary = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($full) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    Assert-ChannelForgeSourceEnrollmentPath -Path $temporary -AllowedRoot $AllowedRoot -AllowMissingLeaf | Out-Null
    try {
        [System.IO.File]::WriteAllBytes($temporary, $Bytes)
        if ([System.IO.File]::Exists($full)) {
            [System.IO.File]::Move($temporary, $full, $true)
        }
        else {
            [System.IO.File]::Move($temporary, $full)
        }
    }
    finally {
        if ([System.IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Write-ChannelForgeSourceEnrollmentAtomicJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$AllowedRoot
    )

    $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $Value))
    Write-ChannelForgeSourceEnrollmentAtomicBytes -Path $Path -Bytes $bytes -AllowedRoot $AllowedRoot
}

function Read-ChannelForgeSourceEnrollmentRecord {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [string]$Path = ''
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $enrollmentPath = if ([string]::IsNullOrWhiteSpace($Path)) { $paths.EnrollmentPath } else { [System.IO.Path]::GetFullPath($Path) }
    Assert-ChannelForgeSourceEnrollmentPath -Path $enrollmentPath -AllowedRoot $paths.StateRoot | Out-Null
    if (-not [System.IO.File]::Exists($enrollmentPath)) { throw 'SOURCE_ENROLLMENT_UNAVAILABLE: source enrollment has not been saved.' }
    $item = Get-Item -LiteralPath $enrollmentPath -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FAIL_CLOSED: source enrollment record is a reparse point.' }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $bytes = [System.IO.File]::ReadAllBytes($enrollmentPath)
    $text = $utf8.GetString($bytes)
    try { $enrollment = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop } catch { throw 'FAIL_CLOSED: source enrollment record is invalid JSON.' }
    if ($utf8.GetString($utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $enrollment))) -cne $text) { throw 'FAIL_CLOSED: source enrollment record is not canonical.' }
    if ([string]$enrollment.Version -cne $script:ChannelForgeSourceEnrollmentVersion) { throw 'FAIL_CLOSED: source enrollment version is unsupported.' }
    if ([string]$enrollment.EnrollmentHash -cne (Get-ChannelForgeSourceEnrollmentHash -Enrollment $enrollment)) { throw 'FAIL_CLOSED: source enrollment integrity check failed.' }
    if ([string]$enrollment.EnrollmentId -notmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: source enrollment identity is invalid.' }
    if ($null -eq $enrollment.M3U -or [string]$enrollment.M3U.SourceId -notmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: source enrollment M3U record is invalid.' }
    if ($null -ne $enrollment.XMLTV -and [string]$enrollment.XMLTV.SourceId -notmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: source enrollment XMLTV record is invalid.' }
    return $enrollment
}

function Get-ChannelForgeSourceEnrollmentIntegrity {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    if (-not [System.IO.File]::Exists($paths.EnrollmentPath)) {
        return [pscustomobject][ordered]@{ State = 'Missing'; Enrollment = $null; M3UState = 'NotEnrolled'; XMLTVState = 'NoGuide'; Reason = 'No saved sources were found.' }
    }

    try {
        $enrollment = Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $RepositoryRoot
    }
    catch {
        return [pscustomobject][ordered]@{ State = 'Corrupt'; Enrollment = $null; M3UState = 'NeedsAttention'; XMLTVState = 'NeedsAttention'; Reason = 'Saved sources need attention before refresh can continue.' }
    }

    $m3uState = 'Ready'
    $xmltvState = if ($null -eq $enrollment.XMLTV) { 'NoGuide' } else { 'Ready' }
    foreach ($entry in @(@{ Record = $enrollment.M3U; Name = 'M3U'; State = 'm3uState' }, @{ Record = $enrollment.XMLTV; Name = 'XMLTV'; State = 'xmltvState' })) {
        if ($null -eq $entry.Record) { continue }
        try {
            $relative = [string]$entry.Record.ManagedPath
            if ($relative -notmatch '^state/managed-sources/[0-9a-f]{64}\.(m3u|xml)$') { throw 'invalid managed source reference' }
            $path = [System.IO.Path]::GetFullPath((Join-Path $paths.RepositoryRoot ($relative -replace '/', '\')))
            Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $paths.RepositoryRoot | Out-Null
            if (-not [System.IO.File]::Exists($path)) { throw 'missing managed source' }
            $currentHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes ([System.IO.File]::ReadAllBytes($path))
            if ($currentHash -cne [string]$entry.Record.ContentHash) {
                if ($entry.Name -eq 'M3U') { $m3uState = 'Changed' } else { $xmltvState = 'Changed' }
            }
        }
        catch {
            if ($entry.Name -eq 'M3U') { $m3uState = 'Unavailable' } else { $xmltvState = 'Unavailable' }
        }
    }

    $state = if ($m3uState -eq 'Unavailable' -or $xmltvState -eq 'Unavailable') { 'SourceUnavailable' } elseif ($m3uState -eq 'Changed' -or $xmltvState -eq 'Changed') { 'Changed' } else { 'Valid' }
    $reason = switch ($state) {
        'Valid' { 'Saved sources are ready to refresh.' }
        'Changed' { 'Saved source bytes changed and require review before acceptance.' }
        'SourceUnavailable' { 'A saved source is missing or cannot be read safely.' }
        default { 'Saved sources need attention before refresh can continue.' }
    }
    return [pscustomobject][ordered]@{ State = $state; Enrollment = $enrollment; M3UState = $m3uState; XMLTVState = $xmltvState; Reason = $reason }
}

function Get-ChannelForgeSourceEnrollmentStatus {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $integrity = Get-ChannelForgeSourceEnrollmentIntegrity -RepositoryRoot $RepositoryRoot
    $enrollmentStatus = switch ($integrity.State) {
        'Valid' {
            if ([string]$integrity.Enrollment.LastRefreshStatus -eq 'up-to-date') { 'up-to-date' } else { 'saved' }
        }
        'Changed' { 'changes-found' }
        'SourceUnavailable' { 'source-unavailable' }
        'Missing' { 'not-enrolled' }
        default { 'needs-attention' }
    }
    $canRefresh = $integrity.State -in @('Valid', 'Changed')
    return [pscustomobject][ordered]@{
        EnrollmentStatus = $enrollmentStatus
        M3UStatus = switch ($integrity.M3UState) {
            'Ready' { 'ready' }
            'Changed' { 'changes-found' }
            'Unavailable' { 'source-unavailable' }
            default { 'not-enrolled' }
        }
        XMLTVStatus = switch ($integrity.XMLTVState) {
            'Ready' { 'ready' }
            'Changed' { 'changes-found' }
            'Unavailable' { 'source-unavailable' }
            'NoGuide' { 'no-guide' }
            default { 'needs-attention' }
        }
        HasSavedSources = $integrity.State -ne 'Missing'
        CanRefresh = $canRefresh
        LastCheckedUtc = if ($null -eq $integrity.Enrollment) { $null } else { [string]$integrity.Enrollment.UpdatedAtUtc }
        Guidance = $integrity.Reason
    }
}

function Get-ChannelForgeSourceEnrollmentInputs {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $integrity = Get-ChannelForgeSourceEnrollmentIntegrity -RepositoryRoot $RepositoryRoot
    if ($integrity.State -notin @('Valid', 'Changed')) { throw "SOURCE_ENROLLMENT_UNAVAILABLE: $($integrity.Reason)" }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $m3uPath = [System.IO.Path]::GetFullPath((Join-Path $paths.RepositoryRoot ([string]$integrity.Enrollment.M3U.ManagedPath -replace '/', '\')))
    $xmltvPath = if ($null -eq $integrity.Enrollment.XMLTV) { $null } else { [System.IO.Path]::GetFullPath((Join-Path $paths.RepositoryRoot ([string]$integrity.Enrollment.XMLTV.ManagedPath -replace '/', '\'))) }
    Assert-ChannelForgeSourceEnrollmentPath -Path $m3uPath -AllowedRoot $paths.RepositoryRoot | Out-Null
    if ($null -ne $xmltvPath) { Assert-ChannelForgeSourceEnrollmentPath -Path $xmltvPath -AllowedRoot $paths.RepositoryRoot | Out-Null }
    return [pscustomobject][ordered]@{ State = $integrity.State; Enrollment = $integrity.Enrollment; M3UPath = $m3uPath; XMLTVPath = $xmltvPath; M3UState = $integrity.M3UState; XMLTVState = $integrity.XMLTVState }
}

function Write-ChannelForgeSourceEnrollment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [AllowNull()][string]$AcceptedGenerationManifestHash,
        [AllowNull()][string]$AcceptedStateHash,
        [AllowNull()][string]$AcceptedOutputManifestHash
    )

    if ($M3UBytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: M3U source bytes cannot be empty.' }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.RepositoryRoot | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.StateRoot -Create | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.ManagedSourceRoot -Create | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.StagingRoot -Create | Out-Null

    $m3uHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $M3UBytes
    $m3uId = Get-ChannelForgeSourceEnrollmentSourceId -Kind M3U -ContentHash $m3uHash
    $m3uPath = Join-Path $paths.ManagedSourceRoot "$m3uId.m3u"
    Write-ChannelForgeSourceEnrollmentAtomicBytes -Path $m3uPath -Bytes $M3UBytes -AllowedRoot $paths.ManagedSourceRoot
    $m3uRecord = [ordered]@{ SourceId = $m3uId; Kind = 'M3U'; Format = 'm3u'; ManagedPath = "state/managed-sources/$m3uId.m3u"; ContentHash = $m3uHash; ByteLength = $M3UBytes.Length }

    $xmltvRecord = $null
    if ($null -ne $XMLTVBytes) {
        if ($XMLTVBytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: XMLTV source bytes cannot be empty.' }
        $xmlHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $XMLTVBytes
        $xmlId = Get-ChannelForgeSourceEnrollmentSourceId -Kind XMLTV -ContentHash $xmlHash
        $xmlPath = Join-Path $paths.ManagedSourceRoot "$xmlId.xml"
        Write-ChannelForgeSourceEnrollmentAtomicBytes -Path $xmlPath -Bytes $XMLTVBytes -AllowedRoot $paths.ManagedSourceRoot
        $xmltvRecord = [ordered]@{ SourceId = $xmlId; Kind = 'XMLTV'; Format = 'xmltv'; ManagedPath = "state/managed-sources/$xmlId.xml"; ContentHash = $xmlHash; ByteLength = $XMLTVBytes.Length }
    }

    $existing = Get-ChannelForgeSourceEnrollmentIntegrity -RepositoryRoot $RepositoryRoot
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $enrollment = [ordered]@{
        Version = $script:ChannelForgeSourceEnrollmentVersion
        EnrollmentId = Get-ChannelForgeDomainHash -Domain 'source-enrollment-id/v1' -InputObject 'browser-local-managed-sources'
        Status = 'Valid'
        GuideMode = if ($null -eq $xmltvRecord) { 'NoGuide' } else { 'XMLTV' }
        M3U = $m3uRecord
        XMLTV = $xmltvRecord
        AcceptedWorkflow = [ordered]@{ GenerationManifestHash = $AcceptedGenerationManifestHash; AcceptedStateHash = $AcceptedStateHash; AcceptedOutputManifestHash = $AcceptedOutputManifestHash }
        RefreshPolicy = [ordered]@{ Mode = 'Manual'; AutoAccept = $false }
        LastRefreshStatus = 'saved'
        CreatedAtUtc = if ($null -eq $existing.Enrollment) { $now } else { [string]$existing.Enrollment.CreatedAtUtc }
        UpdatedAtUtc = $now
    }
    $enrollment.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment ([pscustomobject]$enrollment)
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path $paths.EnrollmentPath -Value ([pscustomobject]$enrollment) -AllowedRoot $paths.StateRoot
    return [pscustomobject]$enrollment
}

function Update-ChannelForgeSourceEnrollmentRefreshState {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateSet('up-to-date', 'changes-found')][string]$RefreshStatus
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $enrollment = Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $RepositoryRoot
    $enrollment.LastRefreshStatus = $RefreshStatus
    $enrollment.UpdatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $enrollment.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $enrollment
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path $paths.EnrollmentPath -Value $enrollment -AllowedRoot $paths.StateRoot
    return [pscustomobject]$enrollment
}
