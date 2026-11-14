function Read-ChannelForgeSourceSetFileBytes {
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'SOURCE_ENROLLMENT_INVALID: the source file was not found.' }
    $limits = Get-ChannelForgeWebProposalLimits
    $maxBytes = if ($Kind -eq 'M3U') { $limits.MaxM3UBytes } else { $limits.MaxXMLTVBytes }
    $length = (Get-Item -LiteralPath $Path -Force).Length
    if ($length -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: the source file is empty.' }
    if ($length -gt $maxBytes) { throw 'SOURCE_ENROLLMENT_INVALID: the source file is too large.' }
    try {
        if ($Kind -eq 'M3U') {
            if (@(Import-ChannelForgeM3UPlaylist -Path $Path -Provider 'candidate').Count -eq 0) { throw 'no channels were found.' }
        }
        else { $null = Import-ChannelForgeXmltvSource -Path $Path -SourceId 'candidate' }
    }
    catch { throw "SOURCE_ENROLLMENT_INVALID: the $Kind source file is not valid. $($_.Exception.Message)" }
    return , [System.IO.File]::ReadAllBytes($Path)
}

function Get-ChannelForgeSourceSetUrlBytes {
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$Url
    )
    # The link is a secret. Every message below is fixed text; never add the link or a transport message to it.
    $parsed = $null
    if (-not (Test-ChannelForgeSourceUrl -Url $Url) -or -not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$parsed) -or -not [string]::IsNullOrEmpty($parsed.Query) -or -not [string]::IsNullOrEmpty($parsed.Fragment)) {
        throw 'SOURCE_ENROLLMENT_INVALID: the link must be a public HTTPS address with no user info, query or fragment. Tokenized or credential-bearing links are not supported.'
    }
    $limits = Get-ChannelForgeWebProposalLimits
    try { $bytes = [byte[]](Get-ChannelForgeRemoteSourceBytes -Kind $Kind -Url $Url -MaxBytes $(if ($Kind -eq 'M3U') { $limits.MaxM3UBytes } else { $limits.MaxXMLTVBytes })) }
    catch { throw 'SOURCE_ENROLLMENT_INVALID: the source could not be fetched, or it was empty or too large.' }
    # The parsers read files, so the fetched bytes get the same file check through a short-lived temp file.
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N') + $(if ($Kind -eq 'M3U') { '.m3u' } else { '.xml' }))
    try {
        [System.IO.File]::WriteAllBytes($temp, $bytes)
        return , (Read-ChannelForgeSourceSetFileBytes -Kind $Kind -Path $temp)
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Get-ChannelForgeSourceSetEditBase {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [switch]$AllowChanged)
    $integrity = Get-ChannelForgeSourceEnrollmentIntegrity -RepositoryRoot $RepositoryRoot
    if ($integrity.State -notin @('Valid', 'Missing') -and -not ($AllowChanged -and $integrity.State -eq 'Changed')) { throw "SOURCE_ENROLLMENT_UNAVAILABLE: $($integrity.Reason)" }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $set = $integrity.Enrollment
    $toSource = {
        param($record)
        $source = [ordered]@{
            Kind = [string]$record.Kind; SourceKind = [string]$record.SourceKind; SourceId = [string]$record.SourceId
            Label = [string]$record.Label; Priority = [int]$record.Priority; Enabled = [bool]$record.Enabled
            Provenance = $record.Provenance; Url = $record.Url; ManagedPath = [string]$record.ManagedPath; ContentHash = [string]$record.ContentHash
        }
        if (-not [string]::IsNullOrWhiteSpace($source.ManagedPath)) {
            $path = Assert-ChannelForgeSourceEnrollmentPath -Path (Join-Path $paths.RepositoryRoot ($source.ManagedPath -replace '/', '\')) -AllowedRoot $paths.ManagedSourceRoot
            $source.Bytes = [System.IO.File]::ReadAllBytes($path)
        }
        return [pscustomobject]$source
    }
    $toBinding = {
        param($binding)
        [pscustomobject][ordered]@{
            GuideId = [string]$binding.GuideId; PlaylistIds = @($binding.PlaylistIds | ForEach-Object { [string]$_ }); AppliesToAll = [bool]$binding.AppliesToAll
            ExplicitlyUnbound = $null -ne $binding.PSObject.Properties['ExplicitlyUnbound'] -and [bool]$binding.ExplicitlyUnbound
            Revision = [int]$binding.Revision; Enabled = [bool]$binding.Enabled
        }
    }
    return [pscustomobject][ordered]@{
        Playlists = if ($null -eq $set) { @() } else { @($set.Playlists | ForEach-Object { & $toSource $_ }) }
        Guides = if ($null -eq $set) { @() } else { @($set.Guides | ForEach-Object { & $toSource $_ }) }
        Bindings = if ($null -eq $set) { @() } else { @($set.Bindings | ForEach-Object { & $toBinding $_ }) }
        AcceptedWorkflow = if ($null -eq $set) { $null } else { $set.AcceptedWorkflow }
    }
}

function Find-ChannelForgeSourceSetSource {
    param(
        [Parameter(Mandatory)]$Base,
        [string]$SourceId,
        [string]$Label,
        [string]$Kind
    )
    $found = @(@($Base.Playlists) + @($Base.Guides) | Where-Object {
        if (-not [string]::IsNullOrEmpty($SourceId)) { $_.SourceId -ceq $SourceId }
        else { $_.Label -ieq $Label -and ([string]::IsNullOrEmpty($Kind) -or $_.Kind -ceq $Kind) }
    })
    if ($found.Count -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: no saved source matches.' }
    if ($found.Count -gt 1) { throw 'SOURCE_ENROLLMENT_INVALID: more than one saved source matches. Use -Kind or -SourceId.' }
    return $found[0]
}

function Save-ChannelForgeSourceSetEdit {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Base,
        [Parameter(Mandatory)][object[]]$PlaylistSources,
        [AllowEmptyCollection()][object[]]$GuideSources = @(),
        [AllowEmptyCollection()][object[]]$Bindings = @()
    )
    $workflow = $Base.AcceptedWorkflow
    return Write-ChannelForgeSourceSet -RepositoryRoot $RepositoryRoot -PlaylistSources $PlaylistSources -GuideSources $GuideSources -Bindings $Bindings -PreserveUnboundGuides `
        -AcceptedGenerationManifestHash $(if ($null -eq $workflow) { $null } else { $workflow.GenerationManifestHash }) `
        -AcceptedStateHash $(if ($null -eq $workflow) { $null } else { $workflow.AcceptedStateHash }) `
        -AcceptedOutputManifestHash $(if ($null -eq $workflow) { $null } else { $workflow.AcceptedOutputManifestHash })
}

function Remove-ChannelForgeManagedSourceSnapshot {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ManagedPath
    )
    if ($ManagedPath -cnotmatch '^state/managed-sources/[0-9a-f]{64}\.(m3u|xml)$') { throw 'FAIL_CLOSED: managed source reference is invalid.' }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $path = Assert-ChannelForgeSourceEnrollmentPath -Path (Join-Path $paths.RepositoryRoot ($ManagedPath -replace '/', '\')) -AllowedRoot $paths.ManagedSourceRoot -AllowMissingLeaf
    if ([System.IO.File]::Exists($path)) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
}
