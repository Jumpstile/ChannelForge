Set-StrictMode -Version 2.0

$script:MonitorOutboxSchemaVersion = 1
$script:MonitorFindingSchemaVersion = 1
$script:MonitorApiBaseUri = 'https://api.github.com'
$script:MonitorMaxPages = 20
$script:MonitorMaxErrorLength = 1000

function Assert-MonitorRepositoryName {
    param([Parameter(Mandatory)][string]$Repository)
    if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw 'Monitor repository must be an owner/name pair.'
    }
}

function Assert-MonitorSpoolRoot {
    param([Parameter(Mandatory)][string]$SpoolRoot)
    if ([string]::IsNullOrWhiteSpace($SpoolRoot)) {
        throw 'Monitor spool root is required.'
    }
    return [IO.Path]::GetFullPath($SpoolRoot)
}

function Get-MonitorUtcNow {
    return [DateTime]::UtcNow
}

function ConvertTo-MonitorCanonicalValue {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $ordered[$key] = ConvertTo-MonitorCanonicalValue -Value $Value[$key]
        }
        return $ordered
    }

    if ($Value -is [PSCustomObject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $ordered[$property.Name] = ConvertTo-MonitorCanonicalValue -Value $property.Value
        }
        return $ordered
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            [void]$items.Add((ConvertTo-MonitorCanonicalValue -Value $item))
        }
        return ,$items.ToArray()
    }

    return $Value
}

function ConvertTo-MonitorCanonicalJson {
    param([AllowNull()]$Value)
    $normalized = ConvertTo-MonitorCanonicalValue -Value $Value
    return ($normalized | ConvertTo-Json -Depth 20 -Compress)
}

function Get-MonitorSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $digest = $algorithm.ComputeHash($bytes)
        return ([BitConverter]::ToString($digest) -replace '-', '').ToUpperInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-MonitorFindingIdentity {
    param([Parameter(Mandatory)]$Finding)

    return [ordered]@{
        schemaVersion      = $script:MonitorFindingSchemaVersion
        monitorId          = [string]$Finding.monitorId
        repository         = [string]$Finding.repository
        targetIssueNumber  = [int]$Finding.targetIssueNumber
        findingType        = [string]$Finding.findingType
        title              = [string]$Finding.title
        body               = [string]$Finding.body
        sourceIds          = @($Finding.sourceIds | ForEach-Object { [string]$_ } | Sort-Object)
        confidence         = if ($Finding.PSObject.Properties['confidence']) { [string]$Finding.confidence } else { $null }
        evidence           = ConvertTo-MonitorCanonicalValue -Value $Finding.evidence
    }
}

function Get-MonitorFindingHash {
    param([Parameter(Mandatory)]$Finding)
    return Get-MonitorSha256 -Text (ConvertTo-MonitorCanonicalJson -Value (Get-MonitorFindingIdentity -Finding $Finding))
}

function Get-MonitorIdempotencyKey {
    param([Parameter(Mandatory)]$Finding)
    return Get-MonitorFindingHash -Finding $Finding
}

function New-MonitorFinding {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure record constructor; it does not mutate external state.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MonitorId,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$TargetIssueNumber,
        [Parameter(Mandatory)][string]$FindingType,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [string[]]$SourceIds = @(),
        [AllowNull()][object]$Evidence = $null,
        [ValidateSet('Confirmed','High','Medium','Low','ReviewNeeded','Unknown')][string]$Confidence = 'ReviewNeeded',
        [DateTime]$ObservedAtUtc = [DateTime]::MinValue
    )

    Assert-MonitorRepositoryName -Repository $Repository
    if ($MonitorId -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Monitor id contains unsafe characters.' }
    if ($FindingType -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Finding type contains unsafe characters.' }
    if ([string]::IsNullOrWhiteSpace($Title) -or $Title.Length -gt 240) { throw 'Monitor finding title is empty or too long.' }
    if ([string]::IsNullOrWhiteSpace($Body) -or $Body.Length -gt 20000) { throw 'Monitor finding body is empty or too long.' }
    if ($ObservedAtUtc -eq [DateTime]::MinValue) { $ObservedAtUtc = Get-MonitorUtcNow }

    return [pscustomobject][ordered]@{
        schemaVersion     = $script:MonitorFindingSchemaVersion
        monitorId         = $MonitorId
        repository        = $Repository
        targetIssueNumber = $TargetIssueNumber
        findingType       = $FindingType
        title             = $Title
        body              = $Body
        sourceIds         = @($SourceIds | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        confidence        = $Confidence
        evidence          = if ($null -eq $Evidence) { [ordered]@{} } else { $Evidence }
        observedAtUtc     = $ObservedAtUtc.ToUniversalTime().ToString('o')
    }
}

function New-MonitorOutboxItem {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure record constructor; it does not mutate external state.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Finding, [DateTime]$CreatedAtUtc = [DateTime]::MinValue)

    if ($CreatedAtUtc -eq [DateTime]::MinValue) { $CreatedAtUtc = Get-MonitorUtcNow }
    $key = Get-MonitorIdempotencyKey -Finding $Finding
    return [pscustomobject][ordered]@{
        schemaVersion       = $script:MonitorOutboxSchemaVersion
        idempotencyKey      = $key
        findingHash          = Get-MonitorFindingHash -Finding $Finding
        finding              = $Finding
        status               = 'pending'
        attemptCount         = 0
        nextAttemptAtUtc     = $CreatedAtUtc.ToUniversalTime().ToString('o')
        lastError            = $null
        recordedCommentId    = $null
        recordedAtUtc        = $null
    }
}

function Initialize-MonitorOutbox {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SpoolRoot)
    $root = Assert-MonitorSpoolRoot -SpoolRoot $SpoolRoot
    foreach ($name in @('pending','recorded','runs')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $root $name))
    }
    return $root
}

function Write-MonitorAtomicText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)

    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($full)
    [void][IO.Directory]::CreateDirectory($parent)
    $temporary = $full + '.tmp.' + [Guid]::NewGuid().ToString('N')
    $stream = $null
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null

        if ([IO.File]::Exists($full)) {
            try {
                [IO.File]::Replace($temporary, $full, $null, $true)
            } catch {
                Move-Item -LiteralPath $temporary -Destination $full -Force -ErrorAction Stop
            }
        } else {
            [IO.File]::Move($temporary, $full)
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function ConvertTo-MonitorJsonText {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 20)
}

function Assert-MonitorOutboxItem {
    param([Parameter(Mandatory)]$Item)
    if ([int]$Item.schemaVersion -ne $script:MonitorOutboxSchemaVersion) { throw 'Unsupported monitor outbox schema.' }
    if ([string]$Item.idempotencyKey -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid monitor outbox idempotency key.' }
    if ([string]$Item.status -notin @('pending','recorded')) { throw 'Invalid monitor outbox status.' }
    if ($null -eq $Item.finding) { throw 'Monitor outbox finding is missing.' }
    $expectedKey = Get-MonitorIdempotencyKey -Finding $Item.finding
    $expectedHash = Get-MonitorFindingHash -Finding $Item.finding
    if (-not [string]::Equals($expectedKey, [string]$Item.idempotencyKey, [StringComparison]::OrdinalIgnoreCase)) { throw 'Monitor outbox idempotency key mismatch.' }
    if (-not [string]::Equals($expectedHash, [string]$Item.findingHash, [StringComparison]::OrdinalIgnoreCase)) { throw 'Monitor outbox finding hash mismatch.' }
}

function Read-MonitorOutboxFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw 'Monitor outbox item does not exist.' }
    $item = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-MonitorOutboxItem -Item $item
    return $item
}

function Write-MonitorOutboxItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SpoolRoot, [Parameter(Mandatory)]$Item)
    Assert-MonitorOutboxItem -Item $Item
    $root = Initialize-MonitorOutbox -SpoolRoot $SpoolRoot
    $fileName = $Item.idempotencyKey.ToUpperInvariant() + '.json'
    $recordedPath = Join-Path (Join-Path $root 'recorded') $fileName
    if ([IO.File]::Exists($recordedPath)) {
        $recorded = Read-MonitorOutboxFile -Path $recordedPath
        if (-not [string]::Equals([string]$recorded.findingHash, [string]$Item.findingHash, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Monitor outbox idempotency collision: recorded key has different evidence.'
        }
        return $recorded
    }
    $path = Join-Path (Join-Path $root 'pending') $fileName
    if ([IO.File]::Exists($path)) {
        $existing = Read-MonitorOutboxFile -Path $path
        if (-not [string]::Equals([string]$existing.findingHash, [string]$Item.findingHash, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Monitor outbox idempotency collision: same key has different evidence.'
        }
        return $existing
    }
    Write-MonitorAtomicText -Path $path -Text (ConvertTo-MonitorJsonText -Value $Item)
    return Read-MonitorOutboxFile -Path $path
}

function Get-MonitorOutboxItems {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Public module API name is part of the persisted monitor contract.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SpoolRoot, [switch]$IncludeRecorded)
    $root = Initialize-MonitorOutbox -SpoolRoot $SpoolRoot
    $directories = @((Join-Path $root 'pending'))
    if ($IncludeRecorded) { $directories += (Join-Path $root 'recorded') }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($directory in $directories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json' | Sort-Object Name)) {
            $item = Read-MonitorOutboxFile -Path $file.FullName
            if ($IncludeRecorded -or $item.status -eq 'pending') {
                [void]$items.Add($item)
            } elseif (-not [IO.File]::Exists((Join-Path (Join-Path $root 'recorded') $file.Name))) {
                throw 'Monitor outbox has a recorded-status pending item without a recorded copy.'
            }
        }
    }
    return $items.ToArray()
}

function Save-MonitorPendingItem {
    param([Parameter(Mandatory)][string]$SpoolRoot, [Parameter(Mandatory)]$Item)
    Assert-MonitorOutboxItem -Item $Item
    if ($Item.status -ne 'pending') { throw 'Only pending monitor items may be saved to the pending queue.' }
    $root = Initialize-MonitorOutbox -SpoolRoot $SpoolRoot
    $path = Join-Path (Join-Path $root 'pending') ($Item.idempotencyKey.ToUpperInvariant() + '.json')
    Write-MonitorAtomicText -Path $path -Text (ConvertTo-MonitorJsonText -Value $Item)
    return Read-MonitorOutboxFile -Path $path
}

function Complete-MonitorOutboxItem {
    param([Parameter(Mandatory)][string]$SpoolRoot, [Parameter(Mandatory)]$Item, [AllowNull()][object]$CommentId = $null, [DateTime]$RecordedAtUtc = [DateTime]::MinValue)
    if ($RecordedAtUtc -eq [DateTime]::MinValue) { $RecordedAtUtc = Get-MonitorUtcNow }
    $Item.status = 'recorded'
    $Item.recordedCommentId = if ($null -eq $CommentId) { $null } else { [string]$CommentId }
    $Item.recordedAtUtc = $RecordedAtUtc.ToUniversalTime().ToString('o')
    Assert-MonitorOutboxItem -Item $Item
    $root = Initialize-MonitorOutbox -SpoolRoot $SpoolRoot
    $recordedPath = Join-Path (Join-Path $root 'recorded') ($Item.idempotencyKey.ToUpperInvariant() + '.json')
    if ([IO.File]::Exists($recordedPath)) {
        $existing = Read-MonitorOutboxFile -Path $recordedPath
        if (-not [string]::Equals([string]$existing.findingHash, [string]$Item.findingHash, [StringComparison]::OrdinalIgnoreCase)) { throw 'Recorded monitor item conflicts with pending evidence.' }
    } else {
        Write-MonitorAtomicText -Path $recordedPath -Text (ConvertTo-MonitorJsonText -Value $Item)
    }
    $pendingPath = Join-Path (Join-Path $root 'pending') ($Item.idempotencyKey.ToUpperInvariant() + '.json')
    if ([IO.File]::Exists($pendingPath)) {
        try { [IO.File]::Delete($pendingPath) } catch { $null = $_.Exception }
    }
    return Read-MonitorOutboxFile -Path $recordedPath
}

function ConvertTo-MonitorSafeError {
    param([Parameter(Mandatory)]$ErrorRecord)
    $message = (($ErrorRecord.Exception.GetType().Name + ': ' + $ErrorRecord.Exception.Message) -replace '[\r\n]+', ' ').Trim()
    $message = [regex]::Replace($message, '(?i)(authorization|token|password|secret|api[_-]?key)\s*[:=]\s*[^\s,;]+', '$1=[redacted]')
    if ($message.Length -gt $script:MonitorMaxErrorLength) { $message = $message.Substring(0, $script:MonitorMaxErrorLength) }
    return $message
}

function Get-MonitorBackoffSeconds {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Public module API name is part of the persisted monitor contract.')]
    param([Parameter(Mandatory)][int]$AttemptCount, [int]$BaseBackoffSeconds = 60, [int]$MaxBackoffSeconds = 3600)
    if ($AttemptCount -lt 1) { return 0 }
    if ($BaseBackoffSeconds -lt 1 -or $MaxBackoffSeconds -lt $BaseBackoffSeconds) { throw 'Invalid monitor backoff bounds.' }
    $seconds = [int64]$BaseBackoffSeconds
    for ($i = 1; $i -lt $AttemptCount; $i++) {
        if ($seconds -ge $MaxBackoffSeconds) { return $MaxBackoffSeconds }
        $seconds = [Math]::Min([int64]$MaxBackoffSeconds, $seconds * 2)
    }
    return [int]$seconds
}

function Test-MonitorGitHubUri {
    param([Parameter(Mandatory)][string]$Uri)
    $parsed = $null
    if (-not [Uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsed) -or
        $parsed.Scheme -ne 'https' -or $parsed.Host -ne 'api.github.com' -or
        -not [string]::IsNullOrEmpty($parsed.UserInfo)) {
        throw 'Monitor GitHub URL is not allowlisted.'
    }
}

function Invoke-MonitorGitHubRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [string]$Token = '',
        [AllowNull()][object]$Body = $null
    )
    Test-MonitorGitHubUri -Uri $Uri
    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'Jumpstile-development-monitor' }
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers.Authorization = 'Bearer ' + $Token }
    if ($Method -eq 'GET') {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
    }
    $json = $Body | ConvertTo-Json -Depth 10 -Compress
    return Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -Body $json -ContentType 'application/json' -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
}

function Find-MonitorGitHubComment {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][string]$Token)
    Assert-MonitorRepositoryName -Repository $Item.finding.repository
    $marker = '<!-- monitor-idempotency:' + $Item.idempotencyKey.ToUpperInvariant() + ' -->'
    for ($page = 1; $page -le $script:MonitorMaxPages; $page++) {
        $uri = $script:MonitorApiBaseUri + '/repos/' + $Item.finding.repository + '/issues/' + $Item.finding.targetIssueNumber + '/comments?per_page=100&page=' + $page
        $comments = @(Invoke-MonitorGitHubRequest -Method GET -Uri $uri -Token $Token)
        foreach ($comment in $comments) {
            if ($null -ne $comment.body -and [string]$comment.body -like ('*' + $marker + '*')) { return $comment }
        }
        if ($comments.Count -lt 100) { return $null }
    }
    throw 'GitHub comment verification exceeded the bounded page limit.'
}

function Publish-MonitorOutboxItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SpoolRoot, [Parameter(Mandatory)]$Item, [Parameter(Mandatory)][string]$Token, [DateTime]$NowUtc = [DateTime]::MinValue)
    if ([string]::IsNullOrWhiteSpace($Token)) { throw 'GitHub token is required to publish monitor evidence.' }
    if ($NowUtc -eq [DateTime]::MinValue) { $NowUtc = Get-MonitorUtcNow }
    Assert-MonitorOutboxItem -Item $Item

    $already = Find-MonitorGitHubComment -Item $Item -Token $Token
    if ($null -ne $already) { return Complete-MonitorOutboxItem -SpoolRoot $SpoolRoot -Item $Item -CommentId $already.id -RecordedAtUtc $NowUtc }

    $marker = '<!-- monitor-idempotency:' + $Item.idempotencyKey.ToUpperInvariant() + ' -->'
    $body = $marker + "`r`n" + [string]$Item.finding.body
    $uri = $script:MonitorApiBaseUri + '/repos/' + $Item.finding.repository + '/issues/' + $Item.finding.targetIssueNumber + '/comments'
    try {
        [void](Invoke-MonitorGitHubRequest -Method POST -Uri $uri -Token $Token -Body @{ body = $body })
    } catch {
        try {
            $afterUncertainWrite = Find-MonitorGitHubComment -Item $Item -Token $Token
            if ($null -ne $afterUncertainWrite) { return Complete-MonitorOutboxItem -SpoolRoot $SpoolRoot -Item $Item -CommentId $afterUncertainWrite.id -RecordedAtUtc $NowUtc }
        } catch { $null = $_.Exception }
        throw
    }

    $verified = Find-MonitorGitHubComment -Item $Item -Token $Token
    if ($null -eq $verified) { throw 'GitHub write verification failed: idempotency marker was not readable after POST.' }
    return Complete-MonitorOutboxItem -SpoolRoot $SpoolRoot -Item $Item -CommentId $verified.id -RecordedAtUtc $NowUtc
}

function Invoke-MonitorOutboxReplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SpoolRoot,
        [string]$Token = '',
        [int]$MaxItems = 50,
        [int]$BaseBackoffSeconds = 60,
        [int]$MaxBackoffSeconds = 3600,
        [switch]$Force,
        [switch]$DryRun,
        [DateTime]$NowUtc = [DateTime]::MinValue
    )
    if ($MaxItems -lt 1) { throw 'MaxItems must be positive.' }
    if ($NowUtc -eq [DateTime]::MinValue) { $NowUtc = Get-MonitorUtcNow }
    $pending = @(Get-MonitorOutboxItems -SpoolRoot $SpoolRoot)
    $due = @($pending | Where-Object {
        if ($Force) { return $true }
        try { ([DateTime]$_.nextAttemptAtUtc).ToUniversalTime() -le $NowUtc.ToUniversalTime() } catch { throw 'Invalid monitor outbox next-attempt timestamp.' }
    } | Sort-Object nextAttemptAtUtc, idempotencyKey | Select-Object -First $MaxItems)
    $results = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($item in $due) {
        if ($DryRun) {
            [void]$results.Add([pscustomobject]@{ IdempotencyKey = $item.idempotencyKey; State = 'DRY_RUN'; Error = $null })
            continue
        }
        try {
            $recorded = Publish-MonitorOutboxItem -SpoolRoot $SpoolRoot -Item $item -Token $Token -NowUtc $NowUtc
            [void]$results.Add([pscustomobject]@{ IdempotencyKey = $item.idempotencyKey; State = 'RECORDED'; CommentId = $recorded.recordedCommentId; Error = $null })
        } catch {
            $item.attemptCount = [int]$item.attemptCount + 1
            $item.lastError = ConvertTo-MonitorSafeError -ErrorRecord $_
            $item.nextAttemptAtUtc = $NowUtc.ToUniversalTime().AddSeconds((Get-MonitorBackoffSeconds -AttemptCount $item.attemptCount -BaseBackoffSeconds $BaseBackoffSeconds -MaxBackoffSeconds $MaxBackoffSeconds)).ToString('o')
            try {
                [void](Save-MonitorPendingItem -SpoolRoot $SpoolRoot -Item $item)
            } catch {
                $fatal = 'Monitor outbox persistence failed after publish failure.'
                [void]$errors.Add($fatal)
                [void]$results.Add([pscustomobject]@{ IdempotencyKey = $item.idempotencyKey; State = 'PERSISTENCE_FAILURE'; Error = $fatal })
                continue
            }
            [void]$errors.Add($item.lastError)
            [void]$results.Add([pscustomobject]@{ IdempotencyKey = $item.idempotencyKey; State = 'DEFERRED'; Error = $item.lastError; NextAttemptAtUtc = $item.nextAttemptAtUtc })
        }
    }
    $remaining = @(Get-MonitorOutboxItems -SpoolRoot $SpoolRoot)
    return [pscustomobject]@{
        Attempted = $due.Count
        Recorded = @($results | Where-Object State -eq 'RECORDED').Count
        Deferred = @($remaining).Count
        Pending = @($remaining).Count
        Errors = $errors.ToArray()
        Results = $results.ToArray()
    }
}

function Read-MonitorSourceState {
    param([Parameter(Mandatory)][string]$SpoolRoot, [Parameter(Mandatory)][string]$MonitorId)
    $root = Initialize-MonitorOutbox -SpoolRoot $SpoolRoot
    $path = Join-Path $root 'source-state.json'
    if (-not [IO.File]::Exists($path)) {
        return [pscustomobject][ordered]@{ schemaVersion = 1; monitorId = $MonitorId; sources = [ordered]@{}; updatedAtUtc = $null }
    }
    $state = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([int]$state.schemaVersion -ne 1 -or [string]$state.monitorId -ne $MonitorId) { throw 'Invalid monitor source state.' }
    return $state
}

function Write-MonitorSourceState {
    param([Parameter(Mandatory)][string]$SpoolRoot, [Parameter(Mandatory)]$State)
    $root = Initialize-MonitorOutbox -SpoolRoot $SpoolRoot
    $path = Join-Path $root 'source-state.json'
    Write-MonitorAtomicText -Path $path -Text (ConvertTo-MonitorJsonText -Value $State)
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-MonitorGitHubSourceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [string]$Token = '')
    Assert-MonitorRepositoryName -Repository $Repository
    $commitUri = $script:MonitorApiBaseUri + '/repos/' + $Repository + '/commits?per_page=1'
    $commits = @(Invoke-MonitorGitHubRequest -Method GET -Uri $commitUri -Token $Token)
    if ($commits.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$commits[0].sha)) { throw 'GitHub source returned no usable commit identity.' }
    $releaseTag = $null
    $releaseUrl = $null
    $releaseUri = $script:MonitorApiBaseUri + '/repos/' + $Repository + '/releases/latest'
    try {
        $release = Invoke-MonitorGitHubRequest -Method GET -Uri $releaseUri -Token $Token
        $releaseTag = if ($release.PSObject.Properties['tag_name'] -and $release.tag_name) { [string]$release.tag_name } else { $null }
        $releaseUrl = if ($release.PSObject.Properties['html_url'] -and $release.html_url) { [string]$release.html_url } else { $null }
    } catch {
        $statusCode = 0
        try {
            if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        } catch { $statusCode = 0 }
        if ($statusCode -ne 404) { throw }
    }
    return [pscustomobject][ordered]@{
        repository      = $Repository
        commitSha       = [string]$commits[0].sha
        commitUrl       = if ($commits[0].PSObject.Properties['html_url'] -and $commits[0].html_url) { [string]$commits[0].html_url } else { $null }
        releaseTag      = $releaseTag
        releaseUrl      = $releaseUrl
    }
}

function Get-MonitorSourceStateValue {
    param([AllowNull()]$Sources, [Parameter(Mandatory)][string]$SourceId)
    if ($null -eq $Sources) { return $null }
    $property = $Sources.PSObject.Properties[$SourceId]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-MonitorFailureCategory {
    param([Parameter(Mandatory)]$ErrorRecord)
    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '(?i)404|not found') { return 'not-found' }
    if ($message -match '(?i)timed out|timeout') { return 'timeout' }
    return 'request-failed'
}

function Invoke-MonitorSourceWatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MonitorId,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$SpoolRoot,
        [string]$Token = '',
        [DateTime]$NowUtc = [DateTime]::MinValue
    )
    if ($NowUtc -eq [DateTime]::MinValue) { $NowUtc = Get-MonitorUtcNow }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Monitor source manifest is missing.' }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.monitorId -ne $MonitorId) { throw 'Monitor source manifest identity is invalid.' }
    Assert-MonitorRepositoryName -Repository $manifest.targetRepository
    if ([int]$manifest.targetIssueNumber -lt 1) { throw 'Monitor source manifest target issue is invalid.' }

    $state = Read-MonitorSourceState -SpoolRoot $SpoolRoot -MonitorId $MonitorId
    $sourceMap = [ordered]@{}
    if ($null -ne $state.sources) {
        foreach ($property in @($state.sources.PSObject.Properties)) { $sourceMap[$property.Name] = $property.Value }
    }
    $findings = New-Object System.Collections.Generic.List[object]
    $baselineCount = 0
    $changedCount = 0
    $failedCount = 0
    foreach ($source in @($manifest.sources | Sort-Object sourceId)) {
        $sourceId = [string]$source.sourceId
        if ($sourceId -notmatch '^[A-Za-z0-9_.-]+$' -or [string]::IsNullOrWhiteSpace([string]$source.repository)) { throw 'Monitor source identity is invalid.' }
        Assert-MonitorRepositoryName -Repository $source.repository
        $targetIssueProperty = $source.PSObject.Properties['targetIssueNumber']
        $targetIssue = if ($targetIssueProperty -and $source.targetIssueNumber) { [int]$source.targetIssueNumber } else { [int]$manifest.targetIssueNumber }
        $snapshot = $null
        $sourceError = $null
        try {
            $snapshot = Get-MonitorGitHubSourceSnapshot -Repository $source.repository -Token $Token
        } catch {
            $sourceError = $_
        }

        if ($null -ne $sourceError) {
            $failedCount++
            $displayName = if ($source.PSObject.Properties['name'] -and $source.name) { [string]$source.name } else { [string]$source.repository }
            $category = Get-MonitorFailureCategory -ErrorRecord $sourceError
            $body = @(
                'The development monitor could not obtain a usable snapshot for an approved source.',
                '',
                ('Source: **{0}** (`{1}`)' -f $displayName, $source.repository),
                ('Failure category: `{0}`' -f $category),
                '',
                'The source state was not advanced. This finding remains queued for later reconciliation; no runtime or release action is implied.'
            ) -join "`r`n"
            $finding = New-MonitorFinding -MonitorId $MonitorId -Repository $manifest.targetRepository -TargetIssueNumber $targetIssue -FindingType 'source-fetch-failure' -Title ('Source snapshot unavailable: ' + $displayName) -Body $body -SourceIds @($sourceId) -Confidence 'Unknown' -Evidence ([ordered]@{ sourceId = $sourceId; repository = [string]$source.repository; failureCategory = $category }) -ObservedAtUtc $NowUtc
            $item = New-MonitorOutboxItem -Finding $finding -CreatedAtUtc $NowUtc
            [void]$findings.Add((Write-MonitorOutboxItem -SpoolRoot $SpoolRoot -Item $item))
            continue
        }

        $prior = Get-MonitorSourceStateValue -Sources $state.sources -SourceId $sourceId
        if ($null -eq $prior) {
            $baselineCount++
        } elseif ([string]$prior.commitSha -ne [string]$snapshot.commitSha -or [string]$prior.releaseTag -ne [string]$snapshot.releaseTag) {
            $changedCount++
            $displayName = if ($source.PSObject.Properties['name'] -and $source.name) { [string]$source.name } else { [string]$source.repository }
            $body = @(
                'The development monitor observed a changed approved source snapshot.',
                '',
                ('Source: **{0}** (`{1}`)' -f $displayName, $source.repository),
                ('Previous commit: `{0}`' -f [string]$prior.commitSha),
                ('Current commit: `{0}` ([source]({1}))' -f [string]$snapshot.commitSha, [string]$snapshot.commitUrl),
                ('Previous latest release: `{0}`' -f $(if ($prior.releaseTag) { [string]$prior.releaseTag } else { 'none observed' })),
                ('Current latest release: `{0}`' -f $(if ($snapshot.releaseTag) { [string]$snapshot.releaseTag } else { 'none observed' })),
                '',
                'This is a review-needed evidence lead. It does not authorize runtime changes, automatic compatibility activation, merge, or release action.'
            ) -join "`r`n"
            $finding = New-MonitorFinding -MonitorId $MonitorId -Repository $manifest.targetRepository -TargetIssueNumber $targetIssue -FindingType 'source-change' -Title ('Upstream source change detected: ' + $displayName) -Body $body -SourceIds @($sourceId) -Confidence 'ReviewNeeded' -Evidence ([ordered]@{ sourceId = $sourceId; repository = [string]$source.repository; previousCommitSha = [string]$prior.commitSha; currentCommitSha = [string]$snapshot.commitSha; previousReleaseTag = [string]$prior.releaseTag; currentReleaseTag = [string]$snapshot.releaseTag; currentCommitUrl = [string]$snapshot.commitUrl; currentReleaseUrl = [string]$snapshot.releaseUrl }) -ObservedAtUtc $NowUtc
            $item = New-MonitorOutboxItem -Finding $finding -CreatedAtUtc $NowUtc
            [void]$findings.Add((Write-MonitorOutboxItem -SpoolRoot $SpoolRoot -Item $item))
        }
        $sourceMap[$sourceId] = $snapshot
    }

    $newState = [pscustomobject][ordered]@{ schemaVersion = 1; monitorId = $MonitorId; sources = [pscustomobject]$sourceMap; updatedAtUtc = $NowUtc.ToUniversalTime().ToString('o') }
    [void](Write-MonitorSourceState -SpoolRoot $SpoolRoot -State $newState)
    return [pscustomobject]@{ MonitorId = $MonitorId; TargetIssueNumber = [int]$manifest.targetIssueNumber; BaselineSources = $baselineCount; ChangedSources = $changedCount; FailedSources = $failedCount; FindingsQueued = $findings.Count; Findings = $findings.ToArray() }
}

Export-ModuleMember -Function @(
    'Assert-MonitorRepositoryName',
    'Initialize-MonitorOutbox',
    'Write-MonitorAtomicText',
    'ConvertTo-MonitorCanonicalJson',
    'Get-MonitorFindingHash',
    'Get-MonitorIdempotencyKey',
    'New-MonitorFinding',
    'New-MonitorOutboxItem',
    'Write-MonitorOutboxItem',
    'Get-MonitorOutboxItems',
    'Get-MonitorBackoffSeconds',
    'Invoke-MonitorOutboxReplay',
    'Invoke-MonitorGitHubRequest',
    'Publish-MonitorOutboxItem',
    'Read-MonitorSourceState',
    'Write-MonitorSourceState',
    'Get-MonitorGitHubSourceSnapshot',
    'Invoke-MonitorSourceWatch'
)
