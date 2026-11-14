$script:ChannelForgeKnowledgeVersion = 'knowledge-state/v1'
$script:ChannelForgeKnowledgePlanVersion = 'knowledge-change-plan/v1'

function Get-ChannelForgeKnowledgePaths {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [System.IO.Directory]::Exists($root)) { throw 'KNOWLEDGE_UNAVAILABLE: repository root does not exist.' }
    if ($root.StartsWith('\\')) { throw 'FAIL_CLOSED: knowledge state does not support UNC roots.' }
    $directory = Join-Path $root 'state/knowledge'
    return [pscustomobject][ordered]@{
        Root = $root
        Directory = $directory
        StatePath = Join-Path $directory 'learned.json'
        LockPath = Join-Path $directory '.learned.lock'
        SchemaPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\schemas\knowledge_state.schema.json'))
    }
}

function Assert-ChannelForgeKnowledgePath {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$AllowedRoot,[switch]$AllowMissingLeaf,[switch]$AllowMissingComponents)
    $root = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92,[char]47)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($root.StartsWith('\\') -or -not $full.StartsWith("$root$([System.IO.Path]::DirectorySeparatorChar)",[System.StringComparison]::OrdinalIgnoreCase)) { throw 'FAIL_CLOSED: knowledge path escaped its allowed root.' }
    $relative = $full.Substring($root.Length).TrimStart([char]92,[char]47)
    $parts = @($relative -split '[\\/]')
    $cursor = $root
    for ($index = 0; $index -lt $parts.Count; $index++) {
        if ([string]::IsNullOrWhiteSpace($parts[$index])) { continue }
        $cursor = Join-Path $cursor $parts[$index]
        if ([System.IO.File]::Exists($cursor) -or [System.IO.Directory]::Exists($cursor)) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FAIL_CLOSED: knowledge path contains a reparse point.' }
        } elseif (-not $AllowMissingComponents -and -not ($AllowMissingLeaf -and $index -eq ($parts.Count - 1))) { throw 'KNOWLEDGE_UNAVAILABLE: knowledge path component is missing.' }
    }
    return $full
}

function Get-ChannelForgeKnowledgeHash {
    param([Parameter(Mandatory)]$State)
    $projection = [ordered]@{ Version = [string]$State.Version; Revision = [int]$State.Revision; Entries = @($State.Entries); AuditTrail = @($State.AuditTrail) }
    return Get-ChannelForgeDomainHash -Domain 'knowledge-state/v1' -InputObject $projection
}

function New-ChannelForgeKnowledgeEmptyState {
    $state = [ordered]@{ Version = $script:ChannelForgeKnowledgeVersion; Revision = 0; Entries = @(); AuditTrail = @(); StateHash = $null }
    $state.StateHash = Get-ChannelForgeKnowledgeHash -State ([pscustomobject]$state)
    return [pscustomobject]$state
}

function Assert-ChannelForgeKnowledgeState {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$SchemaPath)
    if ([string]$State.Version -cne $script:ChannelForgeKnowledgeVersion -or [int]$State.Revision -lt 0) { throw 'FAIL_CLOSED: knowledge state version or revision is invalid.' }
    if ([string]$State.StateHash -cne (Get-ChannelForgeKnowledgeHash -State $State)) { throw 'FAIL_CLOSED: knowledge state integrity check failed.' }
    $ids = @($State.Entries | ForEach-Object { [string]$_.EntryId })
    if ($ids.Count -ne @($ids | Sort-Object -Unique).Count) { throw 'FAIL_CLOSED: knowledge state contains duplicate EntryIds.' }
    try {
        foreach ($entry in @($State.Entries)) {
            [void](ConvertTo-ChannelForgeKnowledgeText $entry.Reason 'Entry.Reason')
            foreach ($record in @($entry.History)) { [void](ConvertTo-ChannelForgeKnowledgeText $record.Reason 'History.Reason') }
        }
        foreach ($record in @($State.AuditTrail)) { [void](ConvertTo-ChannelForgeKnowledgeText $record.Reason 'AuditTrail.Reason') }
    } catch { throw 'FAIL_CLOSED: knowledge state contains unsafe free text.' }
    foreach ($entry in @($State.Entries)) {
        if ([int]$entry.Revision -gt [int]$State.Revision -or @($entry.ObservationIds | Sort-Object -Unique).Count -ne @($entry.ObservationIds).Count) { throw 'FAIL_CLOSED: knowledge entry revision or evidence references are invalid.' }
        foreach ($observationId in @($entry.ObservationIds)) { if ([string]$observationId -notmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: knowledge evidence reference is invalid.' } }
        if ([string]$entry.Kind -eq 'ChannelBinding') {
            $registered = @($State.Entries | Where-Object { [string]$_.Kind -eq 'ChannelIdentity' -and [string]$_.ChannelId -ceq [string]$entry.ChannelId })
            if ($registered.Count -ne 1 -or ($entry.ApprovalStatus -eq 'Approved' -and $registered[0].ApprovalStatus -ne 'Approved')) { throw 'FAIL_CLOSED: channel binding references an unregistered or inactive canonical ChannelId.' }
        } elseif ([string]$entry.Kind -eq 'ProgrammeAlias') {
            try {
                $topSides = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides @($entry.Sides))
                $computedContextKey = Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $topSides)
                if ($computedContextKey -cne [string]$entry.ContextKey -or [string]$entry.EntryId -cne [string]$entry.ContextKey) { throw 'FAIL_CLOSED: contextual alias key does not match its exact side context.' }
                $contextStart = [string](@($topSides | Sort-Object StartUtc | Select-Object -First 1).StartUtc)
                $contextStop = [string](@($topSides | Sort-Object StopUtc -Descending | Select-Object -First 1).StopUtc)
                if ([string]$entry.Context.EventStartUtc -cne $contextStart -or [string]$entry.Context.EventStopUtc -cne $contextStop) { throw 'FAIL_CLOSED: contextual alias interval does not match its sides.' }
                if (@($entry.EvidenceRecords).Count -eq 0) { throw 'FAIL_CLOSED: contextual alias requires at least one evidence record.' }
                $evidenceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                $evidenceKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($record in @($entry.EvidenceRecords)) {
                    $sides = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides $record.Sides)
                    $pairIds = @($record.ObservationIds | Sort-Object -Unique)
                    $sideIds = @($sides | ForEach-Object ObservationId | Sort-Object -Unique)
                    if ($pairIds.Count -ne 2 -or ($sideIds -join '|') -cne ($pairIds -join '|')) { throw 'FAIL_CLOSED: contextual alias evidence identities do not match their sides.' }
                    $evidenceContextKey = Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $sides)
                    if ($evidenceContextKey -cne [string]$entry.ContextKey) { throw 'FAIL_CLOSED: contextual alias evidence does not match its exact side context.' }
                    $basis = @($record.CorrelationBasis | ForEach-Object { ConvertTo-ChannelForgeKnowledgeText $_ 'CorrelationBasis' 128 } | Sort-Object -Unique)
                    if ($basis.Count -eq 0) { throw 'FAIL_CLOSED: contextual alias correlation basis is empty.' }
                    if (-not $evidenceKeys.Add($pairIds -join '|')) { throw 'FAIL_CLOSED: contextual alias contains duplicate evidence pairs.' }
                    foreach ($observationId in $pairIds) { [void]$evidenceIds.Add($observationId) }
                }
                $storedObservationIds = @($entry.ObservationIds | Sort-Object -Unique)
                if (($evidenceIds | Sort-Object) -join '|' -cne ($storedObservationIds -join '|') -or [int]$entry.EvidenceCount -ne $evidenceIds.Count) { throw 'FAIL_CLOSED: contextual alias evidence count or references are inconsistent.' }
                foreach ($side in $topSides) {
                    $registered = @($State.Entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $side.ChannelId })
                    if ($registered.Count -ne 1 -or ($entry.ApprovalStatus -eq 'Approved' -and $registered[0].ApprovalStatus -ne 'Approved')) { throw 'FAIL_CLOSED: contextual alias references an unregistered or inactive ChannelId.' }
                }
            }
            catch {
                if ($_.Exception.Message -match '^FAIL_CLOSED:') { throw }
                throw 'FAIL_CLOSED: contextual alias state contains unsafe or invalid evidence.'
            }
        }
    }
    $activeBindingKeys = @($State.Entries | Where-Object { $_.Kind -eq 'ChannelBinding' -and $_.ApprovalStatus -eq 'Approved' } | ForEach-Object { "$($_.PlaylistId)`u{001f}$($_.SourceId)`u{001f}$($_.SourceChannelReference)`u{001f}$($_.EffectiveFromUtc)`u{001f}$($_.EffectiveToUtc)" })
    if ($activeBindingKeys.Count -ne @($activeBindingKeys | Sort-Object -Unique).Count) { throw 'FAIL_CLOSED: duplicate approved channel binding intervals exist.' }
    $aliasKeys = @($State.Entries | Where-Object { $_.Kind -eq 'ProgrammeAlias' } | ForEach-Object { [string]$_.ContextKey })
    if ($aliasKeys.Count -ne @($aliasKeys | Sort-Object -Unique).Count) { throw 'FAIL_CLOSED: duplicate contextual alias contexts exist.' }
    if (@($State.AuditTrail | Where-Object { [int]$_.Revision -gt [int]$State.Revision -or [int]$_.Revision -lt 1 }).Count -gt 0) { throw 'FAIL_CLOSED: knowledge audit revision is invalid.' }
    $json = ConvertTo-ChannelForgeCanonicalJson -InputObject $State
    if (-not (Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'FAIL_CLOSED: knowledge state schema validation failed.' }
}

function Read-ChannelForgeKnowledgeState {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $bytes = Read-ChannelForgeKnowledgeBytes -Path $paths.StatePath -RepositoryRoot $paths.Root -AllowMissing
    if ($null -eq $bytes) { return New-ChannelForgeKnowledgeEmptyState }
    $utf8 = [System.Text.UTF8Encoding]::new($false,$true)
    try { $text = $utf8.GetString($bytes); $state = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop }
    catch { throw 'FAIL_CLOSED: knowledge state is not valid UTF-8 JSON.' }
    if ((ConvertTo-ChannelForgeCanonicalJson -InputObject $state) -cne $text) { throw 'FAIL_CLOSED: knowledge state is not canonical JSON.' }
    Assert-ChannelForgeKnowledgeState -State $state -SchemaPath $paths.SchemaPath
    return $state
}

function Read-ChannelForgeKnowledgeBytes {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$RepositoryRoot,[switch]$AllowMissing)
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $full = Assert-ChannelForgeKnowledgePath -Path $Path -AllowedRoot $paths.Root -AllowMissingLeaf:$AllowMissing.IsPresent -AllowMissingComponents:$AllowMissing.IsPresent
    $rootHandles = [ChannelForge.KnowledgeNativeIO]::OpenDirectoryChain($paths.Root)
    $directoryHandles = [System.Collections.Generic.List[object]]::new()
    foreach ($handle in $rootHandles) { $directoryHandles.Add($handle) }
    $stream = $null
    try {
        $relativeDirectory = [System.IO.Path]::GetRelativePath($paths.Root,(Split-Path -Parent $full))
        if ($relativeDirectory -cne '.') {
            foreach ($part in @($relativeDirectory -split '[\\/]')) {
                $child = [ChannelForge.KnowledgeNativeIO]::OpenDirectoryIfExists($directoryHandles[$directoryHandles.Count - 1],$part)
                if ($null -eq $child) { return $null }
                $directoryHandles.Add($child)
            }
        }
        $handle = [ChannelForge.KnowledgeNativeIO]::OpenFile($directoryHandles[$directoryHandles.Count - 1],[System.IO.Path]::GetFileName($full),$false,$false,$false,1,$AllowMissing.IsPresent)
        if ($null -eq $handle) { return $null }
        $stream = [System.IO.FileStream]::new($handle,[System.IO.FileAccess]::Read,4096,$false)
        $memory = [System.IO.MemoryStream]::new()
        try { $stream.CopyTo($memory); return ,$memory.ToArray() } finally { $memory.Dispose() }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        foreach ($handle in $directoryHandles) { $handle.Dispose() }
    }
}


function Read-ChannelForgeKnowledgeFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $bytes = Read-ChannelForgeKnowledgeBytes -Path $Path -RepositoryRoot $paths.Root
    if ($null -eq $bytes) { throw 'FAIL_CLOSED: knowledge snapshot is missing.' }
    $utf8 = [System.Text.UTF8Encoding]::new($false,$true)
    try { $text = $utf8.GetString($bytes); $state = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop } catch { throw 'FAIL_CLOSED: knowledge snapshot is not valid UTF-8 JSON.' }
    if ((ConvertTo-ChannelForgeCanonicalJson -InputObject $state) -cne $text) { throw 'FAIL_CLOSED: knowledge snapshot is not canonical JSON.' }
    Assert-ChannelForgeKnowledgeState -State $state -SchemaPath $paths.SchemaPath
    return $state
}

function Write-ChannelForgeKnowledgeSnapshot {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $full = Assert-ChannelForgeKnowledgePath -Path $Path -AllowedRoot $paths.Root -AllowMissingLeaf
    $directoryHandles = [ChannelForge.KnowledgeNativeIO]::OpenDirectoryChain((Split-Path -Parent $full))
    $stream = $null
    try {
        $existingHandle = [ChannelForge.KnowledgeNativeIO]::OpenFile($directoryHandles[-1],[System.IO.Path]::GetFileName($full),$false,$false,$false,1,$true)
        if ($null -ne $existingHandle) {
            $existingHandle.Dispose()
            $existing = Read-ChannelForgeKnowledgeFile -Path $full -RepositoryRoot $RepositoryRoot
            if ([string]$existing.StateHash -cne [string]$State.StateHash) { throw 'FAIL_CLOSED: knowledge snapshot path contains another revision.' }
            return
        }
        $handle = [ChannelForge.KnowledgeNativeIO]::OpenFile($directoryHandles[-1],[System.IO.Path]::GetFileName($full),$true,$false,$true,0,$false)
        $stream = [System.IO.FileStream]::new($handle,[System.IO.FileAccess]::Write,4096,$false)
        $bytes = [System.Text.UTF8Encoding]::new($false,$true).GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $State))
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        foreach ($handle in $directoryHandles) { $handle.Dispose() }
    }
    $roundTrip = Read-ChannelForgeKnowledgeFile -Path $full -RepositoryRoot $RepositoryRoot
    if ([string]$roundTrip.StateHash -cne [string]$State.StateHash) { throw 'FAIL_CLOSED: knowledge backup verification failed.' }
}

function Write-ChannelForgeKnowledgeStateAtomic {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $rootHandles = $null; $stateDirectoryHandle = $null; $knowledgeDirectoryHandle = $null
    $lockStream = $null; $temporaryStream = $null; $temporaryName = $null
    try {
        $rootHandles = [ChannelForge.KnowledgeNativeIO]::OpenDirectoryChain($paths.Root)
        $stateDirectoryHandle = [ChannelForge.KnowledgeNativeIO]::OpenOrCreateDirectory($rootHandles[-1],'state')
        $knowledgeDirectoryHandle = [ChannelForge.KnowledgeNativeIO]::OpenOrCreateDirectory($stateDirectoryHandle,'knowledge')
        $lockHandle = [ChannelForge.KnowledgeNativeIO]::OpenFile($knowledgeDirectoryHandle,'.learned.lock',$false,$true,$true,0,$false)
        $lockStream = [System.IO.FileStream]::new($lockHandle,[System.IO.FileAccess]::ReadWrite,4096,$false)
        $bytes = [System.Text.UTF8Encoding]::new($false,$true).GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $State))
        Assert-ChannelForgeKnowledgeState -State $State -SchemaPath $paths.SchemaPath
        $existingHandle = [ChannelForge.KnowledgeNativeIO]::OpenFile($knowledgeDirectoryHandle,'learned.json',$false,$false,$false,1,$true)
        $hasCurrent = $null -ne $existingHandle
        if ($hasCurrent) { $existingHandle.Dispose() }
        $current = $null
        if ($hasCurrent) {
            $current = Read-ChannelForgeKnowledgeState -RepositoryRoot $paths.Root
            if ([int]$State.Revision -ne ([int]$current.Revision + 1)) { throw 'FAIL_CLOSED: knowledge writer revision changed.' }
            $backup = $paths.StatePath + '.r' + [string]$current.Revision + '.bak'
            Write-ChannelForgeKnowledgeSnapshot -State $current -Path $backup -RepositoryRoot $paths.Root
        } elseif ([int]$State.Revision -ne 1) { throw 'FAIL_CLOSED: initial knowledge state must begin at revision 1.' }
        $temporaryName = '.learned.' + [guid]::NewGuid().ToString('N') + '.tmp'
        $temporaryHandle = [ChannelForge.KnowledgeNativeIO]::OpenFile($knowledgeDirectoryHandle,$temporaryName,$true,$false,$true,0,$false)
        $temporaryStream = [System.IO.FileStream]::new($temporaryHandle,[System.IO.FileAccess]::Write,4096,$false)
        $temporaryStream.Write($bytes,0,$bytes.Length)
        $temporaryStream.Flush($true)
        [ChannelForge.KnowledgeNativeIO]::Rename($temporaryStream.SafeFileHandle,$knowledgeDirectoryHandle,'learned.json',$hasCurrent)
        $temporaryName = $null
        $temporaryStream.Dispose(); $temporaryStream = $null
        $written = Read-ChannelForgeKnowledgeState -RepositoryRoot $paths.Root
        if ([string]$written.StateHash -cne [string]$State.StateHash) { throw 'FAIL_CLOSED: committed knowledge state does not match the validated plan result.' }
        Remove-ChannelForgeKnowledgeBackup -RepositoryRoot $paths.Root
    }
    catch {
        if ($_.Exception.ToString() -match '(?i)reparse point|wrong file type') { throw 'FAIL_CLOSED: knowledge path contains a reparse point or unexpected file type.' }
        throw
    }
    finally {
        if ($null -ne $temporaryStream) { $temporaryStream.Dispose() }
        if ($null -ne $temporaryName -and $null -ne $knowledgeDirectoryHandle) {
            $leftover = [ChannelForge.KnowledgeNativeIO]::OpenFile($knowledgeDirectoryHandle,$temporaryName,$false,$false,$true,0,$true)
            if ($null -ne $leftover) { try { [ChannelForge.KnowledgeNativeIO]::Delete($leftover) } finally { $leftover.Dispose() } }
        }
        if ($null -ne $lockStream) { $lockStream.Dispose() }
        if ($null -ne $knowledgeDirectoryHandle) { $knowledgeDirectoryHandle.Dispose() }
        if ($null -ne $stateDirectoryHandle) { $stateDirectoryHandle.Dispose() }
        if ($null -ne $rootHandles) { foreach ($handle in $rootHandles) { $handle.Dispose() } }
    }
}

function Get-ChannelForgeKnowledgePlanHash {
    param([Parameter(Mandatory)]$Plan)
    $projection = [ordered]@{}
    foreach ($property in @($Plan.PSObject.Properties)) { if ($property.Name -cne 'PlanHash') { $projection[$property.Name] = $property.Value } }
    return Get-ChannelForgeDomainHash -Domain 'knowledge-change-plan/v1' -InputObject $projection
}

function ConvertTo-ChannelForgeKnowledgeText {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name,[int]$Maximum = 512)
    if ($null -eq $Value) { throw "KNOWLEDGE_INVALID: $Name is required." }
    $text = ([string]$Value).Trim()
    $sensitive = '(?i)(?:\b(?:[A-Z0-9]+_)*(?:password|passwd|secret|token|credential|api[_-]?key|access[_-]?key|client[_-]?secret)(?:_[A-Z0-9]+)*\s*[:=]\s*\S+|\bauthorization\s*[:=]\s*(?:(?:bearer|basic)\s+)?\S+|\bbearer\s+[A-Za-z0-9._~+/-]+=*|(?<![A-Za-z0-9])/(?:[^/\s]+/)+[^/\s]*)'
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt $Maximum -or $text -match '[\x00-\x08\x0B\x0C\x0E-\x1F]' -or $text -match '(?i)(https?://|ftp://|file://|[a-z]:[\\/]|\\\\|[\w.+-]+@[\w.-]+)' -or $text -match $sensitive) { throw "KNOWLEDGE_INVALID: $Name is unsafe or outside its length limit." }
    return $text
}

function ConvertTo-ChannelForgeKnowledgeUtc {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name,[switch]$Optional)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { if ($Optional) { return $null }; throw "KNOWLEDGE_INVALID: $Name is required." }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)) { throw "KNOWLEDGE_INVALID: $Name must be an ISO-8601 timestamp." }
    return $parsed.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",[Globalization.CultureInfo]::InvariantCulture)
}

function New-ChannelForgeKnowledgeHash {
    param([Parameter(Mandatory)][string]$Domain,[Parameter(Mandatory)]$InputObject)
    return Get-ChannelForgeDomainHash -Domain $Domain -InputObject $InputObject
}

function New-ChannelForgeKnowledgeChangePlanInternal {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][object[]]$Actions,[Parameter(Mandatory)][datetimeoffset]$CreatedAtUtc)
    $planned = [System.Collections.Generic.List[object]]::new()
    foreach ($action in $Actions) {
        if ($null -eq $action) { throw 'KNOWLEDGE_INVALID: plan action cannot be null.' }
        $type = [string]$action.Action
        $reason = ConvertTo-ChannelForgeKnowledgeText $action.Reason 'Reason'
        if ($type -in @('RegisterIdentity','AddBinding','ProposeAlias')) {
            $entry = New-ChannelForgeKnowledgePlanEntry -Action $action -CreatedAtUtc $CreatedAtUtc
            [void]$planned.Add([pscustomobject][ordered]@{ Action = $type; Entry = $entry; Reason = $reason })
        } elseif ($type -eq 'AppendAliasEvidence') {
            $id = [string]$action.EntryId
            if ($id -notmatch '^[0-9a-f]{64}$') { throw 'KNOWLEDGE_INVALID: evidence action requires an EntryId.' }
            $ids = @($action.ObservationIds | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
            if ($ids.Count -eq 0 -or @($ids | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) { throw 'KNOWLEDGE_INVALID: ObservationIds must contain SHA-256 identifiers.' }
            $records = [System.Collections.Generic.List[object]]::new()
            $target = @($State.Entries | Where-Object { [string]$_.EntryId -ceq $id -and $_.Kind -eq 'ProgrammeAlias' }) | Select-Object -First 1
            foreach ($record in @($action.EvidenceRecords)) {
                if ($null -eq $target) { throw 'KNOWLEDGE_INVALID: evidence target must be an existing contextual alias.' }
                $sides = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides $record.Sides)
                $pairIds = @($record.ObservationIds | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
                $sideIds = @($sides | ForEach-Object ObservationId | Sort-Object -Unique)
                if ($pairIds.Count -ne 2 -or ($pairIds -join '|') -cne ($sideIds -join '|') -or @($pairIds | Where-Object { $_ -notin $ids }).Count -gt 0) { throw 'KNOWLEDGE_INVALID: evidence record ObservationIds must match its two side observations and action references.' }
                $score = [int]$record.ConfidenceScore
                if ($score -lt 0 -or $score -gt 100) { throw 'KNOWLEDGE_INVALID: evidence ConfidenceScore must be between 0 and 100.' }
                $basis = @($record.CorrelationBasis | ForEach-Object { ConvertTo-ChannelForgeKnowledgeText $_ 'CorrelationBasis' 128 } | Sort-Object -Unique)
                if ($basis.Count -eq 0) { throw 'KNOWLEDGE_INVALID: evidence CorrelationBasis is required.' }
                $contextKey = Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $sides)
                if ($contextKey -cne [string]$target.ContextKey) { throw 'KNOWLEDGE_INVALID: evidence record does not match the alias context.' }
                [void]$records.Add([pscustomobject][ordered]@{ ObservationIds = $pairIds; Sides = $sides; ConfidenceScore = $score; CorrelationBasis = $basis })
            }
            if ($records.Count -eq 0) { throw 'KNOWLEDGE_INVALID: at least one complete evidence record is required.' }
            $recordIds = @($records.ToArray() | ForEach-Object { $_.ObservationIds } | Sort-Object -Unique)
            if (($recordIds -join '|') -cne ($ids -join '|')) { throw 'KNOWLEDGE_INVALID: action ObservationIds must exactly match complete evidence records.' }
            $plannedAction = [ordered]@{ Action = $type; EntryId = $id; ObservationIds = $ids; EvidenceRecords = @($records.ToArray()); Reason = $reason }
            [void]$planned.Add([pscustomobject]$plannedAction)
        } elseif ($type -in @('Approve','Reject','Revoke','MarkProbationary')) {
            $id = [string]$action.EntryId
            if ($id -notmatch '^[0-9a-f]{64}$') { throw 'KNOWLEDGE_INVALID: transition requires an EntryId.' }
            [void]$planned.Add([pscustomobject][ordered]@{ Action = $type; EntryId = $id; Reason = $reason })
        } else { throw 'KNOWLEDGE_INVALID: unsupported plan action.' }
    }
    if ($planned.Count -eq 0) { throw 'KNOWLEDGE_INVALID: at least one plan action is required.' }
    $base = [ordered]@{ Version = $script:ChannelForgeKnowledgePlanVersion; PlanId = $null; BaseRevision = [int]$State.Revision; BaseStateHash = [string]$State.StateHash; CreatedAtUtc = $CreatedAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"); Actions = @($planned.ToArray()); ConfirmationRequired = $true; PlanHash = $null }
    $base.PlanId = Get-ChannelForgeDomainHash -Domain 'knowledge-plan-id/v1' -InputObject ([ordered]@{ BaseStateHash = $base.BaseStateHash; CreatedAtUtc = $base.CreatedAtUtc; Actions = $base.Actions })
    $plan = [pscustomobject]$base
    $plan.PlanHash = Get-ChannelForgeKnowledgePlanHash -Plan $plan
    return $plan
}

function New-ChannelForgeKnowledgePlanEntry {
    param([Parameter(Mandatory)]$Action,[Parameter(Mandatory)][datetimeoffset]$CreatedAtUtc)
    $source = $Action.Entry
    $reason = ConvertTo-ChannelForgeKnowledgeText $Action.Reason 'Reason'
    $at = $CreatedAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $entry = [ordered]@{ EntryId = $null; Kind = ''; ApprovalStatus = 'Proposed'; ScopeKind = ''; Reason = $reason; ObservationIds = @(); EvidenceCount = 0; ConfidenceScore = $null; FirstSeenAtUtc = $at; LastSeenAtUtc = $at; EffectiveFromUtc = $null; EffectiveToUtc = $null; Revision = 0; History = @() }
    switch ([string]$Action.Action) {
        'RegisterIdentity' {
            $channelId = ConvertTo-ChannelForgeKnowledgeText $source.ChannelId 'ChannelId' 128
            if ($channelId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { throw 'KNOWLEDGE_INVALID: ChannelId must be an explicitly supplied safe identifier.' }
            $entry.Kind = 'ChannelIdentity'; $entry.ScopeKind = 'ExplicitIdentity'; $entry.ApprovalStatus = 'Approved'; $entry.ChannelId = $channelId
            $entry.EffectiveFromUtc = ConvertTo-ChannelForgeKnowledgeUtc $source.EffectiveFromUtc 'EffectiveFromUtc' -Optional
            $identity = [ordered]@{ Kind = $entry.Kind; ChannelId = $channelId }
            $entry.EntryId = Get-ChannelForgeDomainHash -Domain 'knowledge-entry/v1' -InputObject $identity
        }
        'AddBinding' {
            $entry.Kind = 'ChannelBinding'; $entry.ScopeKind = 'SourceScoped'; $entry.ApprovalStatus = 'Proposed'
            $entry.ChannelId = ConvertTo-ChannelForgeKnowledgeText $source.ChannelId 'ChannelId' 128
            $entry.PlaylistId = ConvertTo-ChannelForgeKnowledgeText $source.PlaylistId 'PlaylistId' 128
            $entry.SourceId = ConvertTo-ChannelForgeKnowledgeText $source.SourceId 'SourceId' 128
            $entry.SourceChannelReference = ConvertTo-ChannelForgeKnowledgeText $source.SourceChannelReference 'SourceChannelReference' 256
            foreach ($name in @('ChannelId','PlaylistId','SourceId')) { if ([string]$entry[$name] -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { throw "KNOWLEDGE_INVALID: $name is not a safe identifier." } }
            if ([string]$entry.SourceChannelReference -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { throw 'KNOWLEDGE_INVALID: SourceChannelReference is not a safe identifier.' }
            $entry.EffectiveFromUtc = ConvertTo-ChannelForgeKnowledgeUtc $source.EffectiveFromUtc 'EffectiveFromUtc' -Optional
            $entry.EffectiveToUtc = ConvertTo-ChannelForgeKnowledgeUtc $source.EffectiveToUtc 'EffectiveToUtc' -Optional
            if ($entry.EffectiveFromUtc -and $entry.EffectiveToUtc -and [datetimeoffset]$entry.EffectiveToUtc -le [datetimeoffset]$entry.EffectiveFromUtc) { throw 'KNOWLEDGE_INVALID: binding effective interval must be positive.' }
            $entry.ObservationIds = @($source.ObservationIds | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
            foreach ($observationId in $entry.ObservationIds) { if ($observationId -notmatch '^[0-9a-f]{64}$') { throw 'KNOWLEDGE_INVALID: binding ObservationIds must be SHA-256 identifiers.' } }
            $identity = [ordered]@{ Kind = $entry.Kind; PlaylistId = $entry.PlaylistId; SourceId = $entry.SourceId; SourceChannelReference = $entry.SourceChannelReference; ChannelId = $entry.ChannelId; EffectiveFromUtc = $entry.EffectiveFromUtc; EffectiveToUtc = $entry.EffectiveToUtc }
            $entry.EntryId = Get-ChannelForgeDomainHash -Domain 'knowledge-entry/v1' -InputObject $identity
        }
        'ProposeAlias' {
            $entry.Kind = 'ProgrammeAlias'; $entry.ScopeKind = 'Contextual'; $entry.ApprovalStatus = 'Proposed'
            $entry.Sides = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides $source.Sides)
            $entry.Context = [ordered]@{ EventStartUtc = @($entry.Sides | Sort-Object StartUtc | Select-Object -First 1).StartUtc; EventStopUtc = @($entry.Sides | Sort-Object StopUtc -Descending | Select-Object -First 1).StopUtc }
            $entry.ContextKey = Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $entry.Sides)
            $inputRecords = if ($null -ne $source.EvidenceRecords) { @($source.EvidenceRecords) } else { @([pscustomobject][ordered]@{ Sides = $entry.Sides; ObservationIds = @($entry.Sides | ForEach-Object ObservationId | Sort-Object -Unique); ConfidenceScore = $source.ConfidenceScore; CorrelationBasis = $source.CorrelationBasis }) }
            $records = [System.Collections.Generic.List[object]]::new()
            foreach ($record in $inputRecords) {
                $sides = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides $record.Sides)
                $pairIds = @($record.ObservationIds | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
                $sideIds = @($sides | ForEach-Object ObservationId | Sort-Object -Unique)
                if ($pairIds.Count -ne 2 -or ($pairIds -join '|') -cne ($sideIds -join '|')) { throw 'KNOWLEDGE_INVALID: proposal evidence ObservationIds must match its two side observations.' }
                $contextKey = Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $sides)
                if ($contextKey -cne [string]$entry.ContextKey) { throw 'KNOWLEDGE_INVALID: proposal evidence does not match the alias context.' }
                $score = [int]$record.ConfidenceScore
                if ($score -lt 0 -or $score -gt 100) { throw 'KNOWLEDGE_INVALID: ConfidenceScore must be between 0 and 100.' }
                $basis = @($record.CorrelationBasis | ForEach-Object { ConvertTo-ChannelForgeKnowledgeText $_ 'CorrelationBasis' 128 } | Sort-Object -Unique)
                if ($basis.Count -eq 0) { throw 'KNOWLEDGE_INVALID: CorrelationBasis is required.' }
                [void]$records.Add([pscustomobject][ordered]@{ ObservationIds = $pairIds; Sides = $sides; ConfidenceScore = $score; CorrelationBasis = $basis })
            }
            if ($records.Count -eq 0) { throw 'KNOWLEDGE_INVALID: at least one complete evidence record is required.' }
            $entry.EvidenceRecords = @($records.ToArray())
            $entry.ObservationIds = @($entry.EvidenceRecords | ForEach-Object ObservationIds | Sort-Object -Unique)
            $entry.EvidenceCount = $entry.ObservationIds.Count
            $entry.ConfidenceScore = [int](($entry.EvidenceRecords | Measure-Object -Property ConfidenceScore -Minimum).Minimum)
            $entry.EffectiveFromUtc = ConvertTo-ChannelForgeKnowledgeUtc $source.EffectiveFromUtc 'EffectiveFromUtc' -Optional
            $entry.EffectiveToUtc = ConvertTo-ChannelForgeKnowledgeUtc $source.EffectiveToUtc 'EffectiveToUtc' -Optional
            if ($entry.EffectiveFromUtc -and $entry.EffectiveToUtc -and [datetimeoffset]$entry.EffectiveToUtc -le [datetimeoffset]$entry.EffectiveFromUtc) { throw 'KNOWLEDGE_INVALID: alias effective interval must be positive.' }
            $entry.EntryId = $entry.ContextKey
        }
        default { throw 'KNOWLEDGE_INVALID: unsupported knowledge plan action.' }
    }
    $entry.History = @()
    return [pscustomobject]$entry
}

function ConvertTo-ChannelForgeKnowledgeAliasSides {
    param([Parameter(Mandatory)][object[]]$Sides)
    if (@($Sides).Count -ne 2) { throw 'KNOWLEDGE_INVALID: contextual alias requires exactly two correlated sides.' }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($side in @($Sides)) {
        $channelId = ConvertTo-ChannelForgeKnowledgeText $side.ChannelId 'Side.ChannelId' 128
        $sourceId = ConvertTo-ChannelForgeKnowledgeText $side.SourceId 'Side.SourceId' 128
        $title = ConvertTo-ChannelForgeKnowledgeText $side.Title 'Side.Title'
        $observationId = ([string]$side.ObservationId).ToLowerInvariant()
        if ($observationId -notmatch '^[0-9a-f]{64}$') { throw 'KNOWLEDGE_INVALID: side ObservationId is invalid.' }
        $start = ConvertTo-ChannelForgeKnowledgeUtc $side.StartUtc 'Side.StartUtc'
        $stop = ConvertTo-ChannelForgeKnowledgeUtc $side.StopUtc 'Side.StopUtc'
        if ([datetimeoffset]$stop -le [datetimeoffset]$start) { throw 'KNOWLEDGE_INVALID: side airing interval must be positive.' }
        $categories = @($side.CategoryKeys | ForEach-Object { ConvertTo-ChannelForgeKnowledgeText $_ 'Side.CategoryKey' 128 } | Sort-Object -Unique)
        $participants = @($side.Participants | ForEach-Object { ConvertTo-ChannelForgeKnowledgeText $_ 'Side.Participant' } | Sort-Object -Unique)
        $relationship = [string]$side.SourceRelationship
        if ($relationship -notin @('Authoritative','Independent','Mirror','Unknown')) { throw 'KNOWLEDGE_INVALID: Side.SourceRelationship is invalid.' }
        $result.Add([pscustomobject][ordered]@{
            ChannelId = $channelId
            Title = $title
            Subtitle = if ([string]::IsNullOrWhiteSpace([string]$side.Subtitle)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.Subtitle 'Side.Subtitle' }
            EventStatus = if ([string]::IsNullOrWhiteSpace([string]$side.EventStatus)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.EventStatus 'Side.EventStatus' 128 }
            ObservationId = $observationId
            SourceId = $sourceId
            SourceFamily = ConvertTo-ChannelForgeKnowledgeText $side.SourceFamily 'Side.SourceFamily' 128
            SourceRelationship = $relationship
            EvidenceClass = ConvertTo-ChannelForgeKnowledgeText $side.EvidenceClass 'Side.EvidenceClass' 128
            ChannelReference = if ([string]::IsNullOrWhiteSpace([string]$side.ChannelReference)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.ChannelReference 'Side.ChannelReference' 256 }
            CategoryKeys = $categories
            Participants = $participants
            EpisodeNumber = if ([string]::IsNullOrWhiteSpace([string]$side.EpisodeNumber)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.EpisodeNumber 'Side.EpisodeNumber' 128 }
            Competition = if ([string]::IsNullOrWhiteSpace([string]$side.Competition)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.Competition 'Side.Competition' }
            StartUtc = $start
            StopUtc = $stop
            SourceRecordReference = if ([string]::IsNullOrWhiteSpace([string]$side.SourceRecordReference)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.SourceRecordReference 'Side.SourceRecordReference' 256 }
            Description = if ([string]::IsNullOrWhiteSpace([string]$side.Description)) { $null } else { ConvertTo-ChannelForgeKnowledgeText $side.Description 'Side.Description' 512 }
            SourceDataTimeUtc = ConvertTo-ChannelForgeKnowledgeUtc $side.SourceDataTimeUtc 'Side.SourceDataTimeUtc' -Optional
            ObservationTimeUtc = ConvertTo-ChannelForgeKnowledgeUtc $side.ObservationTimeUtc 'Side.ObservationTimeUtc' -Optional
            FetchTimeUtc = ConvertTo-ChannelForgeKnowledgeUtc $side.FetchTimeUtc 'Side.FetchTimeUtc' -Optional
        }) | Out-Null
    }
    $values = @($result.ToArray())
    if ([string]$values[0].ChannelId -ceq [string]$values[1].ChannelId) { throw 'KNOWLEDGE_INVALID: contextual alias sides must use distinct registered ChannelIds.' }
    if ([string]::CompareOrdinal([string]$values[0].ChannelId,[string]$values[1].ChannelId) -gt 0) { return @($values[1],$values[0]) }
    return $values
}

function ConvertTo-ChannelForgeKnowledgeContextText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $normalized = ([string]$Value).Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant()
    $normalized = [regex]::Replace($normalized, '\p{Mn}', '')
    return [regex]::Replace($normalized, '[^\p{L}\p{N}]+', ' ').Trim()
}

function Get-ChannelForgeKnowledgeAliasContextProjection {
    param([Parameter(Mandatory)][object[]]$Sides)
    return [ordered]@{ Sides = @($Sides | ForEach-Object { [ordered]@{ ChannelId = $_.ChannelId; Title = ConvertTo-ChannelForgeKnowledgeContextText $_.Title; Subtitle = ConvertTo-ChannelForgeKnowledgeContextText $_.Subtitle; EventStatus = ConvertTo-ChannelForgeKnowledgeContextText $_.EventStatus; CategoryKeys = @($_.CategoryKeys | ForEach-Object { ConvertTo-ChannelForgeKnowledgeContextText $_ } | Where-Object { $_ } | Sort-Object -Unique); Participants = @($_.Participants | ForEach-Object { ConvertTo-ChannelForgeKnowledgeContextText $_ } | Where-Object { $_ } | Sort-Object -Unique); EpisodeNumber = ConvertTo-ChannelForgeKnowledgeContextText $_.EpisodeNumber; Competition = ConvertTo-ChannelForgeKnowledgeContextText $_.Competition; StartUtc = $_.StartUtc; StopUtc = $_.StopUtc } }) }
}

function Invoke-ChannelForgeKnowledgeChangePlanInternal {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][datetimeoffset]$AppliedAtUtc)
    if ([string]$Plan.Version -cne $script:ChannelForgeKnowledgePlanVersion -or [string]$Plan.PlanHash -cne (Get-ChannelForgeKnowledgePlanHash -Plan $Plan)) { throw 'FAIL_CLOSED: knowledge change plan integrity check failed.' }
    if ([int]$Plan.BaseRevision -ne [int]$State.Revision -or [string]$Plan.BaseStateHash -cne [string]$State.StateHash) { throw 'FAIL_CLOSED: knowledge change plan is stale.' }
    $revision = [int]$State.Revision + 1
    $at = $AppliedAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($State.Entries)) { $entries.Add($entry) }
    $audit = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($State.AuditTrail)) { $audit.Add($record) }
    foreach ($action in @($Plan.Actions)) {
        $operation = [string]$action.Action
        $entryId = if ($null -ne $action.EntryId) { [string]$action.EntryId } else { [string]$action.Entry.EntryId }
        $existing = @($entries | Where-Object { [string]$_.EntryId -ceq $entryId }) | Select-Object -First 1
        $previousStatus = if ($null -eq $existing) { $null } else { [string]$existing.ApprovalStatus }
        if ($operation -in @('RegisterIdentity','AddBinding','ProposeAlias')) {
            if ($null -ne $existing) { throw 'FAIL_CLOSED: knowledge entry already exists.' }
            $new = [ordered]@{}
            foreach ($property in @($action.Entry.PSObject.Properties)) { $new[$property.Name] = $property.Value }
            if ($new.Kind -eq 'ChannelBinding' -and @($entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $new.ChannelId -and $_.ApprovalStatus -eq 'Approved' -and (Test-ChannelForgeKnowledgeEffectiveInterval $_ $AppliedAtUtc) }).Count -ne 1) { throw 'FAIL_CLOSED: binding target ChannelId is not uniquely registered and active.' }
            if ($new.Kind -eq 'ProgrammeAlias') {
                foreach ($side in @($new.Sides)) {
                    if (@($entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $side.ChannelId -and $_.ApprovalStatus -eq 'Approved' -and (Test-ChannelForgeKnowledgeEffectiveInterval $_ $AppliedAtUtc) }).Count -ne 1) { throw 'FAIL_CLOSED: contextual alias side references an unregistered or inactive ChannelId.' }
                }
                if (@($entries | Where-Object { $_.Kind -eq 'ProgrammeAlias' -and $_.ContextKey -ceq $new.ContextKey }).Count -gt 0) { throw 'FAIL_CLOSED: contextual alias ContextKey already exists; append evidence or transition the existing entry.' }
            }
            if ($new.Kind -eq 'ChannelIdentity' -and @($entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $new.ChannelId }).Count -gt 0) { throw 'FAIL_CLOSED: canonical ChannelId is already registered.' }
            $status = [string]$new.ApprovalStatus
            $new.Revision = $revision
            $new.FirstSeenAtUtc = $at
            $new.LastSeenAtUtc = $at
            $new.Reason = [string]$action.Reason
            if ($new.Kind -eq 'ChannelIdentity' -and -not $new.EffectiveFromUtc) { $new.EffectiveFromUtc = $at }
            $historyAction = switch ($operation) { 'RegisterIdentity' {'Register'} 'AddBinding' {'Bind'} 'ProposeAlias' {'Propose'} }
            $new.History = @($new.History) + @([ordered]@{ Revision = $revision; Action = $historyAction; AtUtc = $at; Reason = [string]$action.Reason; PreviousStatus = $null; ApprovalStatus = $status })
            $entries.Add([pscustomobject]$new)
        } elseif ($operation -eq 'AppendAliasEvidence') {
            if ($null -eq $existing -or $existing.Kind -ne 'ProgrammeAlias' -or $existing.ApprovalStatus -eq 'Revoked') { throw 'FAIL_CLOSED: evidence target is not an active contextual alias.' }
            $priorObservationIds = @($existing.ObservationIds)
            $actionObservationIds = @($action.ObservationIds)
            $allObservationIds = @($priorObservationIds + $actionObservationIds | Sort-Object -Unique)
            $existingRecords = [System.Collections.Generic.List[object]]::new()
            foreach ($record in @($existing.EvidenceRecords)) { $existingRecords.Add($record) }
            $recordKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($record in @($existing.EvidenceRecords)) { [void]$recordKeys.Add(@($record.ObservationIds | Sort-Object) -join '|') }
            foreach ($record in @($action.EvidenceRecords)) {
                $sides = @(ConvertTo-ChannelForgeKnowledgeAliasSides -Sides $record.Sides)
                $pairIds = @($record.ObservationIds | Sort-Object -Unique)
                $sideIds = @($sides | ForEach-Object ObservationId | Sort-Object -Unique)
                if (($sideIds -join '|') -cne ($pairIds -join '|')) { throw 'FAIL_CLOSED: appended evidence identities do not match its sides.' }
                if ((Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject (Get-ChannelForgeKnowledgeAliasContextProjection -Sides $sides)) -cne [string]$existing.ContextKey) { throw 'FAIL_CLOSED: appended evidence does not match the alias context.' }
                $recordKey = $pairIds -join '|'
                if ($recordKeys.Add($recordKey)) { $existingRecords.Add([pscustomobject][ordered]@{ ObservationIds = $pairIds; Sides = $sides; ConfidenceScore = [int]$record.ConfidenceScore; CorrelationBasis = @($record.CorrelationBasis) }) }
            }
            $recordObservationIds = @($existingRecords.ToArray() | ForEach-Object { $_.ObservationIds } | Sort-Object -Unique)
            if (($recordObservationIds -join '|') -cne ($allObservationIds -join '|')) { throw 'FAIL_CLOSED: appended evidence must preserve every observation reference.' }
            $newObservationIds = @($actionObservationIds | Where-Object { $_ -notin $priorObservationIds })
            $existing.EvidenceRecords = @($existingRecords.ToArray())
            $existing.ObservationIds = $allObservationIds
            $existing.EvidenceCount = $allObservationIds.Count
            $existing.Revision = $revision
            $existing.LastSeenAtUtc = $at
            $existing.History = @($existing.History) + @([ordered]@{ Revision = $revision; Action = 'Observe'; AtUtc = $at; Reason = [string]$action.Reason; PreviousStatus = $previousStatus; ApprovalStatus = [string]$existing.ApprovalStatus })
        } else {
            if ($null -eq $existing) { throw 'FAIL_CLOSED: knowledge transition target does not exist.' }
            $kind = [string]$existing.Kind
            $oldStatus = [string]$existing.ApprovalStatus
            if ($kind -eq 'ChannelIdentity' -and $operation -ne 'Revoke') { throw 'FAIL_CLOSED: canonical identity can only be revoked after explicit registration.' }
            if ($oldStatus -eq 'Revoked' -or ($operation -eq 'Approve' -and $oldStatus -notin @('Proposed','Probationary')) -or ($operation -eq 'Reject' -and ($kind -eq 'ChannelIdentity' -or $oldStatus -notin @('Proposed','Probationary'))) -or ($operation -eq 'MarkProbationary' -and ($kind -ne 'ProgrammeAlias' -or $oldStatus -ne 'Proposed'))) { throw 'FAIL_CLOSED: invalid knowledge status transition.' }
            if ($operation -eq 'Revoke' -and $kind -eq 'ChannelIdentity') {
                if (@($entries | Where-Object { $_.Kind -eq 'ChannelBinding' -and $_.ChannelId -ceq $existing.ChannelId -and $_.ApprovalStatus -eq 'Approved' }).Count -gt 0 -or @($entries | Where-Object { $_.Kind -eq 'ProgrammeAlias' -and $_.ApprovalStatus -eq 'Approved' -and @($_.Sides | Where-Object { $_.ChannelId -ceq $existing.ChannelId }).Count -gt 0 }).Count -gt 0) { throw 'FAIL_CLOSED: active bindings and aliases must be revoked before their identity.' }
            }
            if ($operation -eq 'MarkProbationary') {
                $qualifyingRecords = @($existing.EvidenceRecords | Where-Object { [int]$_.ConfidenceScore -ge 85 -and @($_.Sides).Count -eq 2 -and @($_.Sides | Where-Object { $_.SourceRelationship -notin @('Authoritative','Independent') }).Count -eq 0 -and ([string]$_.Sides[0].SourceId -cne [string]$_.Sides[1].SourceId) })
                $independentSourceIds = @($qualifyingRecords | ForEach-Object { $_.Sides.SourceId } | Sort-Object -Unique)
                if ($qualifyingRecords.Count -lt 2 -or $independentSourceIds.Count -lt 2) { throw 'FAIL_CLOSED: probationary aliases require two repeated strong evidence pairs from independent non-mirror sources.' }
            }
            if ($operation -eq 'Approve' -and $kind -eq 'ChannelBinding' -and @($entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $existing.ChannelId -and $_.ApprovalStatus -eq 'Approved' -and (Test-ChannelForgeKnowledgeEffectiveInterval $_ $AppliedAtUtc) }).Count -ne 1) { throw 'FAIL_CLOSED: binding target identity is not uniquely active.' }
            if ($operation -eq 'Approve' -and $kind -eq 'ProgrammeAlias') {
                foreach ($side in @($existing.Sides)) {
                    if (@($entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $side.ChannelId -and $_.ApprovalStatus -eq 'Approved' -and (Test-ChannelForgeKnowledgeEffectiveInterval $_ $AppliedAtUtc) }).Count -ne 1) { throw 'FAIL_CLOSED: contextual alias side identity is not uniquely active.' }
                }
            }
            $newStatus = switch ($operation) { 'Approve' {'Approved'} 'Reject' {'Rejected'} 'Revoke' {'Revoked'} 'MarkProbationary' {'Probationary'} }
            if ($operation -eq 'Approve' -and -not $existing.EffectiveFromUtc) { $existing.EffectiveFromUtc = $at }
            $existing.ApprovalStatus = $newStatus
            $existing.Reason = [string]$action.Reason
            $existing.Revision = $revision
            $existing.LastSeenAtUtc = $at
            $existing.History = @($existing.History) + @([ordered]@{ Revision = $revision; Action = $operation; AtUtc = $at; Reason = [string]$action.Reason; PreviousStatus = $oldStatus; ApprovalStatus = $newStatus })
        }
        $currentEntry = @($entries | Where-Object { [string]$_.EntryId -ceq $entryId }) | Select-Object -First 1
        $auditAction = switch ($operation) { 'RegisterIdentity' {'Register'} 'AddBinding' {'Bind'} 'ProposeAlias' {'Propose'} 'AppendAliasEvidence' {'Observe'} default { $operation } }
        [void]$audit.Add([pscustomobject][ordered]@{ Revision = $revision; EntryId = $entryId; Action = $auditAction; AtUtc = $at; Reason = [string]$action.Reason; PreviousStatus = $previousStatus; ApprovalStatus = [string]$currentEntry.ApprovalStatus })
    }
    $next = [ordered]@{ Version = $script:ChannelForgeKnowledgeVersion; Revision = $revision; Entries = @($entries.ToArray() | Sort-Object EntryId); AuditTrail = @($audit.ToArray()); StateHash = $null }
    $next.StateHash = Get-ChannelForgeKnowledgeHash -State ([pscustomobject]$next)
    return [pscustomobject]$next
}

function Test-ChannelForgeKnowledgeEffectiveInterval {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][datetimeoffset]$AtUtc)
    $at = $AtUtc.ToUniversalTime()
    if ($Entry.EffectiveFromUtc -and $at -lt [datetimeoffset]$Entry.EffectiveFromUtc) { return $false }
    if ($Entry.EffectiveToUtc -and $at -ge [datetimeoffset]$Entry.EffectiveToUtc) { return $false }
    return $true
}

function Get-ChannelForgeKnowledgePlanHash {
    param([Parameter(Mandatory)]$Plan)
    $projection = [ordered]@{}; foreach ($property in @($Plan.PSObject.Properties)) { if ($property.Name -cne 'PlanHash') { $projection[$property.Name] = $property.Value } }
    return Get-ChannelForgeDomainHash -Domain 'knowledge-change-plan/v1' -InputObject $projection
}

function Remove-ChannelForgeKnowledgeBackup {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $directoryHandles = [ChannelForge.KnowledgeNativeIO]::OpenDirectoryChain($paths.Directory)
    try {
        $backups = @(Get-ChildItem -LiteralPath $paths.Directory -Filter 'learned.json.r*.bak' -File | Sort-Object { [long]([regex]::Match($_.Name,'\.r([0-9]+)\.bak$').Groups[1].Value) } -Descending)
        foreach ($old in @($backups | Select-Object -Skip 10)) {
            $handle = [ChannelForge.KnowledgeNativeIO]::OpenFile($directoryHandles[-1],$old.Name,$false,$false,$true,0,$true)
            if ($null -ne $handle) { try { [ChannelForge.KnowledgeNativeIO]::Delete($handle) } finally { $handle.Dispose() } }
        }
    }
    finally { foreach ($handle in $directoryHandles) { $handle.Dispose() } }
}
