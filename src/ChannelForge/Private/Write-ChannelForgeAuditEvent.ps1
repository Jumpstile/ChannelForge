function Get-ChannelForgeAuditPath {
    # audit.jsonl sits beside users.json in the config folder.
    param([Parameter(Mandatory)][string]$ConfigRoot)
    return Join-Path $ConfigRoot 'audit.jsonl'
}

function Write-ChannelForgeAuditWarningOnce {
    # One plain line per run, so a broken audit file is noticed but never floods the console.
    param([Parameter(Mandatory)][string]$Message)
    if ($script:ChannelForgeAuditWarned) { return }
    $script:ChannelForgeAuditWarned = $true
    Write-Warning $Message
}

function Get-ChannelForgeAuditPerson {
    <#
    .SYNOPSIS
        Id and Name of a person for an event: the user with this id or name (any state), else 'unknown'.
    .DESCRIPTION
        A name typed by a stranger that matches no user is never kept; the event says 'unknown'.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot, [string]$UserId = '', [string]$Name = '')
    $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
    $found = $null
    if ($store.Status -eq 'Ok') {
        $found = @($store.Users | Where-Object { ($UserId -ne '' -and $_.Id -ceq $UserId) -or ($UserId -eq '' -and $Name.Trim() -ne '' -and $_.Name -ieq $Name.Trim()) })[0]
    }
    if ($null -ne $found) { return [pscustomobject]@{ Id = [string]$found.Id; Name = [string]$found.Name } }
    return [pscustomobject]@{ Id = $UserId; Name = 'unknown' }
}

function Write-ChannelForgeAuditEvent {
    <#
    .SYNOPSIS
        Appends one line to audit.jsonl: who did what, to whom, from where, and how it ended. Never throws.
    .DESCRIPTION
        Actor and Target are objects with Id and Name (a users.json record works). Names are stored as text, so history stays
        readable after a delete. Pass only plain words in Reason. Never pass a password, code, token or session id.
        A write that fails gives one warning per run and the caller carries on.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][string]$EventName,
        [ValidateSet('ok', 'refused')][string]$Result = 'ok',
        $Actor = $null,
        $Target = $null,
        [string]$Reason = '',
        [string]$RemoteAddress = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    try {
        $line = [ordered]@{
            TimeUtc       = $Now.ToUniversalTime().ToString('yyyy-MM-dd\THH:mm:ss\Z', [System.Globalization.CultureInfo]::InvariantCulture)
            Event         = $EventName
            ActorUserId   = [string]$Actor.Id
            ActorName     = [string]$Actor.Name
            TargetUserId  = [string]$Target.Id
            TargetName    = [string]$Target.Name
            Result        = $Result
            RemoteAddress = $RemoteAddress
            Reason        = $Reason
        }
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($line | ConvertTo-Json -Compress) + "`n")
        $path = Get-ChannelForgeAuditPath -ConfigRoot $ConfigRoot
        Assert-ChannelForgeSourceEnrollmentDirectory -Path $ConfigRoot -Create | Out-Null
        Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $ConfigRoot -AllowMissingLeaf | Out-Null
        Add-ChannelForgeAuditBytes -Path $path -Bytes $bytes
        if ($null -eq $script:ChannelForgeAuditAppends) { $script:ChannelForgeAuditAppends = @{} }
        $count = 1 + [int]$script:ChannelForgeAuditAppends[$path]
        $script:ChannelForgeAuditAppends[$path] = $count
        if ($count -ge 100) {
            $script:ChannelForgeAuditAppends[$path] = 0
            Invoke-ChannelForgeAuditTrim -ConfigRoot $ConfigRoot -Now $Now
        }
    }
    catch { Write-ChannelForgeAuditWarningOnce -Message 'ChannelForge could not write to its audit trail. Sign-in and user changes carry on.' }
}

function ConvertFrom-ChannelForgeAuditLine {
    # The event on one line, or $null when the line is not a JSON object with a TimeUtc stamp.
    param([AllowEmptyString()][string]$Line)
    try {
        $entry = $Line | ConvertFrom-Json -DateKind String -ErrorAction Stop
        if ($entry -is [pscustomobject] -and $entry.TimeUtc -is [string] -and $entry.TimeUtc -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z') { return $entry }
    }
    catch { $null = $_ }
    return $null
}

function Read-ChannelForgeAuditLine {
    # Every non-blank line of audit.jsonl in file order; none when the file is missing. Bad bytes never throw.
    param([Parameter(Mandatory)][string]$ConfigRoot)
    $path = Get-ChannelForgeAuditPath -ConfigRoot $ConfigRoot
    if (-not [System.IO.File]::Exists($path)) { return @() }
    return @([System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false)) | Where-Object { $_.Trim() -ne '' })
}

function Invoke-ChannelForgeAuditTrim {
    <#
    .SYNOPSIS
        Keeps only events newer than 12 months and at most the newest 5,000 lines. Never throws.
    .DESCRIPTION
        Writes a temp file and replaces audit.jsonl in one step, so a failed trim leaves the old file whole.
        A line that is not a good event is dropped only when it falls outside the 5,000-line limit.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot, [datetime]$Now = [datetime]::UtcNow, [int]$MaxLines = 5000)
    try {
        $lines = Read-ChannelForgeAuditLine -ConfigRoot $ConfigRoot
        $cutoff = $Now.ToUniversalTime().AddMonths(-12).ToString('yyyy-MM-dd\THH:mm:ss\Z', [System.Globalization.CultureInfo]::InvariantCulture)
        $keep = @($lines | Where-Object { $entry = ConvertFrom-ChannelForgeAuditLine -Line $_; $null -eq $entry -or [string]::CompareOrdinal($entry.TimeUtc, $cutoff) -ge 0 })
        if ($keep.Count -gt $MaxLines) { $keep = @($keep[($keep.Count - $MaxLines)..($keep.Count - 1)]) }
        if ($keep.Count -eq $lines.Count) { return }
        $path = Get-ChannelForgeAuditPath -ConfigRoot $ConfigRoot
        if ($keep.Count -eq 0) { [System.IO.File]::Delete($path); return }
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes((($keep -join "`n") + "`n"))
        Write-ChannelForgeSourceEnrollmentAtomicBytes -Path $path -Bytes $bytes -AllowedRoot $ConfigRoot
    }
    catch { Write-ChannelForgeAuditWarningOnce -Message 'ChannelForge could not trim its audit trail. The file was left as it was.' }
}

function Invoke-ChannelForgeAuditApi {
    <#
    .SYNOPSIS
        GET /api/audit for a signed-in Admin: newest first. ?user=<id or name> filters; ?limit= is 200 by default, 500 at most.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ConfigRoot)
    $query = [System.Web.HttpUtility]::ParseQueryString([string]($Path -split '\?', 2)[1])
    $user = [string]$query['user']
    $limit = 200
    if ($null -ne $query['limit'] -and -not [int]::TryParse($query['limit'], [ref]$limit)) { $limit = 200 }
    $limit = [Math]::Min(500, [Math]::Max(1, $limit))
    try { $lines = Read-ChannelForgeAuditLine -ConfigRoot $ConfigRoot }
    catch { return New-ChannelForgeUsersApiError -StatusCode 500 -Code 'audit-unreadable' -Message 'The audit trail could not be read.' }
    $events = [System.Collections.Generic.List[object]]::new()
    for ($i = $lines.Count - 1; $i -ge 0 -and $events.Count -lt $limit; $i--) {
        $entry = ConvertFrom-ChannelForgeAuditLine -Line $lines[$i]
        if ($null -eq $entry) { continue }
        if ($user -ne '' -and $user -cne $entry.ActorUserId -and $user -cne $entry.TargetUserId -and $user -ine $entry.ActorName -and $user -ine $entry.TargetName) { continue }
        $events.Add($entry)
    }
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Events = $events.ToArray() }
}

function Add-ChannelForgeAuditBytes {
    # Appends bytes to the file. A last line cut off by a crash gets its newline first, so the new event is not glued to it.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
    try {
        $null = $stream.Seek(0, [System.IO.SeekOrigin]::End)
        if ($stream.Length -gt 0) {
            $null = $stream.Seek(-1, [System.IO.SeekOrigin]::End)
            if ($stream.ReadByte() -ne 10) { $stream.WriteByte(10) }
        }
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}
