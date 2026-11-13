function Import-ChannelForgeKnowledgeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][ValidateSet('IMPORT')][string]$ConfirmImport,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [datetimeoffset]$ImportedAtUtc = ([datetimeoffset]::UtcNow)
    )

    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $sourcePath = if ([System.IO.Path]::IsPathRooted($InputPath)) { $InputPath } else { Join-Path $paths.Root $InputPath }
    $source = Read-ChannelForgeKnowledgeFile -Path $sourcePath -RepositoryRoot $paths.Root
    $current = Read-ChannelForgeKnowledgeState -RepositoryRoot $paths.Root
    if ([string]$source.StateHash -ceq [string]$current.StateHash -or @($current.AuditTrail | Where-Object { [string]$_.OriginStateHash -ceq [string]$source.StateHash }).Count -gt 0) { return $current }

    $revision = [int]$current.Revision + 1
    $at = $ImportedAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($current.Entries)) { $entries.Add($entry) }
    $audit = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($current.AuditTrail)) { $audit.Add($record) }
    foreach ($entry in @($source.Entries)) {
        $existing = @($entries | Where-Object { [string]$_.EntryId -ceq [string]$entry.EntryId }) | Select-Object -First 1
        if ($null -ne $existing) {
            if ((ConvertTo-ChannelForgeCanonicalJson -InputObject $existing) -cne (ConvertTo-ChannelForgeCanonicalJson -InputObject $entry)) { throw 'KNOWLEDGE_CONFLICT: imported EntryId differs from canonical state; review a change plan instead.' }
            continue
        }
        $copy = ConvertFrom-Json -InputObject (ConvertTo-ChannelForgeCanonicalJson -InputObject $entry) -DateKind String -ErrorAction Stop
        foreach ($history in @($copy.History)) { Add-Member -InputObject $history -MemberType NoteProperty -Name OriginRevision -Value ([int]$history.Revision) -Force; Add-Member -InputObject $history -MemberType NoteProperty -Name OriginStateHash -Value ([string]$source.StateHash) -Force; $history.Revision = $revision }
        $copy.Revision = $revision
        $copy.History = @($copy.History) + @([ordered]@{ Revision = $revision; OriginRevision = [int]$entry.Revision; OriginStateHash = [string]$source.StateHash; Action = 'Import'; AtUtc = $at; Reason = "Imported validated state $($source.StateHash)."; PreviousStatus = $null; ApprovalStatus = [string]$entry.ApprovalStatus })
        $entries.Add($copy)
        [void]$audit.Add([pscustomobject][ordered]@{ Revision = $revision; OriginRevision = [int]$entry.Revision; OriginStateHash = [string]$source.StateHash; EntryId = [string]$entry.EntryId; Action = 'Import'; AtUtc = $at; Reason = "Imported validated state $($source.StateHash)."; PreviousStatus = $null; ApprovalStatus = [string]$entry.ApprovalStatus })
    }
    foreach ($record in @($source.AuditTrail)) {
        [void]$audit.Add([pscustomobject][ordered]@{ Revision = $revision; OriginRevision = [int]$record.Revision; OriginStateHash = [string]$source.StateHash; EntryId = [string]$record.EntryId; Action = 'Import'; AtUtc = [string]$record.AtUtc; Reason = [string]$record.Reason; PreviousStatus = $record.PreviousStatus; ApprovalStatus = [string]$record.ApprovalStatus })
    }
    $next = [ordered]@{ Version = 'knowledge-state/v1'; Revision = $revision; Entries = @($entries.ToArray() | Sort-Object EntryId); AuditTrail = @($audit.ToArray()); StateHash = $null }
    $next.StateHash = Get-ChannelForgeKnowledgeHash -State ([pscustomobject]$next)
    Assert-ChannelForgeKnowledgeState -State ([pscustomobject]$next) -SchemaPath $paths.SchemaPath
    Write-ChannelForgeKnowledgeStateAtomic -State ([pscustomobject]$next) -RepositoryRoot $paths.Root
    return [pscustomobject]$next
}
