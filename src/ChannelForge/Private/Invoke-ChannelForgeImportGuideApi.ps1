function Get-ChannelForgeImportHandleLifetime {
    # How long a guide handle works.
    return [TimeSpan]::FromMinutes(15)
}

function Test-ChannelForgeImportGuideName {
    # True for a plain file name (no folder part) that ends in .xml or .xml.gz.
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -ne [IO.Path]::GetFileName($Name) -or $Name -match '[\\/:\x00-\x1f]') { return $false }
    return $Name -match '\.xml(\.gz)?$'
}

function Get-ChannelForgeImportDisplayName {
    # A name that is safe to show: letters, digits, space, dot, dash, underscore and brackets only, at most 80 characters.
    param([Parameter(Mandatory)][string]$Name)
    $safe = [regex]::Replace($Name, '[^A-Za-z0-9 ._()\[\]-]', '_')
    if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80) }
    return $safe
}

function Test-ChannelForgeImportRoot {
    # True when the root is a real folder and not a link or reparse point.
    param([AllowNull()][string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root) -or -not [IO.Path]::IsPathRooted($Root)) { return $false }
    $item = Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
}

function Get-ChannelForgeImportGuideFile {
    <#
    .SYNOPSIS
        The guide files directly in the import folder (no subfolders, no links), by name, at most 200.
    #>
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-ChannelForgeImportRoot -Root $Root)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -File -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and (Test-ChannelForgeImportGuideName -Name $_.Name) } |
            Sort-Object -Property Name -CaseSensitive |
            Select-Object -First 200)
}

function New-ChannelForgeImportHandleTable {
    <#
    .SYNOPSIS
        Replaces the handle table of a session with fresh random handles, one per file. Returns handle, display name and size.
    .DESCRIPTION
        The table lives on the session object, so sign-out, idle timeout and other sessions drop or never see it.
        The file name is kept server-side only and is never returned.
    #>
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$File, [Parameter(Mandatory)][datetime]$Now)
    $table = @{}
    $guides = @(foreach ($file in $File) {
        $handle = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).Replace('+', '-').Replace('/', '_')
        $table[$handle] = [pscustomobject]@{ FileName = $file.Name; ExpiresUtc = $Now + (Get-ChannelForgeImportHandleLifetime) }
        [ordered]@{ Handle = $handle; Name = (Get-ChannelForgeImportDisplayName -Name $file.Name); Size = [long]$file.Length }
    })
    $Session.Handles = $table
    return , $guides
}

function Resolve-ChannelForgeImportHandle {
    <#
    .SYNOPSIS
        The full path of the file a handle points to, or $null. Only the server uses the path; it is never sent to the browser.
    .DESCRIPTION
        $null for an unknown, expired, other-session or signed-out handle, and when the file is gone, outside the root, or a link.
    #>
    param([AllowNull()]$Session, [AllowNull()][string]$Handle, [AllowNull()][string]$ImportRoot, [datetime]$Now = [datetime]::UtcNow)
    if ($null -eq $Session -or [string]::IsNullOrEmpty($Handle) -or -not (Test-ChannelForgeImportRoot -Root $ImportRoot)) { return $null }
    $entry = $Session.Handles[$Handle]
    if ($null -eq $entry) { return $null }
    if ($Now -gt $entry.ExpiresUtc) { $Session.Handles.Remove($Handle); return $null }
    if (-not (Test-ChannelForgeImportGuideName -Name $entry.FileName)) { return $null }
    $root = [IO.Path]::GetFullPath($ImportRoot)
    $full = [IO.Path]::GetFullPath((Join-Path $root $entry.FileName))
    if ([IO.Path]::GetDirectoryName($full) -ne $root.TrimEnd('\', '/')) { return $null }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
    return $full
}

function Invoke-ChannelForgeImportGuideApi {
    <#
    .SYNOPSIS
        GET /api/import-guides for a signed-in session: the guides in the server's import folder, each with a handle, a safe name and a size.
    .DESCRIPTION
        Every call replaces the session's earlier handles. Handles last 15 minutes. No path or time is returned.
    #>
    param([AllowNull()]$Session, [AllowNull()][string]$ImportRoot, [datetime]$Now = [datetime]::UtcNow)
    if ($null -eq $Session -or [string]::IsNullOrWhiteSpace($ImportRoot)) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Available = $false; Guides = @() }
    }
    if (-not (Test-ChannelForgeImportRoot -Root $ImportRoot)) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Available = $false; Guides = @(); Message = 'ChannelForge could not read the import folder.' }
    }
    $guides = New-ChannelForgeImportHandleTable -Session $Session -File @(Get-ChannelForgeImportGuideFile -Root $ImportRoot) -Now $Now
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Available = $true; Guides = $guides }
}
