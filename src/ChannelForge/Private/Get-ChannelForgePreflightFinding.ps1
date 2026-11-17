function New-ChannelForgePreflightFinding {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Fail', 'Unknown')][string]$Status,
        [Parameter(Mandatory)][string]$Observed,
        [Parameter(Mandatory)][string]$Expected,
        [string]$NotTested = 'Nothing else.',
        [string]$NextStep = 'No action needed.'
    )
    $severity = switch ($Status) { 'Fail' { 'Error' } 'Unknown' { 'Warning' } default { 'Info' } }
    [pscustomobject][ordered]@{
        Check = $Check; Root = $Root; Status = $Status; Severity = $severity
        Observed = $Observed; Expected = $Expected; NotTested = $NotTested; NextStep = $NextStep
    }
}

function Get-ChannelForgePreflightDisplayRoot {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RepositoryRoot)
    if (-not (Test-ChannelForgeWritePath -Path $Path -AllowedRoot $RepositoryRoot)) { return '[outside the project]' }
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($RepositoryRoot), [IO.Path]::GetFullPath($Path))
    return $relative -replace '\\', '/'
}

function Test-ChannelForgePreflightCanary {
    # Writes one tiny file in <root>/.preflight, reads it back, then removes only what it made.
    param([Parameter(Mandatory)][string]$Path)
    $folder = Join-Path $Path '.preflight'
    if ([IO.Directory]::Exists($folder) -or [IO.File]::Exists($folder)) {
        return [pscustomobject]@{ Ok = $false; Detail = 'A ".preflight" item already exists, so no test file was written.' }
    }
    $file = Join-Path $folder ('canary-' + [guid]::NewGuid().ToString('N') + '.txt')
    $ok = $false; $detail = ''
    try {
        [void][IO.Directory]::CreateDirectory($folder)
        [IO.File]::WriteAllText($file, 'channelforge-preflight')
        $ok = [IO.File]::ReadAllText($file) -ceq 'channelforge-preflight'
        if (-not $ok) { $detail = 'The test file did not read back the same.' }
    }
    catch { $detail = 'The folder could not be written.' }
    finally {
        try { if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) } } catch { $null = $_ }
        try { if ([IO.Directory]::Exists($folder)) { [IO.Directory]::Delete($folder, $false) } } catch { $null = $_ }
    }
    if ([IO.Directory]::Exists($folder)) { return [pscustomobject]@{ Ok = $false; Detail = 'The test file or its ".preflight" folder could not be removed.' } }
    return [pscustomobject]@{ Ok = $ok; Detail = $detail }
}

function Get-ChannelForgePreflightRootFinding {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][long]$MinimumFreeBytes
    )
    $display = Get-ChannelForgePreflightDisplayRoot -Path $Path -RepositoryRoot $RepositoryRoot
    $rest = 'Reparse point, write test, free space.'
    $new = { param($check, $status, $observed, $expected, $notTested, $next)
        New-ChannelForgePreflightFinding -Check "$Name $check" -Root $display -Status $status -Observed $observed -Expected $expected -NotTested $notTested -NextStep $next }

    if (-not [IO.Directory]::Exists($Path)) {
        return & $new 'exists' 'Fail' 'The folder is missing.' 'The folder exists.' $rest 'Create this folder, then run the check again.'
    }
    if (-not (Test-ChannelForgeWritePath -Path $Path -AllowedRoot $RepositoryRoot)) {
        return & $new 'inside project' 'Fail' 'The folder is outside the project.' 'The folder is inside the project.' $rest 'Choose a folder inside the project folder.'
    }
    try { Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $Path | Out-Null }
    catch {
        return & $new 'no link' 'Fail' 'The folder or a parent is a link or is not safe to use.' 'A normal folder, not a symlink or junction.' 'Write test, free space.' 'Use a real folder instead of a link.'
    }
    $canary = Test-ChannelForgePreflightCanary -Path $Path
    $writable = if ($canary.Ok) {
        & $new 'writable' 'Pass' 'A test file was written, read back and removed.' 'The folder is writable and cleanup works.' 'Permissions on files that already exist.' 'No action needed.'
    }
    else {
        & $new 'writable' 'Fail' $canary.Detail 'The folder is writable and cleanup works.' 'Free space.' 'Check that you can create and delete files in this folder, and remove any leftover ".preflight" folder by hand.'
    }
    $floorMb = [long]($MinimumFreeBytes / 1MB)
    try {
        $free = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)))).AvailableFreeSpace
        $space = if ($free -ge $MinimumFreeBytes) {
            & $new 'free space' 'Pass' ('{0} MB free.' -f [long]($free / 1MB)) "At least $floorMb MB free." 'Space needed by one specific build.' 'No action needed.'
        }
        else {
            & $new 'free space' 'Fail' ('{0} MB free.' -f [long]($free / 1MB)) "At least $floorMb MB free." 'Space needed by one specific build.' 'Free up disk space on this drive.'
        }
    }
    catch {
        $space = & $new 'free space' 'Unknown' 'Free space could not be read.' "At least $floorMb MB free." 'Free space.' 'Check the free space on this drive by hand.'
    }
    return @(
        (& $new 'exists' 'Pass' 'The folder exists.' 'The folder exists.' 'Nothing else.' 'No action needed.'),
        (& $new 'inside project' 'Pass' 'The folder is inside the project.' 'The folder is inside the project.' 'Nothing else.' 'No action needed.'),
        (& $new 'no link' 'Pass' 'The folder is a normal folder.' 'A normal folder, not a symlink or junction.' 'Nothing else.' 'No action needed.'),
        $writable,
        $space
    )
}

function Get-ChannelForgePreflightVolumeFinding {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    $make = { param($status, $observed, $next)
        New-ChannelForgePreflightFinding -Check 'staging and final on one volume' -Root 'state' -Status $status -Observed $observed -Expected 'Staging and final folders are on the same volume.' -NotTested 'Whether the file system supports atomic replace.' -NextStep $next }
    try {
        $null = Initialize-ChannelForgeGenerationStore
        Assert-ChannelForgeGenerationSameVolume -RepositoryRoot $paths.Staging -Paths @($paths.Generations)
        return & $make 'Pass' 'Staging and final folders are on the same volume.' 'No action needed.'
    }
    catch {
        if ($_.Exception.Message -like '*another volume*') {
            return & $make 'Fail' 'Staging and final folders are on different volumes.' 'Move the state folder so staging and final output share one drive.'
        }
        return & $make 'Unknown' 'The volumes could not be compared.' 'Check by hand that the state folder is on one drive.'
    }
}

function Get-ChannelForgePreflightPublishedFinding {
    # Reuses the accepted-state reader, which re-hashes the published files against their manifest.
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    $make = { param($name, $status, $observed, $next)
        New-ChannelForgePreflightFinding -Check "published $name matches manifest" -Root 'state' -Status $status -Observed $observed -Expected 'The file hash equals the manifest hash.' -NotTested 'Playlist content, guide binding.' -NextStep $next }
    $unknown = 'No published output was found yet.'
    $snapshot = $null; $problem = $null
    if ([IO.File]::Exists($paths.Current)) {
        try { $snapshot = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths }
        catch { $problem = [string]$_.Exception.Message }
    }
    $rebuild = 'Rebuild and accept the lineup again; do not edit published files by hand.'
    if ($null -ne $problem) {
        $m3u = if ($problem -like '*M3U hash mismatch*') { & $make 'M3U' 'Fail' 'The published file changed after it was accepted.' $rebuild } else { & $make 'M3U' 'Unknown' 'The published files could not be verified.' 'Run the accepted-state recovery check.' }
        $xml = if ($problem -like '*XMLTV hash mismatch*') { & $make 'XMLTV' 'Fail' 'The published file changed after it was accepted.' $rebuild } else { & $make 'XMLTV' 'Unknown' 'The published files could not be verified.' 'Run the accepted-state recovery check.' }
        return @($m3u, $xml)
    }
    if ($null -eq $snapshot) {
        return @((& $make 'M3U' 'Unknown' $unknown 'Accept a lineup first.'), (& $make 'XMLTV' 'Unknown' $unknown 'Accept a lineup first.'))
    }
    $xmlFinding = if ($null -eq $snapshot.XMLTV) { & $make 'XMLTV' 'Unknown' 'The accepted lineup has no guide file.' 'Accept a lineup with a guide if you need one.' } else { & $make 'XMLTV' 'Pass' 'The file matches.' 'No action needed.' }
    return @((& $make 'M3U' 'Pass' 'The file matches.' 'No action needed.'), $xmlFinding)
}
