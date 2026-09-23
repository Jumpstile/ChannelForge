$script:ChannelForgeSourceEnrollmentVersion = 'source-enrollment/v2'

function Get-ChannelForgeSourceEnrollmentPaths {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
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
    param([Parameter(Mandatory)][string]$Path,[switch]$Create)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\')) { throw 'FAIL_CLOSED: source enrollment does not support UNC roots.' }
    if (-not [System.IO.Directory]::Exists($full)) {
        if (-not $Create) { throw 'SOURCE_ENROLLMENT_UNAVAILABLE: managed source directory is missing.' }
        [System.IO.Directory]::CreateDirectory($full) | Out-Null
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FAIL_CLOSED: source enrollment directory is a reparse point.' }
    return $full
}

function Assert-ChannelForgeSourceEnrollmentPath {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$AllowedRoot,[switch]$AllowMissingLeaf)
    $root = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92, [char]47)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($root.StartsWith('\\') -or -not ($full -ceq $root -or $full.StartsWith("$root$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase))) { throw 'FAIL_CLOSED: source enrollment path escaped its allowed root.' }
    $relative = if ($full -ceq $root) { '' } else { $full.Substring($root.Length).TrimStart([char]92, [char]47) }
    $cursor = $root
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $cursor = Join-Path $cursor $part
        if ([System.IO.File]::Exists($cursor) -or [System.IO.Directory]::Exists($cursor)) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "FAIL_CLOSED: source enrollment path contains a reparse point: $part" }
        } elseif (-not ($AllowMissingLeaf -and $cursor -ceq $full)) { throw "SOURCE_ENROLLMENT_UNAVAILABLE: source enrollment path is missing: $part" }
    }
    return $full
}

function Get-ChannelForgeSourceEnrollmentHash {
    param([Parameter(Mandatory)]$Enrollment)
    $projection = [ordered]@{}
    foreach ($property in @($Enrollment.PSObject.Properties)) {
        if ($property.Name -cne 'EnrollmentHash' -and $property.Name -cne 'SourceSetHash') { $projection[$property.Name] = $property.Value }
    }
    return Get-ChannelForgeDomainHash -Domain 'source-enrollment/v2' -InputObject $projection
}

function Get-ChannelForgeSourceEnrollmentSourceHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    if ($Bytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: managed source bytes cannot be empty.' }
    return Get-ChannelForgeDomainHash -Domain 'managed-source-bytes/v1' -Bytes $Bytes
}

function Get-ChannelForgeSourceEnrollmentSourceId {
    param([Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,[Parameter(Mandatory)][string]$ContentHash)
    return Get-ChannelForgeDomainHash -Domain 'managed-source-id/v1' -InputObject ([ordered]@{ Kind = $Kind; ContentHash = $ContentHash })
}

function Get-ChannelForgeSourceSetSourceId {
    param([Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,[Parameter(Mandatory)][string]$SourceKind,[Parameter(Mandatory)][string]$SourceKey)
    return Get-ChannelForgeDomainHash -Domain 'source-set-source-id/v2' -InputObject ([ordered]@{ Kind = $Kind; SourceKind = $SourceKind; SourceKey = $SourceKey })
}

function Convert-ChannelForgeSourceEnrollmentV1ToV2 {
    param([Parameter(Mandatory)]$Legacy)
    $playlist = [ordered]@{
        SourceId = [string]$Legacy.M3U.SourceId; Kind = 'M3U'; Format = 'm3u'; Label = 'Saved playlist'
        SourceKind = 'managed-file'; Enabled = $true; Present = $true; Priority = 100; OrderKey = 'playlist-0001'
        ManagedPath = [string]$Legacy.M3U.ManagedPath; Url = $null; ContentHash = [string]$Legacy.M3U.ContentHash; ByteLength = [int]$Legacy.M3U.ByteLength
        Provenance = [ordered]@{ Origin = 'legacy-source-enrollment/v1'; ImportedAtUtc = [string]$Legacy.CreatedAtUtc }
        Refresh = [ordered]@{ State = 'unknown'; LastValidatedAtUtc = $null; CacheKey = $null; ETag = $null; LastModified = $null }
    }
    $guides = @()
    $bindings = @()
    if ($null -ne $Legacy.XMLTV) {
        $guide = [ordered]@{
            SourceId = [string]$Legacy.XMLTV.SourceId; Kind = 'XMLTV'; Format = 'xmltv'; Label = 'Saved guide'
            SourceKind = 'managed-file'; Enabled = $true; Present = $true; Priority = 100; OrderKey = 'guide-0001'
            ManagedPath = [string]$Legacy.XMLTV.ManagedPath; Url = $null; ContentHash = [string]$Legacy.XMLTV.ContentHash; ByteLength = [int]$Legacy.XMLTV.ByteLength
            Provenance = [ordered]@{ Origin = 'legacy-source-enrollment/v1'; ImportedAtUtc = [string]$Legacy.CreatedAtUtc }
            Refresh = [ordered]@{ State = 'unknown'; LastValidatedAtUtc = $null; CacheKey = $null; ETag = $null; LastModified = $null }
        }
        $guides = @($guide)
        $bindings = @([ordered]@{ BindingId = Get-ChannelForgeDomainHash -Domain 'source-binding/v2' -InputObject ([ordered]@{ GuideId = $guide.SourceId; PlaylistIds = @($playlist.SourceId); AppliesToAll = $false; Revision = 1 }); GuideId = $guide.SourceId; PlaylistIds = @($playlist.SourceId); AppliesToAll = $false; Enabled = $true; Revision = 1 })
    }
    $converted = [ordered]@{
        Version = 'source-enrollment/v2'; SourceSetId = Get-ChannelForgeDomainHash -Domain 'source-set-id/v2' -InputObject 'browser-local-managed-sources'
        EnrollmentId = [string]$Legacy.EnrollmentId; Status = [string]$Legacy.Status; GuideMode = if ($guides.Count -eq 0) { 'NoGuide' } else { 'XMLTV' }
        Playlists = @($playlist); Guides = @($guides); Bindings = @($bindings)
        AcceptedWorkflow = $Legacy.AcceptedWorkflow; RefreshPolicy = $Legacy.RefreshPolicy; LastRefreshStatus = $Legacy.LastRefreshStatus
        CreatedAtUtc = [string]$Legacy.CreatedAtUtc; UpdatedAtUtc = [string]$Legacy.UpdatedAtUtc; LegacyVersion = 'source-enrollment/v1'
    }
    $converted.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment ([pscustomobject]$converted)
    return [pscustomobject]$converted
}
function Assert-ChannelForgeSourceEnrollmentV2Integrity {
    param([Parameter(Mandatory)]$Record)
    $playlists = @($Record.Playlists)
    $guides = @($Record.Guides)
    $allSources = @($playlists) + @($guides)
    $sourceIds = @($allSources | ForEach-Object { [string]$_.SourceId })
    if ($sourceIds.Count -ne @($sourceIds | Sort-Object -Unique).Count) { throw 'FAIL_CLOSED: source enrollment contains duplicate source identity.' }
    if (@($playlists | Where-Object { [string]$_.Kind -cne 'M3U' }).Count -gt 0 -or @($guides | Where-Object { [string]$_.Kind -cne 'XMLTV' }).Count -gt 0) { throw 'FAIL_CLOSED: source enrollment collection kind is invalid.' }
    $playlistIds = @($playlists | ForEach-Object SourceId)
    $guideIds = @($guides | ForEach-Object SourceId)
    $bindingIds = @($Record.Bindings | ForEach-Object { [string]$_.BindingId })
    if ($bindingIds.Count -ne @($bindingIds | Sort-Object -Unique).Count) { throw 'FAIL_CLOSED: source enrollment contains duplicate binding identity.' }
    $effective = @{}
    foreach ($binding in @($Record.Bindings)) {
        $guideId = [string]$binding.GuideId
        if ($guideId -notin $guideIds) { throw 'FAIL_CLOSED: source enrollment binding references a missing guide.' }
        $all = [bool]$binding.AppliesToAll
        $ids = @($binding.PlaylistIds | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if ($all) {
            if ($ids.Count -ne 0) { throw 'FAIL_CLOSED: ALL source enrollment binding must not list playlist IDs.' }
        } elseif ($ids.Count -eq 0 -or @($ids | Where-Object { $_ -notin $playlistIds }).Count -gt 0) {
            throw 'FAIL_CLOSED: source enrollment binding references an invalid playlist selection.'
        }
        $key = "$guideId|$all|$($ids -join ',')"
        if ($effective.ContainsKey($key)) { throw 'FAIL_CLOSED: source enrollment contains a duplicate effective guide binding.' }
        $effective[$key] = $true
    }
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
    param([string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),[string]$Path = '')
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $enrollmentPath = if ([string]::IsNullOrWhiteSpace($Path)) { $paths.EnrollmentPath } else { [System.IO.Path]::GetFullPath($Path) }
    Assert-ChannelForgeSourceEnrollmentPath -Path $enrollmentPath -AllowedRoot $paths.StateRoot | Out-Null
    if (-not [System.IO.File]::Exists($enrollmentPath)) { throw 'SOURCE_ENROLLMENT_UNAVAILABLE: source enrollment has not been saved.' }
    $item = Get-Item -LiteralPath $enrollmentPath -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FAIL_CLOSED: source enrollment record is a reparse point.' }
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $utf8.GetString([System.IO.File]::ReadAllBytes($enrollmentPath))
    try { $record = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop } catch { throw 'FAIL_CLOSED: source enrollment record is invalid JSON.' }
    if ($utf8.GetString($utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $record))) -cne $text) { throw 'FAIL_CLOSED: source enrollment record is not canonical.' }
    if ([string]$record.Version -eq 'source-enrollment/v1') {
        if ([string]$record.EnrollmentHash -cne (Get-ChannelForgeDomainHash -Domain 'source-enrollment/v1' -InputObject ([ordered]@{ Version = $record.Version; EnrollmentId = $record.EnrollmentId; Status = $record.Status; GuideMode = $record.GuideMode; M3U = $record.M3U; XMLTV = $record.XMLTV; AcceptedWorkflow = $record.AcceptedWorkflow; RefreshPolicy = $record.RefreshPolicy; LastRefreshStatus = $record.LastRefreshStatus; CreatedAtUtc = $record.CreatedAtUtc; UpdatedAtUtc = $record.UpdatedAtUtc }))) { throw 'FAIL_CLOSED: source enrollment integrity check failed.' }
        return Convert-ChannelForgeSourceEnrollmentV1ToV2 -Legacy $record
    }
    if ([string]$record.Version -cne $script:ChannelForgeSourceEnrollmentVersion) { throw 'FAIL_CLOSED: source enrollment version is unsupported.' }
    if ([string]$record.EnrollmentHash -cne (Get-ChannelForgeSourceEnrollmentHash -Enrollment $record)) { throw 'FAIL_CLOSED: source enrollment integrity check failed.' }
    if ([string]$record.EnrollmentId -notmatch '^[0-9a-f]{64}$' -or [string]$record.SourceSetId -notmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: source enrollment identity is invalid.' }
    if (@($record.Playlists).Count -eq 0 -or @($record.Playlists | Where-Object { [string]$_.Kind -ne 'M3U' })) { throw 'FAIL_CLOSED: source enrollment playlist records are invalid.' }
    foreach ($source in @($record.Playlists) + @($record.Guides)) {
        if ([string]$source.SourceId -notmatch '^[0-9a-f]{64}$' -or [string]$source.SourceKind -notin @('managed-file','public-https')) { throw 'FAIL_CLOSED: source enrollment source record is invalid.' }
        if ([string]$source.SourceKind -eq 'public-https') {
            $parsed = $null
            if (-not (Test-ChannelForgeSourceUrl -Url ([string]$source.Url)) -or -not [Uri]::TryCreate([string]$source.Url,[UriKind]::Absolute,[ref]$parsed) -or -not [string]::IsNullOrEmpty($parsed.UserInfo) -or -not [string]::IsNullOrEmpty($parsed.Query) -or -not [string]::IsNullOrEmpty($parsed.Fragment)) { throw 'FAIL_CLOSED: source enrollment public URL is not trusted.' }
        }
    }
    Assert-ChannelForgeSourceEnrollmentV2Integrity -Record $record
    return $record
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
    $xmltvState = if (@($enrollment.Guides).Count -eq 0) { 'NoGuide' } else { 'Ready' }
    $sourceStates = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(@{ Records = @($enrollment.Playlists); Name = 'M3U' }, @{ Records = @($enrollment.Guides); Name = 'XMLTV' })) {
        foreach ($record in $entry.Records) {
            $sourceState = 'Ready'
            if ([string]$record.SourceKind -eq 'public-https') {
                $refreshState = if ($null -ne $record.Refresh -and $record.Refresh.PSObject.Properties.Name -contains 'State') {
                    [string]$record.Refresh.State
                } else { 'saved' }
                if ($refreshState -eq 'source-unavailable') {
                    $sourceState = 'Unavailable'
                } elseif ($refreshState -eq 'changes-found') {
                    $sourceState = 'Changed'
                } elseif ([string]::IsNullOrWhiteSpace([string]$record.ManagedPath)) {
                    $sourceState = 'Remote'
                } else {
                    try {
                        $relative = [string]$record.ManagedPath
                        if ($relative -notmatch '^state/managed-sources/[0-9a-f]{64}\.(m3u|xml)$') { throw 'invalid managed source reference' }
                        $path = [System.IO.Path]::GetFullPath((Join-Path $paths.RepositoryRoot ($relative -replace '/', '\')))
                        Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $paths.RepositoryRoot | Out-Null
                        if (-not [System.IO.File]::Exists($path)) { throw 'missing managed source' }
                        $currentHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes ([System.IO.File]::ReadAllBytes($path))
                        if ($currentHash -cne [string]$record.ContentHash) { $sourceState = 'Changed' }
                    }
                    catch { $sourceState = 'Unavailable' }
                }
            }
            else {
                try {
                    $relative = [string]$record.ManagedPath
                    if ($relative -notmatch '^state/managed-sources/[0-9a-f]{64}\.(m3u|xml)$') { throw 'invalid managed source reference' }
                    $path = [System.IO.Path]::GetFullPath((Join-Path $paths.RepositoryRoot ($relative -replace '/', '\')))
                    Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $paths.RepositoryRoot | Out-Null
                    if (-not [System.IO.File]::Exists($path)) { throw 'missing managed source' }
                    $currentHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes ([System.IO.File]::ReadAllBytes($path))
                    if ($currentHash -cne [string]$record.ContentHash) { $sourceState = 'Changed' }
                }
                catch { $sourceState = 'Unavailable' }
            }
            if ($entry.Name -eq 'M3U' -and $sourceState -eq 'Changed') { $m3uState = 'Changed' }
            if ($entry.Name -eq 'M3U' -and $sourceState -eq 'Unavailable') { $m3uState = 'Unavailable' }
            if ($entry.Name -eq 'XMLTV' -and $sourceState -eq 'Changed') { $xmltvState = 'Changed' }
            if ($entry.Name -eq 'XMLTV' -and $sourceState -eq 'Unavailable') { $xmltvState = 'Unavailable' }
            [void]$sourceStates.Add([pscustomobject][ordered]@{
                SourceId = [string]$record.SourceId
                Kind = $entry.Name
                Label = [string]$record.Label
                SourceKind = [string]$record.SourceKind
                Enabled = [bool]$record.Enabled
                State = $sourceState
                ManagedPath = [string]$record.ManagedPath
            })
        }
    }
    $state = if ($m3uState -eq 'Unavailable' -or $xmltvState -eq 'Unavailable') { 'SourceUnavailable' } elseif ($m3uState -eq 'Changed' -or $xmltvState -eq 'Changed') { 'Changed' } else { 'Valid' }
    $reason = switch ($state) {
        'Valid' { 'Saved sources are ready.' }
        'Changed' { 'Saved source bytes changed and require review before acceptance.' }
        'SourceUnavailable' { 'A saved source is missing or cannot be read safely.' }
    }
    return [pscustomobject][ordered]@{
        State = $state
        Enrollment = $enrollment
        M3UState = $m3uState
        XMLTVState = $xmltvState
        SourceStates = @($sourceStates.ToArray())
        Reason = $reason
    }
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
    $canRefresh = $integrity.State -in @('Valid', 'Changed') -or @($integrity.SourceStates | Where-Object {
        $_.SourceKind -eq 'public-https' -and $_.State -in @('Remote', 'Unavailable', 'Changed')
    }).Count -gt 0
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
        Sources = @($integrity.SourceStates | ForEach-Object {
            [ordered]@{
                Kind = [string]$_.Kind
                Label = [string]$_.Label
                SourceKind = [string]$_.SourceKind
                Enabled = [bool]$_.Enabled
                State = [string]$_.State
            }
        })
    }
}
function Get-ChannelForgeSourceEnrollmentInputs {
    $integrity = Get-ChannelForgeSourceEnrollmentIntegrity -RepositoryRoot $RepositoryRoot
    $remoteRetryable = @($integrity.SourceStates | Where-Object { $_.SourceKind -eq 'public-https' -and $_.State -in @('Remote', 'Unavailable', 'Changed') }).Count -gt 0
    if ($integrity.State -notin @('Valid', 'Changed') -and -not $remoteRetryable) { throw "SOURCE_ENROLLMENT_UNAVAILABLE: $($integrity.Reason)" }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $playlist = @($integrity.Enrollment.Playlists | Where-Object { $_.Enabled }) | Sort-Object Priority, OrderKey, SourceId | Select-Object -First 1
    $guide = @($integrity.Enrollment.Guides | Where-Object { $_.Enabled }) | Sort-Object Priority, OrderKey, SourceId | Select-Object -First 1
    $resolveManagedPath = {
        param($record)
        if ($null -eq $record -or [string]::IsNullOrWhiteSpace([string]$record.ManagedPath)) { return $null }
        $path = [System.IO.Path]::GetFullPath((Join-Path $paths.RepositoryRoot ([string]$record.ManagedPath -replace '/', '\')))
        Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $paths.RepositoryRoot | Out-Null
        return $path
    }
    $m3uPath = & $resolveManagedPath $playlist
    $xmltvPath = & $resolveManagedPath $guide
    return [pscustomobject][ordered]@{
        State = $integrity.State
        Enrollment = $integrity.Enrollment
        M3UPath = $m3uPath
        XMLTVPath = $xmltvPath
        M3UState = $integrity.M3UState
        XMLTVState = $integrity.XMLTVState
        Playlists = @($integrity.Enrollment.Playlists)
        Guides = @($integrity.Enrollment.Guides)
        Bindings = @($integrity.Enrollment.Bindings)
        SourceStates = @($integrity.SourceStates)
        PlaylistPaths = @($integrity.Enrollment.Playlists | Where-Object { $_.Enabled } | ForEach-Object { & $resolveManagedPath $_ } | Where-Object { $null -ne $_ })
        GuidePaths = @($integrity.Enrollment.Guides | Where-Object { $_.Enabled } | ForEach-Object { & $resolveManagedPath $_ } | Where-Object { $null -ne $_ })
    }
}

function Write-ChannelForgeSourceEnrollment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [AllowNull()][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [AllowEmptyCollection()][object[]]$PlaylistSources,
        [AllowEmptyCollection()][object[]]$GuideSources = @(),
        [AllowEmptyCollection()][object[]]$Bindings = @(),
        [AllowNull()][string]$AcceptedGenerationManifestHash,
        [AllowNull()][string]$AcceptedStateHash,
        [AllowNull()][string]$AcceptedOutputManifestHash
    )
    if ($null -ne $PlaylistSources) {
        if (@($PlaylistSources).Count -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: at least one playlist is required.' }
        return Write-ChannelForgeSourceSet -RepositoryRoot $RepositoryRoot -PlaylistSources $PlaylistSources -GuideSources $GuideSources -Bindings $Bindings -AcceptedGenerationManifestHash $AcceptedGenerationManifestHash -AcceptedStateHash $AcceptedStateHash -AcceptedOutputManifestHash $AcceptedOutputManifestHash
    }
    if ($null -eq $M3UBytes -or $M3UBytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: M3U source bytes cannot be empty.' }
    $playlist = [pscustomobject][ordered]@{ Kind = 'M3U'; SourceKind = 'managed-file'; SourceKey = 'browser-playlist'; Label = 'Saved playlist'; Bytes = $M3UBytes; Priority = 100; Enabled = $true; Provenance = [ordered]@{ Origin = 'guided-setup' } }
    $guides = @()
    if ($null -ne $XMLTVBytes) {
        if ($XMLTVBytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: XMLTV source bytes cannot be empty.' }
        $guides = @([pscustomobject][ordered]@{ Kind = 'XMLTV'; SourceKind = 'managed-file'; SourceKey = 'browser-guide'; Label = 'Saved guide'; Bytes = $XMLTVBytes; Priority = 100; Enabled = $true; Provenance = [ordered]@{ Origin = 'guided-setup' } })
    }
    return Write-ChannelForgeSourceSet -RepositoryRoot $RepositoryRoot -PlaylistSources @($playlist) -GuideSources $guides -AcceptedGenerationManifestHash $AcceptedGenerationManifestHash -AcceptedStateHash $AcceptedStateHash -AcceptedOutputManifestHash $AcceptedOutputManifestHash

}
function Write-ChannelForgeSourceSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][object[]]$PlaylistSources,
        [object[]]$GuideSources = @(),
        [object[]]$Bindings = @(),
        [AllowNull()][string]$AcceptedGenerationManifestHash,
        [AllowNull()][string]$AcceptedStateHash,
        [AllowNull()][string]$AcceptedOutputManifestHash
    )
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.RepositoryRoot | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.StateRoot -Create | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.ManagedSourceRoot -Create | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $paths.StagingRoot -Create | Out-Null
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $makeSource = {
        param($descriptor,$index)
        $kind = [string]$descriptor.Kind
        if ($kind -notin @('M3U','XMLTV')) { throw 'SOURCE_ENROLLMENT_INVALID: source kind is unsupported.' }
        $sourceKind = [string]$descriptor.SourceKind
        if ($sourceKind -notin @('managed-file','public-https')) { throw 'SOURCE_ENROLLMENT_INVALID: source storage kind is unsupported.' }
        $key = [string]$descriptor.SourceKey
        if ([string]::IsNullOrWhiteSpace($key)) { $key = "$kind|$([string]$descriptor.Label)|$sourceKind" }
        $id = Get-ChannelForgeSourceSetSourceId -Kind $kind -SourceKind $sourceKind -SourceKey $key
        $managedPath = $null; $url = $null; $contentHash = $null; $byteLength = $null; $refreshState = 'saved'
        if ($sourceKind -eq 'managed-file') {
            $bytes = [byte[]]$descriptor.Bytes
            if ($null -eq $bytes -or $bytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: managed source bytes cannot be empty.' }
            $extension = if ($kind -eq 'M3U') { 'm3u' } else { 'xml' }
            $managedPath = "state/managed-sources/$id.$extension"
            Write-ChannelForgeSourceEnrollmentAtomicBytes -Path (Join-Path $paths.RepositoryRoot ($managedPath -replace '/', '\')) -Bytes $bytes -AllowedRoot $paths.ManagedSourceRoot
            $contentHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $bytes
            $byteLength = $bytes.Length
            $refreshState = 'up-to-date'
        } else {
            $url = [string]$descriptor.Url
            $parsed = $null
            if (-not (Test-ChannelForgeSourceUrl -Url $url) -or -not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$parsed) -or -not [string]::IsNullOrEmpty($parsed.UserInfo) -or -not [string]::IsNullOrEmpty($parsed.Query) -or -not [string]::IsNullOrEmpty($parsed.Fragment)) { throw 'SOURCE_ENROLLMENT_INVALID: public HTTPS source must be a non-tokenized URL.' }
            $descriptorProperties = @($descriptor.PSObject.Properties.Name)
            $bytes = if ($descriptorProperties -contains 'Bytes') { [byte[]]$descriptor.Bytes } else { $null }
            if ($null -ne $bytes) {
                if ($bytes.Length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: public HTTPS source bytes cannot be empty.' }
                $extension = if ($kind -eq 'M3U') { 'm3u' } else { 'xml' }
                $managedPath = "state/managed-sources/$id.$extension"
                Write-ChannelForgeSourceEnrollmentAtomicBytes -Path (Join-Path $paths.RepositoryRoot ($managedPath -replace '/', '\')) -Bytes $bytes -AllowedRoot $paths.ManagedSourceRoot
                $contentHash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $bytes
                $byteLength = $bytes.Length
                $refreshState = 'up-to-date'
            }
        }
        return [ordered]@{
            SourceId = $id; Kind = $kind; Format = if ($kind -eq 'M3U') { 'm3u' } else { 'xmltv' }; Label = if ([string]::IsNullOrWhiteSpace([string]$descriptor.Label)) { "$kind source" } else { [string]$descriptor.Label }
            SourceKind = $sourceKind; Enabled = if ($null -eq $descriptor.Enabled) { $true } else { [bool]$descriptor.Enabled }; Present = $true; Priority = if ($null -eq $descriptor.Priority) { 100 } else { [int]$descriptor.Priority }; OrderKey = $id
            ManagedPath = $managedPath; Url = $url; ContentHash = $contentHash; ByteLength = $byteLength
            Provenance = if ($null -eq $descriptor.Provenance) { [ordered]@{ Origin = 'source-set-v2' } } else { $descriptor.Provenance }
            Refresh = [ordered]@{ State = $refreshState; LastValidatedAtUtc = $now; CacheKey = $null; ETag = $null; LastModified = $null }
        }
    }
    $playlists = @(); $i = 0; foreach ($source in $PlaylistSources) { $playlists += & $makeSource $source $i; $i++ }
    if (@($playlists).Count -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: at least one playlist is required.' }
    $guides = @(); $i = 0; foreach ($source in $GuideSources) { $guides += & $makeSource $source $i; $i++ }
    $sourceIds = @(@($playlists) + @($guides) | ForEach-Object SourceId)
    if ($sourceIds.Count -ne @($sourceIds | Sort-Object -Unique).Count) { throw 'SOURCE_ENROLLMENT_INVALID: duplicate source identity is not allowed.' }
    $bindingsOut = @()
    foreach ($binding in $Bindings) {
        $guideId = [string]$binding.GuideId
        if ($guideId -notin @($guides | ForEach-Object SourceId)) { throw 'SOURCE_ENROLLMENT_INVALID: binding guide is not enrolled.' }
        $all = [bool]$binding.AppliesToAll
        $playlistIds = @($binding.PlaylistIds | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($all) {
            if ($playlistIds.Count -gt 0) { throw 'SOURCE_ENROLLMENT_INVALID: ALL bindings cannot list playlist IDs.' }
            $playlistIds = @()
        } elseif ($playlistIds.Count -eq 0 -or @($playlistIds | Where-Object { $_ -notin @($playlists | ForEach-Object SourceId) }).Count -gt 0) {
            throw 'SOURCE_ENROLLMENT_INVALID: binding playlist selection is invalid.'
        }
        $revision = if ($null -eq $binding.Revision) { 1 } else { [int]$binding.Revision }
        $bindingsOut += [ordered]@{ BindingId = Get-ChannelForgeDomainHash -Domain 'source-binding/v2' -InputObject ([ordered]@{ GuideId = $guideId; PlaylistIds = @($playlistIds | Sort-Object); AppliesToAll = $all; Revision = $revision }); GuideId = $guideId; PlaylistIds = @($playlistIds | Sort-Object); AppliesToAll = $all; Enabled = if ($null -eq $binding.Enabled) { $true } else { [bool]$binding.Enabled }; Revision = $revision }
    }
    if (@($guides).Count -gt 0 -and @($bindingsOut).Count -eq 0 -and @($playlists).Count -eq 1) {
        $playlistId = [string]$playlists[0].SourceId
        $bindingsOut = @($guides | ForEach-Object {
            $guideId = [string]$_.SourceId
            [ordered]@{ BindingId = Get-ChannelForgeDomainHash -Domain 'source-binding/v2' -InputObject ([ordered]@{ GuideId = $guideId; PlaylistIds = @($playlistId); AppliesToAll = $false; Revision = 1 }); GuideId = $guideId; PlaylistIds = @($playlistId); AppliesToAll = $false; Enabled = $true; Revision = 1 }
        })
    }
    $existing = Get-ChannelForgeSourceEnrollmentIntegrity -RepositoryRoot $RepositoryRoot
    $enrollment = [ordered]@{
        Version = $script:ChannelForgeSourceEnrollmentVersion; SourceSetId = Get-ChannelForgeDomainHash -Domain 'source-set-id/v2' -InputObject 'browser-local-managed-sources'; EnrollmentId = Get-ChannelForgeDomainHash -Domain 'source-enrollment-id/v1' -InputObject 'browser-local-managed-sources'
        Status = 'Valid'; GuideMode = if (@($guides).Count -eq 0) { 'NoGuide' } else { 'XMLTV' }; Playlists = @($playlists | Sort-Object Priority, OrderKey, SourceId); Guides = @($guides | Sort-Object Priority, OrderKey, SourceId); Bindings = @($bindingsOut | Sort-Object GuideId, BindingId)
        AcceptedWorkflow = [ordered]@{ GenerationManifestHash = $AcceptedGenerationManifestHash; AcceptedStateHash = $AcceptedStateHash; AcceptedOutputManifestHash = $AcceptedOutputManifestHash }; RefreshPolicy = [ordered]@{ Mode = 'Manual'; AutoAccept = $false }; LastRefreshStatus = 'saved'
        CreatedAtUtc = if ($null -eq $existing.Enrollment) { $now } else { [string]$existing.Enrollment.CreatedAtUtc }; UpdatedAtUtc = $now
    }
    Assert-ChannelForgeSourceEnrollmentV2Integrity -Record ([pscustomobject]$enrollment)
    $enrollment.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment ([pscustomobject]$enrollment)
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path $paths.EnrollmentPath -Value ([pscustomobject]$enrollment) -AllowedRoot $paths.StateRoot
    return [pscustomobject]$enrollment
}

function Update-ChannelForgeSourceEnrollmentRefreshState {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateSet('up-to-date', 'changes-found')][string]$RefreshStatus,
        [AllowEmptyCollection()][object[]]$SourceUpdates = @()
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $enrollment = Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $RepositoryRoot
    foreach ($update in @($SourceUpdates)) {
        $sourceId = [string]$update.SourceId
        $source = @($enrollment.Playlists + $enrollment.Guides | Where-Object { [string]$_.SourceId -eq $sourceId }) | Select-Object -First 1
        if ($null -eq $source) { continue }
        if ($null -eq $source.Refresh) { $source.Refresh = [ordered]@{} }
        $source.Refresh.State = [string]$update.State
        $source.Refresh.LastValidatedAtUtc = if ($null -eq $update.LastValidatedAtUtc) {
            (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        } else { [string]$update.LastValidatedAtUtc }
        if ($update.PSObject.Properties.Name -contains 'ContentHash' -and
            -not [string]::IsNullOrWhiteSpace([string]$update.ContentHash)) {
            $source.Refresh.ContentHash = [string]$update.ContentHash
        }
    }
    $enrollment.LastRefreshStatus = $RefreshStatus
    $enrollment.UpdatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $enrollment.EnrollmentHash = Get-ChannelForgeSourceEnrollmentHash -Enrollment $enrollment
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path $paths.EnrollmentPath -Value $enrollment -AllowedRoot $paths.StateRoot
    return [pscustomobject]$enrollment
}
