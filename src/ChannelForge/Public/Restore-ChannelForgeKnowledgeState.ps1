function Restore-ChannelForgeKnowledgeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(0,[int]::MaxValue)][int]$BackupRevision,
        [Parameter(Mandatory)][ValidateSet('RESTORE')][string]$ConfirmRestore,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [datetimeoffset]$RestoredAtUtc = ([datetimeoffset]::UtcNow)
    )

    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $target = Read-ChannelForgeKnowledgeFile -Path ($paths.StatePath + '.r' + [string]$BackupRevision + '.bak') -RepositoryRoot $paths.Root
    if ([int]$target.Revision -ne $BackupRevision) { throw 'FAIL_CLOSED: selected knowledge backup revision does not match its filename.' }
    $current = Read-ChannelForgeKnowledgeState -RepositoryRoot $paths.Root
    $revision = [int]$current.Revision + 1
    $at = $RestoredAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $targetById = @{}
    foreach ($entry in @($target.Entries)) { $targetById[[string]$entry.EntryId] = $entry }
    $currentById = @{}
    foreach ($entry in @($current.Entries)) { $currentById[[string]$entry.EntryId] = $entry }
    $entries = [System.Collections.Generic.List[object]]::new()
    $audit = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($current.AuditTrail)) { $audit.Add($record) }
    foreach ($entry in @($current.Entries)) {
        $copy = if ($targetById.ContainsKey([string]$entry.EntryId)) { ConvertFrom-Json -InputObject (ConvertTo-ChannelForgeCanonicalJson -InputObject $targetById[[string]$entry.EntryId]) -DateKind String } else { ConvertFrom-Json -InputObject (ConvertTo-ChannelForgeCanonicalJson -InputObject $entry) -DateKind String }
        $previousStatus = [string]$entry.ApprovalStatus
        $desiredStatus = if ($targetById.ContainsKey([string]$entry.EntryId)) { [string]$copy.ApprovalStatus } else { 'Revoked' }
        if ($desiredStatus -eq 'Approved' -and $copy.Kind -in @('ChannelBinding','ProgrammeAlias')) {
            $requiredChannelIds = if ($copy.Kind -eq 'ChannelBinding') { @([string]$copy.ChannelId) } else { @($copy.Sides | ForEach-Object { [string]$_.ChannelId }) }
            foreach ($channelId in $requiredChannelIds) {
                $identity = @($target.Entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $channelId -and $_.ApprovalStatus -eq 'Approved' -and (Test-ChannelForgeKnowledgeEffectiveInterval $_ $RestoredAtUtc) })
                if ($identity.Count -ne 1) { $desiredStatus = 'Revoked'; break }
            }
        }
        if ($copy.Kind -eq 'ProgrammeAlias') {
            $recordsByPair = @{}
            foreach ($record in @($copy.EvidenceRecords) + @($entry.EvidenceRecords)) {
                $pairKey = @($record.ObservationIds | Sort-Object -Unique) -join '|'
                if (-not $recordsByPair.ContainsKey($pairKey)) { $recordsByPair[$pairKey] = $record }
            }
            $copy.EvidenceRecords = @($recordsByPair.Keys | Sort-Object | ForEach-Object { $recordsByPair[$_] })
            $copy.ObservationIds = @($copy.EvidenceRecords | ForEach-Object ObservationIds | Sort-Object -Unique)
            $copy.EvidenceCount = $copy.ObservationIds.Count
            if ([datetimeoffset]$entry.LastSeenAtUtc -gt [datetimeoffset]$copy.LastSeenAtUtc) { $copy.LastSeenAtUtc = [string]$entry.LastSeenAtUtc }
        } else {
            $copy.ObservationIds = @(@($copy.ObservationIds) + @($entry.ObservationIds) | Sort-Object -Unique)
        }
        $copy.ApprovalStatus = $desiredStatus
        $copy.Revision = $revision
        $history = [System.Collections.Generic.List[object]]::new()
        $historyKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($record in @($entry.History) + @($copy.History)) {
            $recordKey = ConvertTo-ChannelForgeCanonicalJson -InputObject $record
            if ($historyKeys.Add($recordKey)) { $history.Add($record) }
        }
        $copy.History = @($history.ToArray()) + @([ordered]@{ Revision = $revision; OriginRevision = [int]$target.Revision; OriginStateHash = [string]$target.StateHash; Action = 'Restore'; AtUtc = $at; Reason = "Restored from validated revision $BackupRevision."; PreviousStatus = $previousStatus; ApprovalStatus = $desiredStatus })
        $entries.Add($copy)
        [void]$audit.Add([pscustomobject][ordered]@{ Revision = $revision; OriginRevision = [int]$target.Revision; OriginStateHash = [string]$target.StateHash; EntryId = [string]$entry.EntryId; Action = 'Restore'; AtUtc = $at; Reason = "Restored from validated revision $BackupRevision."; PreviousStatus = $previousStatus; ApprovalStatus = $desiredStatus })
    }
    foreach ($entry in @($target.Entries | Where-Object { -not $currentById.ContainsKey([string]$_.EntryId) })) {
        $copy = ConvertFrom-Json -InputObject (ConvertTo-ChannelForgeCanonicalJson -InputObject $entry) -DateKind String
        if ($copy.ApprovalStatus -eq 'Approved' -and $copy.Kind -in @('ChannelBinding','ProgrammeAlias')) {
            $requiredChannelIds = if ($copy.Kind -eq 'ChannelBinding') { @([string]$copy.ChannelId) } else { @($copy.Sides | ForEach-Object { [string]$_.ChannelId }) }
            foreach ($channelId in $requiredChannelIds) {
                $identity = @($target.Entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ChannelId -ceq $channelId -and $_.ApprovalStatus -eq 'Approved' -and (Test-ChannelForgeKnowledgeEffectiveInterval $_ $RestoredAtUtc) })
                if ($identity.Count -ne 1) { $copy.ApprovalStatus = 'Revoked'; break }
            }
        }
        $status = [string]$copy.ApprovalStatus
        $copy.Revision = $revision
        $copy.History = @($copy.History) + @([ordered]@{ Revision = $revision; OriginRevision = [int]$target.Revision; OriginStateHash = [string]$target.StateHash; Action = 'Restore'; AtUtc = $at; Reason = "Restored from validated revision $BackupRevision."; PreviousStatus = $null; ApprovalStatus = $status })
        $entries.Add($copy)
        [void]$audit.Add([pscustomobject][ordered]@{ Revision = $revision; OriginRevision = [int]$target.Revision; OriginStateHash = [string]$target.StateHash; EntryId = [string]$copy.EntryId; Action = 'Restore'; AtUtc = $at; Reason = "Restored from validated revision $BackupRevision."; PreviousStatus = $null; ApprovalStatus = $status })
    }
    $next = [ordered]@{ Version = 'knowledge-state/v1'; Revision = $revision; Entries = @($entries.ToArray() | Sort-Object EntryId); AuditTrail = @($audit.ToArray()); StateHash = $null }
    $next.StateHash = Get-ChannelForgeKnowledgeHash -State ([pscustomobject]$next)
    Assert-ChannelForgeKnowledgeState -State ([pscustomobject]$next) -SchemaPath $paths.SchemaPath
    Write-ChannelForgeKnowledgeStateAtomic -State ([pscustomobject]$next) -RepositoryRoot $paths.Root
    return [pscustomobject]$next
}
