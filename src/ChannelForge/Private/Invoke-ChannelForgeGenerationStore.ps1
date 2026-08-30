$script:ChannelForgeGenerationAcceptanceVersion = 'blocker-2-contract/v8-acceptance'
$script:ChannelForgeGenerationStages = @('None', 'Prepared', 'GenerationPublished', 'PointerSwapped', 'Committed')

function Get-ChannelForgeGenerationStoreType {
    return Initialize-ChannelForgeGenerationStore
}

function Invoke-ChannelForgeGenerationFaultHook {
    param([AllowNull()][string]$FaultHook, [Parameter(Mandatory)][string]$Name)
    if ($null -ne $FaultHook -and $FaultHook -ceq $Name) {
        throw "FAULT_HOOK: $Name"
    }
}

function ConvertTo-ChannelForgeGenerationBytes {
    param([Parameter(Mandatory)][object]$InputObject)
    if ($InputObject -is [byte[]]) { return [byte[]]$InputObject }
    $ordered = ConvertTo-ChannelForgeGenerationCanonicalObject $InputObject
    return [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $ordered))
}

function ConvertTo-ChannelForgeGenerationCanonicalObject {
    param([AllowNull()]$InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [ValueType]) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($entry in $InputObject.GetEnumerator()) { $ordered[$entry.Key] = ConvertTo-ChannelForgeGenerationCanonicalObject $entry.Value }
        return $ordered
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        return ,@($InputObject | ForEach-Object { ConvertTo-ChannelForgeGenerationCanonicalObject $_ })
    }
    $ordered = [ordered]@{}
    foreach ($property in @($InputObject.PSObject.Properties)) { $ordered[$property.Name] = ConvertTo-ChannelForgeGenerationCanonicalObject $property.Value }
    return $ordered
}

function Test-ChannelForgeGenerationBytesEqual {
    param([Parameter(Mandatory)][byte[]]$Left, [Parameter(Mandatory)][byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Assert-ChannelForgeGenerationSafePath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowMissingLeaf
    )
    $null = Initialize-ChannelForgeGenerationStore
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ([System.IO.Path]::IsPathRooted($root) -and $root.StartsWith('\\')) {
        throw 'FAIL_CLOSED: UNC/SMB repository roots are not accepted.'
    }
    if ($full -cne $root) {
        $prefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'FAIL_CLOSED: path escapes the repository root.'
        }
    }
    $relative = [System.IO.Path]::GetRelativePath($root, $full)
    if ($relative -ne '.' -and ($relative -match '(^|[\\/]):|(^|[\\/])\.\.($|[\\/])')) {
        throw 'FAIL_CLOSED: unsafe relative path.'
    }
    $cursor = $root
    if ([System.IO.Directory]::Exists($cursor) -and [ChannelForge.GenerationStore]::IsReparsePoint($cursor)) {
        throw 'FAIL_CLOSED: repository root is a reparse point.'
    }
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrEmpty($part) -or $part -eq '.') { continue }
        $cursor = Join-Path $cursor $part
        if ([ChannelForge.GenerationStore]::Exists($cursor)) {
            if ([ChannelForge.GenerationStore]::IsReparsePoint($cursor)) {
                throw "FAIL_CLOSED: reparse point in authority path: $cursor"
            }
        }
        elseif (-not $AllowMissingLeaf) {
            throw "FAIL_CLOSED: required path is missing: $cursor"
        }
    }
    return $full
}

function Ensure-ChannelForgeGenerationDirectory {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$Path)
    $full = Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $Path -AllowMissingLeaf
    if (-not [System.IO.Directory]::Exists($full)) {
        [System.IO.Directory]::CreateDirectory($full) | Out-Null
    }
    Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $full
    return $full
}

function Get-ChannelForgeGenerationIdentityObject {
    param([Parameter(Mandatory)]$Identity)
    return [ordered]@{
        VolumeSerial = [uint64]$Identity.VolumeSerial
        FileId = [string]$Identity.FileId
        ByteLength = [uint64]$Identity.ByteLength
        LastWriteUtcTicks = [uint64]$Identity.LastWriteUtcTicks
    }
}

function Read-ChannelForgeGenerationFile {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Domain
    )
    $full = Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $Path
    $store = Get-ChannelForgeGenerationStoreType
    $stream = $null
    try {
        $stream = [ChannelForge.GenerationStore]::OpenRead($full)
        $memory = [System.IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
        }
        finally { $memory.Dispose() }
        $identity = Get-ChannelForgeGenerationIdentityObject ([ChannelForge.GenerationStore]::ReadIdentity($stream))
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    return [pscustomobject][ordered]@{
        Path = $full
        Bytes = [byte[]]$bytes
        ByteLength = [uint64]$bytes.Length
        ContentHash = Get-ChannelForgeDomainHash -Domain $Domain -Bytes $bytes
        FileIdentity = $identity
    }
}

function Read-ChannelForgeGenerationDocument {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Domain
    )
    $file = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path $Path -Domain $Domain
    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($file.Bytes)
        $object = ConvertFrom-Json -InputObject $text -AsHashtable -Depth 100 -DateKind String -ErrorAction Stop
        $canonical = ConvertTo-ChannelForgeGenerationBytes $object
        if (-not (Test-ChannelForgeGenerationBytesEqual $file.Bytes $canonical)) {
            throw 'FAIL_CLOSED: canonical document bytes do not match the parsed object.'
        }
    }
    catch {
        throw "FAIL_CLOSED: invalid canonical document '$($file.Path)': $($_.Exception.Message)"
    }
    $file | Add-Member -NotePropertyName Object -NotePropertyValue $object -PassThru
}

function Write-ChannelForgeGenerationFile {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [AllowNull()][string]$FaultHook,
        [Parameter(Mandatory)][string]$WriteHook,
        [Parameter(Mandatory)][string]$FlushHook,
        [Parameter(Mandatory)][string]$ReopenHook,
        [Parameter(Mandatory)][string]$Domain
    )
    $full = Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $Path -AllowMissingLeaf
    $parent = Split-Path -Parent $full
    if (-not [System.IO.Directory]::Exists($parent)) { throw 'FAIL_CLOSED: staging parent is missing.' }
    $store = Get-ChannelForgeGenerationStoreType
    $stream = $null
    try {
        $stream = [ChannelForge.GenerationStore]::CreateExclusive($full)
        if ($FaultHook -ceq $WriteHook) {
            $partial = [Math]::Max(1, [Math]::Min($Bytes.Length, [int][Math]::Ceiling($Bytes.Length / 2.0)))
            $stream.Write($Bytes, 0, $partial)
            throw "FAULT_HOOK: $WriteHook"
        }
        $stream.Write($Bytes, 0, $Bytes.Length)
        if ($FaultHook -ceq $FlushHook) { throw "FAULT_HOOK: $FlushHook" }
        [ChannelForge.GenerationStore]::Flush($stream)
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    if ($FaultHook -ceq $ReopenHook) { throw "FAULT_HOOK: $ReopenHook" }
    $actual = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path $full -Domain $Domain
    if (-not (Test-ChannelForgeGenerationBytesEqual $actual.Bytes $Bytes) -or $actual.ByteLength -ne [uint64]$Bytes.Length) {
        throw 'FAIL_CLOSED: staged bytes changed during reopen verification.'
    }
    return $actual
}

function Get-ChannelForgeGenerationPaths {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $state = Join-Path $RepositoryRoot 'state'
    [ordered]@{
        State = $state
        Lock = Join-Path $state 'lineup-operation.lock'
        Current = Join-Path $state 'accepted-lineup.json'
        Previous = Join-Path $state 'accepted-lineup.json.previous'
        Journal = Join-Path $state 'accepted-lineup.journal.json'
        JournalPrevious = Join-Path $state 'accepted-lineup.journal.json.previous'
        Generations = Join-Path $state 'generations'
        Staging = Join-Path $state '.staging'
    }
}

function Assert-ChannelForgeGenerationId {
    param([Parameter(Mandatory)][string]$GenerationId)
    if ($GenerationId -cnotmatch '^[0-9a-f]{32}$') { throw 'FAIL_CLOSED: GenerationId must be 32 lowercase hexadecimal characters.' }
}
function Assert-ChannelForgeGenerationHash {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value -or ([string]$Value) -cnotmatch '^[0-9a-f]{64}$') { throw "FAIL_CLOSED: $Name must be lowercase 64-hex." }
}


function Test-ChannelForgeGenerationProjectionHash {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][string]$Property, [string[]]$Omit = @())
    $ordered = ConvertTo-ChannelForgeGenerationCanonicalObject $Object
    if ($null -eq $ordered[$Property]) { return $false }
    $input = [ordered]@{}
    foreach ($entry in $ordered.GetEnumerator()) {
        if ($entry.Key -ne $Property -and $entry.Key -notin $Omit) { $input[$entry.Key] = $entry.Value }
    }
    $actual = Get-ChannelForgeDomainHash -Domain $Domain -InputObject $input
    return $actual -ceq [string]$ordered[$Property]
}

function Get-ChannelForgeGenerationOutputProperty {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Names)
    foreach ($name in $Names) {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($name)) { return $Object[$name] }
        }
        elseif ($null -ne $Object.PSObject.Properties[$name]) { return $Object.$name }
    }
    return $null
}

function Assert-ChannelForgeGenerationInputs {
    param(
        [Parameter(Mandatory)]$GenerationManifest,
        [Parameter(Mandatory)]$AcceptedState,
        [Parameter(Mandatory)]$AcceptedOutputManifest,
        [Parameter(Mandatory)]$DecisionManifest,
        [Parameter(Mandatory)][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes
    )
    $GenerationManifest = [pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $GenerationManifest)
    $AcceptedState = [pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $AcceptedState)
    $AcceptedOutputManifest = [pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $AcceptedOutputManifest)
    $DecisionManifest = [pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $DecisionManifest)
    foreach ($pair in @(
        @($AcceptedState, 'AcceptedState'),
        @($AcceptedOutputManifest, 'AcceptedOutputManifest'),
        @($DecisionManifest, 'DecisionManifest')
    )) { Assert-ChannelForgeAcceptanceVersion $pair[0] $pair[1] }
    if (-not (Test-ChannelForgeGenerationProjectionHash $GenerationManifest 'generation-manifest/v2' 'GenerationManifestHash' @('GenerationId'))) { throw 'FAIL_CLOSED: invalid GenerationManifestHash.' }
    if (-not (Test-ChannelForgeGenerationProjectionHash $AcceptedState 'accepted-state/v2' 'AcceptedStateHash' @('GenerationId','AcceptedAtUtc'))) { throw 'FAIL_CLOSED: invalid AcceptedStateHash.' }
    $outputHashOmit = if ($null -ne $AcceptedOutputManifest.PSObject.Properties['OutputM3UHash']) { @() } else { @('GenerationId','AcceptedStateHash') }
    if (-not (Test-ChannelForgeGenerationProjectionHash $AcceptedOutputManifest 'previous-output-manifest/v2' 'OutputManifestHash' $outputHashOmit)) { throw 'FAIL_CLOSED: invalid OutputManifestHash.' }
    if (-not (Test-ChannelForgeGenerationProjectionHash $DecisionManifest 'decision-manifest/v2' 'DecisionManifestHash')) { throw 'FAIL_CLOSED: invalid DecisionManifestHash.' }
    $generationId = [string]$GenerationManifest.GenerationId
    Assert-ChannelForgeGenerationId $generationId
    foreach ($object in @($AcceptedState, $AcceptedOutputManifest)) {
        $objectGenerationId = Get-ChannelForgeGenerationOutputProperty $object @('GenerationId')
        if ($null -ne $objectGenerationId -and [string]$objectGenerationId -cne $generationId) { throw 'FAIL_CLOSED: generation identity mismatch.' }
    }
    if ([string]$GenerationManifest.AcceptedStateHash -cne [string]$AcceptedState.AcceptedStateHash -or [string]$GenerationManifest.AcceptedOutputManifestHash -cne [string]$AcceptedOutputManifest.OutputManifestHash -or [string]$GenerationManifest.DecisionManifestHash -cne [string]$DecisionManifest.DecisionManifestHash) { throw 'FAIL_CLOSED: generation linkage mismatch.' }
    $m3uHash = Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('OutputM3UHash','ActiveM3UHash')
    if ($M3UBytes.Length -eq 0 -or (Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $M3UBytes) -cne [string]$m3uHash) { throw 'FAIL_CLOSED: M3U bytes do not match the output manifest.' }
    $status = [string](Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('AcceptedXMLTVStatus','ActiveXMLTVStatus'))
    $outputXmlHash = Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('OutputXMLTVHash','ActiveXMLTVHash')
    $acceptedXmlHash = Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('AcceptedXMLTVHash')
    $xmlHash = if ($null -ne $outputXmlHash) { $outputXmlHash } else { $acceptedXmlHash }
    if ($status -eq 'Generated') {
        if ($null -eq $XMLTVBytes -or $XMLTVBytes.Length -eq 0 -or $null -eq $xmlHash -or (Get-ChannelForgeDomainHash -Domain 'active-xmltv/v2' -Bytes $XMLTVBytes) -cne [string]$xmlHash) { throw 'FAIL_CLOSED: Generated XMLTV bytes do not match the output manifest.' }
        if ($null -ne $outputXmlHash -and $null -ne $acceptedXmlHash -and [string]$outputXmlHash -cne [string]$acceptedXmlHash) { throw 'FAIL_CLOSED: Generated XMLTV hashes disagree.' }
    }
    elseif ($status -eq 'NotGenerated') {
        if ($null -ne $XMLTVBytes -and $XMLTVBytes.Length -gt 0) { throw 'FAIL_CLOSED: NotGenerated output cannot contain XMLTV bytes.' }
        if ($null -ne $outputXmlHash -or $null -ne $acceptedXmlHash) { throw 'FAIL_CLOSED: NotGenerated output has an XMLTV hash.' }
    }
    else { throw 'FAIL_CLOSED: unknown XMLTV status.' }
    return $generationId
}

function New-ChannelForgeGenerationPointer {
    param([Parameter(Mandatory)]$GenerationManifest,[Parameter(Mandatory)]$AcceptedState,[Parameter(Mandatory)]$AcceptedOutputManifest)
    $pointer = [ordered]@{
        Version = $script:ChannelForgeGenerationAcceptanceVersion
        GenerationId = [string]$GenerationManifest.GenerationId
        GenerationManifestHash = [string]$GenerationManifest.GenerationManifestHash
        AcceptedStateHash = [string]$AcceptedState.AcceptedStateHash
        AcceptedOutputManifestHash = [string]$AcceptedOutputManifest.OutputManifestHash
        PointerHash = $null
    }
    $pointer.PointerHash = Get-ChannelForgeAcceptanceHash -Domain 'pointer/v2' -Projection $pointer -HashProperty PointerHash
    return [pscustomobject]$pointer
}

function New-ChannelForgeGenerationMutationRecord {
    param([int]$Ordinal,[ValidateSet('Create','Replace','Move','Delete','Verify')][string]$Kind,[Parameter(Mandatory)][string]$RelativePath,[AllowNull()]$Old,[AllowNull()]$New)
    [pscustomobject][ordered]@{
        MutationOrdinal = $Ordinal
        MutationKind = $Kind
        RelativePath = $RelativePath
        ExpectedOldPresence = if ($null -eq $Old) { 'Absent' } else { 'Present' }
        ExpectedOldByteHash = if ($null -eq $Old) { $null } else { [string]$Old.ContentHash }
        ExpectedOldFileIdentity = if ($null -eq $Old) { $null } else { $Old.FileIdentity }
        ExpectedNewPresence = if ($null -eq $New) { 'Absent' } else { 'Present' }
        ExpectedNewByteHash = if ($null -eq $New) { $null } else { [string]$New.ContentHash }
        ExpectedNewFileIdentity = if ($null -eq $New) { $null } else { $New.FileIdentity }
    }
}

function New-ChannelForgeGenerationJournal {
    param([Parameter(Mandatory)][int]$Stage,[Parameter(Mandatory)][string]$TransactionId,[AllowNull()][string]$ExpectedOldPointerHash,[Parameter(Mandatory)][string]$ExpectedNewPointerHash,[AllowNull()][string]$ExpectedOldGenerationId,[Parameter(Mandatory)][string]$ExpectedNewGenerationId,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MutationRecords,[AllowNull()][string]$OldJournalHash)
    $journal = [ordered]@{
        Version = 2
        TransactionId = $TransactionId
        JournalStage = $Stage
        ExpectedOldPointerHash = $ExpectedOldPointerHash
        ExpectedNewPointerHash = $ExpectedNewPointerHash
        ExpectedOldGenerationId = $ExpectedOldGenerationId
        ExpectedNewGenerationId = $ExpectedNewGenerationId
        MutationRecords = @($MutationRecords | ForEach-Object { ConvertTo-ChannelForgeGenerationCanonicalObject $_ })
        OldJournalHash = $OldJournalHash
        JournalHash = $null
    }
    $journal.JournalHash = Get-ChannelForgeDomainHash -Domain 'journal/v2' -InputObject ([ordered]@{ Version=$journal.Version; TransactionId=$journal.TransactionId; JournalStage=$journal.JournalStage; ExpectedOldPointerHash=$journal.ExpectedOldPointerHash; ExpectedNewPointerHash=$journal.ExpectedNewPointerHash; ExpectedOldGenerationId=$journal.ExpectedOldGenerationId; ExpectedNewGenerationId=$journal.ExpectedNewGenerationId; MutationRecords=$journal.MutationRecords; OldJournalHash=$journal.OldJournalHash })
    return [pscustomobject]$journal
}

function Publish-ChannelForgeGenerationJournal {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$AuthoritativePath,[Parameter(Mandatory)][string]$StagedPath,[Parameter(Mandatory)]$Journal,[AllowNull()][string]$FaultHook,[Parameter(Mandatory)][string]$StageName)
    $bytes = ConvertTo-ChannelForgeGenerationBytes $Journal
    $writeHook = if ($StageName -eq 'Prepared') { 'JournalWrite.Prepared' } else { "JournalStageWrite.$StageName" }
    $flushHook = if ($StageName -eq 'Prepared') { 'JournalFlush.Prepared' } else { "JournalStageFlush.$StageName" }
    $reopenHook = if ($StageName -eq 'Prepared') { 'JournalReopenHash.Prepared' } else { "JournalStageReopenHash.$StageName" }
    Write-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path $StagedPath -Bytes $bytes -FaultHook $FaultHook -WriteHook $writeHook -FlushHook $flushHook -ReopenHook $reopenHook -Domain 'journal/v2' | Out-Null
    if ($StageName -eq 'Prepared') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalBeforeReplace.Prepared' }
    elseif ($StageName -eq 'GenerationPublished') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalBeforeReplace.GenerationPublished' }
    elseif ($StageName -eq 'PointerSwapped') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalBeforeReplace.PointerSwapped' }
    elseif ($StageName -eq 'Committed') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalBeforeReplace.Committed' }
    $authoritativeExists = [System.IO.File]::Exists($AuthoritativePath)
    $backup = "$AuthoritativePath.previous"
    if ($authoritativeExists) {
        if ([System.IO.File]::Exists($backup)) { throw 'FAIL_CLOSED: journal backup already exists.' }
        [ChannelForge.GenerationStore]::ReplaceFile($StagedPath, $AuthoritativePath, $backup)
    }
    else { [ChannelForge.GenerationStore]::MoveFile($StagedPath, $AuthoritativePath) }
    $verified = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $AuthoritativePath -Domain 'journal/v2'
    if ([string]$verified.Object.JournalHash -cne [string]$Journal.JournalHash) { throw 'FAIL_CLOSED: authoritative journal hash mismatch.' }
    if ($StageName -eq 'Prepared') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalAfterReplace.Prepared' }
    elseif ($StageName -eq 'GenerationPublished') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalAfterReplace.GenerationPublished' }
    elseif ($StageName -eq 'PointerSwapped') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalAfterReplace.PointerSwapped' }
    elseif ($StageName -eq 'Committed') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'JournalAfterReplace.Committed' }
    if ([System.IO.File]::Exists($backup)) { [ChannelForge.GenerationStore]::DeleteFile($backup) }
    return $verified
}

function Get-ChannelForgeGenerationCurrentSnapshot {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    if (-not [System.IO.File]::Exists($Paths.Current)) { return $null }
    $pointer = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $Paths.Current -Domain 'pointer/v2'
    if (-not (Test-ChannelForgeGenerationProjectionHash $pointer.Object 'pointer/v2' 'PointerHash')) { throw 'FAIL_CLOSED: invalid current pointer hash.' }
    Assert-ChannelForgeGenerationHash $pointer.Object.PointerHash 'PointerHash'
    Assert-ChannelForgeGenerationId ([string]$pointer.Object.GenerationId)
    $generation = Join-Path $Paths.Generations ([string]$pointer.Object.GenerationId)
    if (-not [System.IO.Directory]::Exists($generation)) { throw 'FAIL_CLOSED: current generation is missing.' }
    $manifest = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'generation.manifest.json') -Domain 'generation-manifest/v2'
    if (-not (Test-ChannelForgeGenerationProjectionHash $manifest.Object 'generation-manifest/v2' 'GenerationManifestHash' @('GenerationId'))) { throw 'FAIL_CLOSED: invalid current generation manifest hash.' }
    if ([string]$manifest.Object.GenerationId -cne [string]$pointer.Object.GenerationId -or [string]$manifest.Object.GenerationManifestHash -cne [string]$pointer.Object.GenerationManifestHash) { throw 'FAIL_CLOSED: current pointer/generation mismatch.' }
    $state = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'accepted-state.json') -Domain 'accepted-state/v2'
    $output = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'accepted-output.manifest.json') -Domain 'previous-output-manifest/v2'
    $decision = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'decision-manifest.json') -Domain 'decision-manifest/v2'
    $outputOmit = if ($null -ne $output.Object.PSObject.Properties['OutputM3UHash']) { @() } else { @('GenerationId','AcceptedStateHash') }
    if (-not (Test-ChannelForgeGenerationProjectionHash $state.Object 'accepted-state/v2' 'AcceptedStateHash' @('GenerationId','AcceptedAtUtc')) -or -not (Test-ChannelForgeGenerationProjectionHash $output.Object 'previous-output-manifest/v2' 'OutputManifestHash' $outputOmit) -or -not (Test-ChannelForgeGenerationProjectionHash $decision.Object 'decision-manifest/v2' 'DecisionManifestHash')) { throw 'FAIL_CLOSED: current generation semantic hash mismatch.' }
    $m3u = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'merged.m3u') -Domain 'active-m3u/v2'
    if ([string]$m3u.ContentHash -cne [string](Get-ChannelForgeGenerationOutputProperty $output.Object @('OutputM3UHash','ActiveM3UHash'))) { throw 'FAIL_CLOSED: current M3U hash mismatch.' }
    $xml = $null
    $status = [string](Get-ChannelForgeGenerationOutputProperty $output.Object @('AcceptedXMLTVStatus','ActiveXMLTVStatus'))
    $outputXmlHash = Get-ChannelForgeGenerationOutputProperty $output.Object @('OutputXMLTVHash','ActiveXMLTVHash')
    $acceptedXmlHash = Get-ChannelForgeGenerationOutputProperty $output.Object @('AcceptedXMLTVHash')
    if ($status -eq 'Generated') {
        $xml = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'merged.xml') -Domain 'active-xmltv/v2'
        $effectiveXmlHash = if ($null -ne $outputXmlHash) { $outputXmlHash } else { $acceptedXmlHash }
        if ([string]$xml.ContentHash -cne [string]$effectiveXmlHash) { throw 'FAIL_CLOSED: current XMLTV hash mismatch.' }
        if ($null -ne $outputXmlHash -and $null -ne $acceptedXmlHash -and [string]$outputXmlHash -cne [string]$acceptedXmlHash) { throw 'FAIL_CLOSED: current XMLTV hashes disagree.' }
    }
    elseif ($status -eq 'NotGenerated') {
        if ($null -ne $outputXmlHash -or $null -ne $acceptedXmlHash -or [System.IO.File]::Exists((Join-Path $generation 'merged.xml'))) { throw 'FAIL_CLOSED: NotGenerated generation has XMLTV content.' }
    }
    else { throw 'FAIL_CLOSED: unknown current XMLTV status.' }
    $allowed = @('generation.manifest.json','accepted-state.json','accepted-output.manifest.json','decision-manifest.json','merged.m3u')
    if ($status -eq 'Generated') { $allowed += 'merged.xml' }
    foreach ($child in [System.IO.Directory]::GetFileSystemEntries($generation)) {
        if ([System.IO.Path]::GetFileName($child) -notin $allowed) { throw 'FAIL_CLOSED: generation contains an unexpected child.' }
    }
    [pscustomobject][ordered]@{ Pointer = $pointer; GenerationPath = $generation; Manifest = $manifest; State = $state; Output = $output; Decision = $decision; M3U = $m3u; XMLTV = $xml }
}

function Publish-ChannelForgeGenerationCore {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$GenerationManifest,
        [Parameter(Mandatory)]$AcceptedState,
        [Parameter(Mandatory)]$AcceptedOutputManifest,
        [Parameter(Mandatory)]$DecisionManifest,
        [Parameter(Mandatory)][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [AllowNull()][string]$FaultHook
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $root
    Assert-ChannelForgeGenerationSafePath -RepositoryRoot $root -Path $root
    $generationId = Assert-ChannelForgeGenerationInputs -GenerationManifest $GenerationManifest -AcceptedState $AcceptedState -AcceptedOutputManifest $AcceptedOutputManifest -DecisionManifest $DecisionManifest -M3UBytes $M3UBytes -XMLTVBytes $XMLTVBytes
    Ensure-ChannelForgeGenerationDirectory -RepositoryRoot $root -Path $paths.State | Out-Null
    Ensure-ChannelForgeGenerationDirectory -RepositoryRoot $root -Path $paths.Generations | Out-Null
    Ensure-ChannelForgeGenerationDirectory -RepositoryRoot $root -Path $paths.Staging | Out-Null
    $store = Get-ChannelForgeGenerationStoreType
    $lease = $null
    $transactionId = ([guid]::NewGuid().ToString('N'))
    $transactionRoot = Join-Path $paths.Staging $transactionId
    $stageGeneration = Join-Path $transactionRoot "generation/$generationId"
    $finalGeneration = Join-Path $paths.Generations $generationId
    try {
        $lease = [ChannelForge.GenerationStore]::AcquireLock($paths.Lock)
        $lockMetadata = [ordered]@{ TransactionId = $transactionId; ProcessId = $PID } | ConvertTo-Json -Compress
        $lease.WriteMetadata(([System.Text.UTF8Encoding]::new($false).GetBytes($lockMetadata)))
        $current = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $root -Paths $paths
        if ($null -eq $current -and [System.IO.File]::Exists($paths.Previous)) { throw 'FAIL_CLOSED: previous pointer exists without current pointer.' }
        $priorStateHash = [string]$AcceptedState.PreviousStateHash
        if ($null -ne $current -and [string]::IsNullOrEmpty($priorStateHash)) { throw 'FAIL_CLOSED: later generation omitted previous state hash.' }
        if ($null -ne $current -and $priorStateHash -cne [string]$current.State.Object.AcceptedStateHash) { throw 'FAIL_CLOSED: accepted parent state does not match current state.' }
        if ($null -eq $current -and -not [string]::IsNullOrEmpty($priorStateHash)) { throw 'FAIL_CLOSED: first generation has prior state lineage.' }
        if ([System.IO.Directory]::Exists($finalGeneration)) { throw 'FAIL_CLOSED: generation ID collision.' }
        Ensure-ChannelForgeGenerationDirectory -RepositoryRoot $root -Path $stageGeneration | Out-Null
        $files = @(
            @('generation.manifest.json', (ConvertTo-ChannelForgeGenerationBytes $GenerationManifest), 'generation-manifest/v2', 'GenerationManifest', 'A01','A02','A03'),
            @('accepted-state.json', (ConvertTo-ChannelForgeGenerationBytes $AcceptedState), 'accepted-state/v2', 'AcceptedState', 'A04','A05','A06'),
            @('accepted-output.manifest.json', (ConvertTo-ChannelForgeGenerationBytes $AcceptedOutputManifest), 'previous-output-manifest/v2', 'AcceptedOutputManifest', 'A07','A08','A09'),
            @('decision-manifest.json', (ConvertTo-ChannelForgeGenerationBytes $DecisionManifest), 'decision-manifest/v2', 'DecisionManifest', 'A10','A11','A12'),
            @('merged.m3u', $M3UBytes, 'active-m3u/v2', 'M3U', 'A13','A14','A15')
        )
        $outputStatus = [string](Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('AcceptedXMLTVStatus','ActiveXMLTVStatus'))
        if ($outputStatus -eq 'Generated') { $files += ,@('merged.xml', $XMLTVBytes, 'active-xmltv/v2', 'XMLTV', 'A16','A17','A18') }
        $stagedSnapshots = @{}
        foreach ($file in $files) {
            $stagedSnapshots[$file[0]] = Write-ChannelForgeGenerationFile -RepositoryRoot $root -Path (Join-Path $stageGeneration $file[0]) -Bytes $file[1] -FaultHook $FaultHook -WriteHook "StageWrite.$($file[3])" -FlushHook "StageFlush.$($file[3])" -ReopenHook "StageReopenHash.$($file[3])" -Domain $file[2]
        }
        $pointer = New-ChannelForgeGenerationPointer -GenerationManifest $GenerationManifest -AcceptedState $AcceptedState -AcceptedOutputManifest $AcceptedOutputManifest
        $stagePointer = Join-Path $transactionRoot 'accepted-lineup.json'
        $stagedPointer = Write-ChannelForgeGenerationFile -RepositoryRoot $root -Path $stagePointer -Bytes (ConvertTo-ChannelForgeGenerationBytes $pointer) -FaultHook $FaultHook -WriteHook 'StageWrite.Pointer' -FlushHook 'StageFlush.Pointer' -ReopenHook 'StageReopenHash.Pointer' -Domain 'pointer/v2'
        $oldPointerHash = if ($null -eq $current) { $null } else { [string]$current.Pointer.Object.PointerHash }
        $oldGenerationId = if ($null -eq $current) { $null } else { [string]$current.Pointer.Object.GenerationId }
        $oldJournalHash = if ([System.IO.File]::Exists($paths.Journal)) { [string](Read-ChannelForgeGenerationDocument -RepositoryRoot $root -Path $paths.Journal -Domain 'journal/v2').Object.JournalHash } else { $null }
        $records = [System.Collections.Generic.List[object]]::new()
        $ordinal = 0
        foreach ($file in $files) {
            [void]$records.Add((New-ChannelForgeGenerationMutationRecord $ordinal Create "state/generations/$generationId/$($file[0])" $null $stagedSnapshots[$file[0]]))
            $ordinal++
        }
        $oldPointerRecord = if ($null -eq $current) { $null } else { $current.Pointer }
        [void]$records.Add((New-ChannelForgeGenerationMutationRecord $ordinal Replace 'state/accepted-lineup.json' $oldPointerRecord $stagedPointer))
        $journalStagePath = Join-Path $transactionRoot 'accepted-lineup.journal.json'
        $journal = New-ChannelForgeGenerationJournal -Stage 1 -TransactionId $transactionId -ExpectedOldPointerHash $oldPointerHash -ExpectedNewPointerHash $pointer.PointerHash -ExpectedOldGenerationId $oldGenerationId -ExpectedNewGenerationId $generationId -MutationRecords @($records) -OldJournalHash $oldJournalHash
        Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $journalStagePath -Journal $journal -FaultHook $FaultHook -StageName Prepared | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'GenerationDirectoryMove.Before'
        [ChannelForge.GenerationStore]::MoveDirectory($stageGeneration, $finalGeneration)
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'GenerationDirectoryMove.After'
        $journal = New-ChannelForgeGenerationJournal -Stage 2 -TransactionId $transactionId -ExpectedOldPointerHash $oldPointerHash -ExpectedNewPointerHash $pointer.PointerHash -ExpectedOldGenerationId $oldGenerationId -ExpectedNewGenerationId $generationId -MutationRecords @($records) -OldJournalHash ([string]$journal.JournalHash)
        Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $journalStagePath -Journal $journal -FaultHook $FaultHook -StageName GenerationPublished | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'PointerReplace.Before'
        if ($null -ne $current) {
            if ([System.IO.File]::Exists($paths.Previous)) { throw 'FAIL_CLOSED: pointer backup already exists.' }
            [ChannelForge.GenerationStore]::ReplaceFile($stagePointer, $paths.Current, $paths.Previous)
        }
        else {
            if ([System.IO.File]::Exists($paths.Current) -or [System.IO.File]::Exists($paths.Previous)) { throw 'FAIL_CLOSED: first-generation pointer precondition changed.' }
            [ChannelForge.GenerationStore]::MoveFile($stagePointer, $paths.Current)
        }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'PointerReplace.After'
        $journal = New-ChannelForgeGenerationJournal -Stage 3 -TransactionId $transactionId -ExpectedOldPointerHash $oldPointerHash -ExpectedNewPointerHash $pointer.PointerHash -ExpectedOldGenerationId $oldGenerationId -ExpectedNewGenerationId $generationId -MutationRecords @($records) -OldJournalHash ([string]$journal.JournalHash)
        Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $journalStagePath -Journal $journal -FaultHook $FaultHook -StageName PointerSwapped | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'VerifyCurrentPointer.Before'
        $verified = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $root -Paths $paths
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'VerifyCurrentPointer.After'
        foreach ($verify in @('GenerationManifest','AcceptedState','OutputManifest','M3U','XMLTV')) {
            if ($verify -eq 'XMLTV' -and $null -eq $verified.XMLTV) { continue }
            Invoke-ChannelForgeGenerationFaultHook $FaultHook "Verify.$verify.Before"
            $propertyName = switch ($verify) { 'GenerationManifest' {'Manifest'} 'AcceptedState' {'State'} 'OutputManifest' {'Output'} 'M3U' {'M3U'} default {'XMLTV'} }
            if ($null -eq $verified.$propertyName) { throw "FAIL_CLOSED: verification object missing $verify." }
            Invoke-ChannelForgeGenerationFaultHook $FaultHook "Verify.$verify.After"
        }
        $journal = New-ChannelForgeGenerationJournal -Stage 4 -TransactionId $transactionId -ExpectedOldPointerHash $oldPointerHash -ExpectedNewPointerHash $pointer.PointerHash -ExpectedOldGenerationId $oldGenerationId -ExpectedNewGenerationId $generationId -MutationRecords @($records) -OldJournalHash ([string]$journal.JournalHash)
        Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $journalStagePath -Journal $journal -FaultHook $FaultHook -StageName Committed | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.GenerationStage.Before'
        if ([System.IO.Directory]::Exists($transactionRoot)) { [ChannelForge.GenerationStore]::DeleteDirectory($transactionRoot) }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.GenerationStage.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.PointerJournalBackup.Before'
        if ([System.IO.File]::Exists($paths.JournalPrevious)) { [ChannelForge.GenerationStore]::DeleteFile($paths.JournalPrevious) }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.PointerJournalBackup.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.TransactionDirectory.Before'
        if ([System.IO.Directory]::Exists($transactionRoot)) { [ChannelForge.GenerationStore]::DeleteDirectory($transactionRoot) }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.TransactionDirectory.After'
        if ($null -ne $lease) { $lease.Dispose(); $lease = $null }
        if ([System.IO.File]::Exists($paths.Lock)) { [ChannelForge.GenerationStore]::DeleteFile($paths.Lock) }
        return [pscustomobject][ordered]@{ Outcome = 'NEW'; TransactionId = $transactionId; GenerationId = $generationId; PointerHash = [string]$pointer.PointerHash; GenerationManifestHash = [string]$GenerationManifest.GenerationManifestHash }
    }
    finally {
        if ($null -ne $lease) { $lease.Dispose() }
    }
}

function Get-ChannelForgeNoJournalRecoveryOutcome {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    if ([System.IO.File]::Exists($Paths.JournalPrevious)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: orphan journal backup.' }
    if ([System.IO.Directory]::Exists($Paths.Staging) -and @([System.IO.Directory]::GetDirectories($Paths.Staging)).Count -gt 0) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: transaction staging remnant.' }
    $generationDirectories = if ([System.IO.Directory]::Exists($Paths.Generations)) { @([System.IO.Directory]::GetDirectories($Paths.Generations)) } else { @() }
    if (-not [System.IO.File]::Exists($Paths.Current)) {
        if ($generationDirectories.Count -gt 0) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: final generation exists without current pointer.' }
        if ([System.IO.File]::Exists($Paths.Previous)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: previous pointer exists without current pointer.' }
        return [pscustomobject][ordered]@{ Outcome = 'INITIAL_BASELINE_REQUIRED'; Mutation = 'None' }
    }
    $current = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $Paths
    if ([System.IO.File]::Exists($Paths.Previous)) {
        $previous = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $Paths.Previous -Domain 'pointer/v2'
        if (-not (Test-ChannelForgeGenerationProjectionHash $previous.Object 'pointer/v2' 'PointerHash')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: invalid previous pointer.' }
        if ([string]$previous.Object.GenerationId -ceq [string]$current.Pointer.Object.GenerationId) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: previous pointer names current generation.' }
        $previousGeneration = Join-Path $Paths.Generations ([string]$previous.Object.GenerationId)
        if (-not [System.IO.Directory]::Exists($previousGeneration)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: previous generation is missing.' }
        $previousManifest = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $previousGeneration 'generation.manifest.json') -Domain 'generation-manifest/v2'
        if ([string]$previousManifest.Object.GenerationManifestHash -cne [string]$previous.Object.GenerationManifestHash -or -not (Test-ChannelForgeGenerationProjectionHash $previousManifest.Object 'generation-manifest/v2' 'GenerationManifestHash' @('GenerationId'))) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: previous generation linkage is invalid.' }
    }
    $referencedGenerationIds = @([string]$current.Pointer.Object.GenerationId)
    if ([System.IO.File]::Exists($Paths.Previous)) { $referencedGenerationIds += [string]$previous.Object.GenerationId }
    $generationDirectories = if ([System.IO.Directory]::Exists($Paths.Generations)) { @([System.IO.Directory]::GetDirectories($Paths.Generations)) } else { @() }
    foreach ($directory in $generationDirectories) {
        $directoryId = [System.IO.Path]::GetFileName($directory)
        if ($directoryId -in $referencedGenerationIds) { continue }
        try {
            Assert-ChannelForgeGenerationId $directoryId
            $orphanManifest = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $directory 'generation.manifest.json') -Domain 'generation-manifest/v2'
            $orphanState = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $directory 'accepted-state.json') -Domain 'accepted-state/v2'
            $orphanOutput = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $directory 'accepted-output.manifest.json') -Domain 'previous-output-manifest/v2'
            $orphanDecision = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $directory 'decision-manifest.json') -Domain 'decision-manifest/v2'
            if (-not (Test-ChannelForgeGenerationProjectionHash $orphanManifest.Object 'generation-manifest/v2' 'GenerationManifestHash' @('GenerationId')) -or -not (Test-ChannelForgeGenerationProjectionHash $orphanState.Object 'accepted-state/v2' 'AcceptedStateHash' @('GenerationId','AcceptedAtUtc')) -or -not (Test-ChannelForgeGenerationProjectionHash $orphanOutput.Object 'previous-output-manifest/v2' 'OutputManifestHash' @('GenerationId','AcceptedStateHash')) -or -not (Test-ChannelForgeGenerationProjectionHash $orphanDecision.Object 'decision-manifest/v2' 'DecisionManifestHash')) { throw 'semantic hash mismatch' }
            $orphanM3U = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path (Join-Path $directory 'merged.m3u') -Domain 'active-m3u/v2'
            if ([string]$orphanM3U.ContentHash -cne [string](Get-ChannelForgeGenerationOutputProperty $orphanOutput.Object @('OutputM3UHash','ActiveM3UHash'))) { throw 'M3U hash mismatch' }
            $orphanStatus = [string](Get-ChannelForgeGenerationOutputProperty $orphanOutput.Object @('AcceptedXMLTVStatus','ActiveXMLTVStatus'))
            $orphanAllowed = @('generation.manifest.json','accepted-state.json','accepted-output.manifest.json','decision-manifest.json','merged.m3u')
            if ($orphanStatus -eq 'Generated') { $orphanAllowed += 'merged.xml'; $null = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path (Join-Path $directory 'merged.xml') -Domain 'active-xmltv/v2' }
            elseif ($orphanStatus -ne 'NotGenerated' -or [System.IO.File]::Exists((Join-Path $directory 'merged.xml'))) { throw 'invalid XMLTV state' }
            foreach ($child in [System.IO.Directory]::GetFileSystemEntries($directory)) { if ([System.IO.Path]::GetFileName($child) -notin $orphanAllowed) { throw 'extra generation child' } }
        }
        catch { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: malformed unreferenced generation.' }
    }
    [pscustomobject][ordered]@{ Outcome = 'ACCEPTED_STATE_VALID'; Mutation = 'None'; GenerationId = [string]$current.Pointer.Object.GenerationId; PointerHash = [string]$current.Pointer.Object.PointerHash }
}

function Recover-ChannelForgeAcceptedStateCore {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $null = Initialize-ChannelForgeGenerationStore
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ($root.StartsWith('\\')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: UNC/SMB repository roots are not accepted.' }
    if (-not [System.IO.Directory]::Exists($root)) { return [pscustomobject][ordered]@{ Outcome = 'INITIAL_BASELINE_REQUIRED'; Mutation = 'None' } }
    if ([ChannelForge.GenerationStore]::IsReparsePoint($root)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: repository root is a reparse point.' }
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $root
    if (-not [System.IO.Directory]::Exists($paths.State)) { return [pscustomobject][ordered]@{ Outcome = 'INITIAL_BASELINE_REQUIRED'; Mutation = 'None' } }
    Assert-ChannelForgeGenerationSafePath -RepositoryRoot $root -Path $paths.State | Out-Null
    $lease = $null
    try {
        $lease = [ChannelForge.GenerationStore]::AcquireLock($paths.Lock)
        if (-not [System.IO.File]::Exists($paths.Journal)) { return Get-ChannelForgeNoJournalRecoveryOutcome -RepositoryRoot $root -Paths $paths }
        $journal = Read-ChannelForgeGenerationDocument -RepositoryRoot $root -Path $paths.Journal -Domain 'journal/v2'
        $object = $journal.Object
        if ([int]$object.Version -ne 2 -or [int]$object.JournalStage -lt 1 -or [int]$object.JournalStage -gt 4 -or -not (Test-ChannelForgeGenerationProjectionHash $object 'journal/v2' 'JournalHash')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: invalid authoritative journal.' }
        $current = $null
        if ([System.IO.File]::Exists($paths.Current)) { $current = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $root -Paths $paths }
        $newGeneration = Join-Path $paths.Generations ([string]$object.ExpectedNewGenerationId)
        $transactionRoot = Join-Path $paths.Staging ([string]$object.TransactionId)
        $stagePointer = Join-Path $transactionRoot 'accepted-lineup.json'
        if ([int]$object.JournalStage -eq 1) {
            if ([System.IO.Directory]::Exists($newGeneration)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: Prepared journal has unexpected final generation.' }
            return [pscustomobject][ordered]@{ Outcome = 'OLD'; Mutation = 'None'; JournalStage = 'Prepared' }
        }
        if ([int]$object.JournalStage -eq 2 -and $null -ne $current -and [string]$current.Pointer.Object.GenerationId -eq [string]$object.ExpectedNewGenerationId) {
            $next = New-ChannelForgeGenerationJournal -Stage 3 -TransactionId ([string]$object.TransactionId) -ExpectedOldPointerHash $object.ExpectedOldPointerHash -ExpectedNewPointerHash $object.ExpectedNewPointerHash -ExpectedOldGenerationId $object.ExpectedOldGenerationId -ExpectedNewGenerationId $object.ExpectedNewGenerationId -MutationRecords @($object.MutationRecords) -OldJournalHash ([string]$object.JournalHash)
            $nextStage = Join-Path $transactionRoot 'accepted-lineup.journal.json'
            Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $nextStage -Journal $next -FaultHook $null -StageName PointerSwapped | Out-Null
            return [pscustomobject][ordered]@{ Outcome = 'NEW'; Mutation = 'PublishPointerSwapped'; JournalStage = 'PointerSwapped' }
        }
        if ([int]$object.JournalStage -eq 2) {
            if ($null -eq $current -or [string]$current.Pointer.Object.PointerHash -cne [string]$object.ExpectedOldPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: old pointer precondition changed.' }
            if (-not [System.IO.File]::Exists($stagePointer)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: staged new pointer is missing.' }
            if ([System.IO.File]::Exists($paths.Previous)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: pointer backup already exists.' }
            [ChannelForge.GenerationStore]::ReplaceFile($stagePointer, $paths.Current, $paths.Previous)
            $next = New-ChannelForgeGenerationJournal -Stage 3 -TransactionId ([string]$object.TransactionId) -ExpectedOldPointerHash $object.ExpectedOldPointerHash -ExpectedNewPointerHash $object.ExpectedNewPointerHash -ExpectedOldGenerationId $object.ExpectedOldGenerationId -ExpectedNewGenerationId $object.ExpectedNewGenerationId -MutationRecords @($object.MutationRecords) -OldJournalHash ([string]$object.JournalHash)
            $nextStage = Join-Path $transactionRoot 'accepted-lineup.journal.json'
            Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $nextStage -Journal $next -FaultHook $null -StageName PointerSwapped | Out-Null
            return [pscustomobject][ordered]@{ Outcome = 'NEW'; Mutation = 'RetryPointerReplace'; JournalStage = 'PointerSwapped' }
        }
        if ($null -eq $current -or [string]$current.Pointer.Object.GenerationId -cne [string]$object.ExpectedNewGenerationId) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal and current pointer disagree.' }
        if ([int]$object.JournalStage -eq 3) {
            $next = New-ChannelForgeGenerationJournal -Stage 4 -TransactionId ([string]$object.TransactionId) -ExpectedOldPointerHash $object.ExpectedOldPointerHash -ExpectedNewPointerHash $object.ExpectedNewPointerHash -ExpectedOldGenerationId $object.ExpectedOldGenerationId -ExpectedNewGenerationId $object.ExpectedNewGenerationId -MutationRecords @($object.MutationRecords) -OldJournalHash ([string]$object.JournalHash)
            $nextStage = Join-Path $transactionRoot 'accepted-lineup.journal.json'
            Publish-ChannelForgeGenerationJournal -RepositoryRoot $root -AuthoritativePath $paths.Journal -StagedPath $nextStage -Journal $next -FaultHook $null -StageName Committed | Out-Null
            return [pscustomobject][ordered]@{ Outcome = 'NEW'; Mutation = 'PublishCommitted'; JournalStage = 'Committed' }
        }
        if ([System.IO.Directory]::Exists($transactionRoot)) { [ChannelForge.GenerationStore]::DeleteDirectory($transactionRoot) }
        [pscustomobject][ordered]@{ Outcome = 'NEW'; Mutation = 'CleanupOnly'; JournalStage = 'Committed'; GenerationId = [string]$current.Pointer.Object.GenerationId }
    }
    catch {
        if ($_.Exception.Message -like 'FAIL_CLOSED_RECOVERY_REQUIRED*') { throw }
        throw "FAIL_CLOSED_RECOVERY_REQUIRED: $($_.Exception.Message)"
    }
    finally { if ($null -ne $lease) { $lease.Dispose() } }
}
