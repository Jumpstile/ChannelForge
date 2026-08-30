$script:ChannelForgeGenerationAcceptanceVersion = 'blocker-2-contract/v8-acceptance'
$script:ChannelForgeGenerationStages = @('Prepared','GenerationPublished','PointerSwapped','Committed')

function Get-ChannelForgeGenerationStoreType { Initialize-ChannelForgeGenerationStore }

function Invoke-ChannelForgeGenerationFaultHook {
    param([AllowNull()][string]$FaultHook,[Parameter(Mandatory)][string]$Name)
    if ($null -ne $FaultHook -and $FaultHook -ceq $Name) {
        $holdAt = [Environment]::GetEnvironmentVariable('CHANNELFORGE_TEST_HOLD_AT')
        if ([Environment]::GetEnvironmentVariable('CHANNELFORGE_TEST_MODE') -eq '1' -and $holdAt -ceq $Name) {
            $marker = [Environment]::GetEnvironmentVariable('CHANNELFORGE_TEST_HOLD_MARKER')
            if (-not [string]::IsNullOrWhiteSpace($marker)) { [IO.File]::WriteAllText($marker,'READY') }
            while ($true) { Start-Sleep -Milliseconds 100 }
        }
        throw "FAULT_HOOK: $Name"
    }
}

function ConvertTo-ChannelForgeGenerationCanonicalObject {
    param([AllowNull()]$InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [ValueType]) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($entry in $InputObject.GetEnumerator()) { $result[$entry.Key] = ConvertTo-ChannelForgeGenerationCanonicalObject $entry.Value }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable]) { return ,@($InputObject | ForEach-Object { ConvertTo-ChannelForgeGenerationCanonicalObject $_ }) }
    $result = [ordered]@{}
    foreach ($property in @($InputObject.PSObject.Properties)) { $result[$property.Name] = ConvertTo-ChannelForgeGenerationCanonicalObject $property.Value }
    return $result
}

function ConvertTo-ChannelForgeGenerationBytes {
    param([Parameter(Mandatory)][object]$InputObject)
    if ($InputObject -is [byte[]]) { return [byte[]]$InputObject }
    $json = ConvertTo-ChannelForgeCanonicalJson -InputObject (ConvertTo-ChannelForgeGenerationCanonicalObject $InputObject)
    return [Text.UTF8Encoding]::new($false).GetBytes($json)
}

function Test-ChannelForgeGenerationBytesEqual {
    param([Parameter(Mandatory)][byte[]]$Left,[Parameter(Mandatory)][byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) { if ($Left[$i] -ne $Right[$i]) { return $false } }
    return $true
}

function Assert-ChannelForgeGenerationSafePath {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Path,[switch]$AllowMissingLeaf)
    $null = Initialize-ChannelForgeGenerationStore
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $full = [IO.Path]::GetFullPath($Path)
    if ($root.StartsWith('\\')) { throw 'FAIL_CLOSED: UNC/SMB repository roots are not accepted.' }
    if ($full -cne $root) {
        $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'FAIL_CLOSED: path escapes the repository root.' }
    }
    $relative = [IO.Path]::GetRelativePath($root,$full)
    if ($relative -ne '.' -and @($relative -split '[\\/]' | Where-Object { $_ -like '*:*' }).Count -gt 0) { throw 'FAIL_CLOSED: alternate data stream path.' }
    if ([ChannelForge.GenerationStore]::Exists($root)) {
        $rootIdentity = [ChannelForge.GenerationStore]::ReadPathIdentity($root)
        if ($rootIdentity.IsReparsePoint) { throw 'FAIL_CLOSED: repository root is a reparse point.' }
    }
    $cursor = $root
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrEmpty($part) -or $part -eq '.') { continue }
        $cursor = Join-Path $cursor $part
        if ([ChannelForge.GenerationStore]::Exists($cursor)) {
            $identity = [ChannelForge.GenerationStore]::ReadPathIdentity($cursor)
            if ($identity.IsReparsePoint) { throw "FAIL_CLOSED: reparse point in authority path: $cursor" }
            if ([IO.File]::Exists($cursor) -and $identity.NumberOfLinks -ne 1) { throw "FAIL_CLOSED: hard-linked authority file: $cursor" }
        } elseif (-not $AllowMissingLeaf) { throw "FAIL_CLOSED: required path is missing: $cursor" }
    }
    return $full
}

function Ensure-ChannelForgeGenerationDirectory {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Path)
    $root = [IO.Path]::GetFullPath($RepositoryRoot); $full = [IO.Path]::GetFullPath($Path)
    Assert-ChannelForgeGenerationSafePath -RepositoryRoot $root -Path $root -AllowMissingLeaf | Out-Null
    if (-not [IO.Directory]::Exists($root)) { [IO.Directory]::CreateDirectory($root) | Out-Null }
    $cursor = $root
    foreach ($part in ([IO.Path]::GetRelativePath($root,$full) -split '[\\/]')) {
        if ([string]::IsNullOrEmpty($part) -or $part -eq '.') { continue }
        $cursor = Join-Path $cursor $part
        Assert-ChannelForgeGenerationSafePath -RepositoryRoot $root -Path $cursor -AllowMissingLeaf | Out-Null
        if (-not [IO.Directory]::Exists($cursor)) {
            if ([ChannelForge.GenerationStore]::Exists($cursor)) { throw "FAIL_CLOSED: authority path is not a directory: $cursor" }
            [IO.Directory]::CreateDirectory($cursor) | Out-Null
        }
        Assert-ChannelForgeGenerationSafePath -RepositoryRoot $root -Path $cursor | Out-Null
    }
    return $full
}

function Get-ChannelForgeGenerationIdentityObject {
    param([Parameter(Mandatory)]$Identity)
    [ordered]@{ VolumeSerial=[uint64]$Identity.VolumeSerial; FileId=[string]$Identity.FileId; ByteLength=[uint64]$Identity.ByteLength; LastWriteUtcTicks=[int64]$Identity.LastWriteUtcTicks }
}
function Get-ChannelForgeGenerationIdentityKey {
    param([Parameter(Mandatory)]$Identity)
    '{0}|{1}|{2}|{3}' -f [uint64]$Identity.VolumeSerial,[string]$Identity.FileId,[uint64]$Identity.ByteLength,[int64]$Identity.LastWriteUtcTicks
}
function Assert-ChannelForgeGenerationIdentity {
    param([Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Actual,[Parameter(Mandatory)][string]$Name)
    if ((Get-ChannelForgeGenerationIdentityKey $Expected) -cne (Get-ChannelForgeGenerationIdentityKey $Actual)) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: $Name FileIdentity changed." }
    if ($Actual.PSObject.Properties['NumberOfLinks'] -and [uint32]$Actual.NumberOfLinks -ne 1) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: $Name has multiple hard links." }
    if ($Actual.PSObject.Properties['IsReparsePoint'] -and [bool]$Actual.IsReparsePoint) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: $Name is a reparse point." }
}

function Get-ChannelForgeGenerationVolumePath {
    param([Parameter(Mandatory)][string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while (-not [ChannelForge.GenerationStore]::Exists($cursor)) {
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { throw 'FAIL_CLOSED: volume identity cannot be resolved.' }
        $cursor = $parent
    }
    return $cursor
}
function Assert-ChannelForgeGenerationSameVolume {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$Paths)
    $rootId = [ChannelForge.GenerationStore]::ReadPathIdentity((Get-ChannelForgeGenerationVolumePath $RepositoryRoot))
    foreach ($path in $Paths) {
        $id = [ChannelForge.GenerationStore]::ReadPathIdentity((Get-ChannelForgeGenerationVolumePath $path))
        if ([uint32]$id.VolumeSerial -ne [uint32]$rootId.VolumeSerial) { throw "FAIL_CLOSED: atomic authority path is on another volume: $path" }
    }
}
function Assert-ChannelForgeGenerationMutationPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Path,[AllowNull()]$ExpectedIdentity,[switch]$AllowMissing)
    $full = Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $Path -AllowMissingLeaf
    $parent = Split-Path -Parent $full
    Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $parent | Out-Null
    if (-not [ChannelForge.GenerationStore]::Exists($full)) { if (-not $AllowMissing) { throw "FAIL_CLOSED: mutation target is missing: $full" }; return $full }
    $actual = [ChannelForge.GenerationStore]::ReadPathIdentity($full)
    if ($actual.IsReparsePoint -or $actual.NumberOfLinks -ne 1) { throw "FAIL_CLOSED: unsafe mutation target: $full" }
    if ($null -ne $ExpectedIdentity) { Assert-ChannelForgeGenerationIdentity -Expected $ExpectedIdentity -Actual $actual -Name $full }
    return $full
}

function Read-ChannelForgeGenerationFile {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Domain)
    $full = Assert-ChannelForgeGenerationSafePath -RepositoryRoot $RepositoryRoot -Path $Path
    $stream = $null
    try {
        $stream = [ChannelForge.GenerationStore]::OpenRead($full)
        $memory = [IO.MemoryStream]::new(); try { $stream.CopyTo($memory); $bytes=$memory.ToArray() } finally { $memory.Dispose() }
        $raw = [ChannelForge.GenerationStore]::ReadIdentity($stream)
        if ($raw.IsReparsePoint -or $raw.NumberOfLinks -ne 1) { throw 'FAIL_CLOSED: authority file identity is unsafe.' }
        $identity = Get-ChannelForgeGenerationIdentityObject $raw
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    [pscustomobject][ordered]@{ Path=$full; Bytes=[byte[]]$bytes; ByteLength=[uint64]$bytes.Length; ContentHash=Get-ChannelForgeDomainHash -Domain $Domain -Bytes $bytes; FileIdentity=$identity }
}
function Read-ChannelForgeGenerationDocument {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Domain)
    $file = Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path $Path -Domain $Domain
    try {
        $object = ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString($file.Bytes)) -AsHashtable -Depth 100 -DateKind String -ErrorAction Stop
        if (-not (Test-ChannelForgeGenerationBytesEqual $file.Bytes (ConvertTo-ChannelForgeGenerationBytes $object))) { throw 'non-canonical bytes' }
    } catch { throw "FAIL_CLOSED: invalid canonical document '$($file.Path)': $($_.Exception.Message)" }
    $file | Add-Member NoteProperty Object $object -PassThru
}
function Write-ChannelForgeGenerationFile {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes,[AllowNull()][string]$FaultHook,[Parameter(Mandatory)][string]$WriteHook,[Parameter(Mandatory)][string]$FlushHook,[Parameter(Mandatory)][string]$ReopenHook,[Parameter(Mandatory)][string]$Domain)
    $full = Assert-ChannelForgeGenerationMutationPath -RepositoryRoot $RepositoryRoot -Path $Path -AllowMissing
    $parent = Split-Path -Parent $full
    if (-not [IO.Directory]::Exists($parent)) { throw 'FAIL_CLOSED: staging parent is missing.' }
    Assert-ChannelForgeGenerationSameVolume -RepositoryRoot $RepositoryRoot -Paths @($parent,$full)
    $stream=$null; $opened=$null
    try {
        $stream=[ChannelForge.GenerationStore]::CreateExclusive($full)
        if ($FaultHook -ceq $WriteHook) { $partial=[Math]::Max(1,[Math]::Min($Bytes.Length,[int][Math]::Ceiling($Bytes.Length/2.0))); $stream.Write($Bytes,0,$partial); throw "FAULT_HOOK: $WriteHook" }
        $stream.Write($Bytes,0,$Bytes.Length)
        if ($FaultHook -ceq $FlushHook) { throw "FAULT_HOOK: $FlushHook" }
        [ChannelForge.GenerationStore]::Flush($stream)
        $opened=Get-ChannelForgeGenerationIdentityObject ([ChannelForge.GenerationStore]::ReadIdentity($stream))
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    if ($FaultHook -ceq $ReopenHook) { throw "FAULT_HOOK: $ReopenHook" }
    $actual=Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path $full -Domain $Domain
    Assert-ChannelForgeGenerationIdentity -Expected $opened -Actual $actual.FileIdentity -Name $full
    if (-not (Test-ChannelForgeGenerationBytesEqual $actual.Bytes $Bytes)) { throw 'FAIL_CLOSED: staged bytes changed during reopen verification.' }
    return $actual
}

function Get-ChannelForgeGenerationPaths {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $state=Join-Path $RepositoryRoot 'state'
    [ordered]@{ State=$state; Lock=Join-Path $state 'lineup-operation.lock'; Current=Join-Path $state 'accepted-lineup.json'; Previous=Join-Path $state 'accepted-lineup.json.previous'; Journal=Join-Path $state 'accepted-lineup.journal.json'; JournalPrevious=Join-Path $state 'accepted-lineup.journal.json.previous'; Generations=Join-Path $state 'generations'; Staging=Join-Path $state '.staging' }
}
function Assert-ChannelForgeGenerationId { param([Parameter(Mandatory)][string]$GenerationId); if ($GenerationId -cnotmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: GenerationId must be 64 lowercase hexadecimal characters.' } }
function Assert-ChannelForgeGenerationHash { param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name); if ($null -eq $Value -or ([string]$Value) -cnotmatch '^[0-9a-f]{64}$') { throw "FAIL_CLOSED: $Name must be lowercase 64-hex." } }
function Get-ChannelForgeGenerationOutputProperty { param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string[]]$Names); foreach ($name in $Names) { if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($name)) { return $Object[$name] } } elseif ($Object.PSObject.Properties[$name]) { return $Object.$name } }; return $null }
function Get-ChannelForgeGenerationPropertyNames { param([Parameter(Mandatory)]$Object); if ($Object -is [Collections.IDictionary]) { return @($Object.Keys | ForEach-Object { [string]$_ }) }; return @($Object.PSObject.Properties | ForEach-Object { [string]$_.Name }) }
function Get-ChannelForgeGenerationPropertyValue { param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string]$Name); if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $null }; if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }; return $null }
function Assert-ChannelForgeGenerationPropertySequence { param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Name); $actual=@(Get-ChannelForgeGenerationPropertyNames $Object); if ($actual.Count -ne $Expected.Count -or (($actual -join "`0") -cne ($Expected -join "`0"))) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: $Name schema/property sequence is invalid." } }
function Test-ChannelForgeGenerationProjectionHash { param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string]$Domain,[Parameter(Mandatory)][string]$Property,[string[]]$Omit=@()); $ordered=ConvertTo-ChannelForgeGenerationCanonicalObject $Object; if ($null -eq $ordered[$Property]) { return $false }; $input=[ordered]@{}; foreach ($entry in $ordered.GetEnumerator()) { if ($entry.Key -ne $Property -and $entry.Key -notin $Omit) { $input[$entry.Key]=$entry.Value } }; return (Get-ChannelForgeDomainHash -Domain $Domain -InputObject $input) -ceq [string]$ordered[$Property] }

function Assert-ChannelForgeGenerationAcceptedGraph {
    param([Parameter(Mandatory)]$GenerationManifest,[Parameter(Mandatory)]$AcceptedState,[Parameter(Mandatory)]$AcceptedOutputManifest,[Parameter(Mandatory)]$DecisionManifest,[Parameter(Mandatory)][string]$GenerationId)
    Assert-ChannelForgeGenerationPropertySequence $GenerationManifest @('Version','GenerationId','BuildIdentity','CandidateManifestHash','DecisionManifestHash','AcceptedStateHash','AcceptedOutputManifestHash','ActiveM3UHash','ActiveXMLTVHash','PreviousOutputManifestHash','GenerationManifestHash') 'GenerationManifest'
    Assert-ChannelForgeGenerationPropertySequence $AcceptedState @('Version','GenerationId','BuildIdentity','CandidateManifestHash','DecisionManifestHash','AcceptedOutputManifestHash','PreviousStateHash','IncludedCandidateEntryIds','ExcludedCandidateEntryIds','AcceptedBindingIds','AcceptedXMLTVStatus','AcceptedAtUtc','AcceptedStateHash') 'AcceptedState'
    Assert-ChannelForgeGenerationPropertySequence $AcceptedOutputManifest @('Version','GenerationId','ActiveM3UHash','ActiveXMLTVStatus','ActiveXMLTVHash','AcceptedStateHash','OutputManifestHash') 'AcceptedOutputManifest'
    Assert-ChannelForgeGenerationPropertySequence $DecisionManifest @('Version','CandidateManifestHash','BuildIdentity','M3UDecisionHash','XMLTVDecisionStatus','XMLTVDecisionHash','DecisionIds','DecisionManifestHash') 'DecisionManifest'
    Assert-ChannelForgeGenerationId $GenerationId
    foreach ($pair in @(@($GenerationManifest,'GenerationManifest'),@($AcceptedState,'AcceptedState'),@($AcceptedOutputManifest,'AcceptedOutputManifest'),@($DecisionManifest,'DecisionManifest'))) { Assert-ChannelForgeAcceptanceVersion $pair[0] $pair[1] }
    foreach ($name in @('BuildIdentity','CandidateManifestHash','DecisionManifestHash','AcceptedStateHash','AcceptedOutputManifestHash','ActiveM3UHash')) { Assert-ChannelForgeGenerationHash (Get-ChannelForgeGenerationPropertyValue $GenerationManifest $name) "GenerationManifest.$name" }
    if ([string]$AcceptedState.PreviousStateHash -eq '') { if ($null -ne $GenerationManifest.PreviousOutputManifestHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: first generation has previous output linkage.' } } else { Assert-ChannelForgeGenerationHash $GenerationManifest.PreviousOutputManifestHash 'GenerationManifest.PreviousOutputManifestHash' }
    if ([string]$AcceptedState.AcceptedXMLTVStatus -eq 'Generated') { Assert-ChannelForgeGenerationHash $GenerationManifest.ActiveXMLTVHash 'GenerationManifest.ActiveXMLTVHash' } elseif ($null -ne $GenerationManifest.ActiveXMLTVHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: NotGenerated generation contains XMLTV hash.' }
    foreach ($pair in @(@($AcceptedState,'BuildIdentity'),@($AcceptedState,'CandidateManifestHash'),@($AcceptedState,'DecisionManifestHash'),@($AcceptedState,'AcceptedOutputManifestHash'),@($AcceptedState,'AcceptedStateHash'),@($AcceptedOutputManifest,'ActiveM3UHash'),@($AcceptedOutputManifest,'OutputManifestHash'),@($DecisionManifest,'CandidateManifestHash'),@($DecisionManifest,'BuildIdentity'),@($DecisionManifest,'M3UDecisionHash'),@($DecisionManifest,'DecisionManifestHash'))) { Assert-ChannelForgeGenerationHash (Get-ChannelForgeGenerationPropertyValue $pair[0] $pair[1]) $pair[1] }
    if ([string]$GenerationManifest.GenerationId -cne $GenerationId -or [string]$AcceptedState.GenerationId -cne $GenerationId -or [string]$AcceptedOutputManifest.GenerationId -cne $GenerationId) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: graph GenerationId mismatch.' }
    if ([string]$GenerationManifest.BuildIdentity -cne [string]$AcceptedState.BuildIdentity -or [string]$GenerationManifest.BuildIdentity -cne [string]$DecisionManifest.BuildIdentity -or [string]$GenerationManifest.CandidateManifestHash -cne [string]$AcceptedState.CandidateManifestHash -or [string]$GenerationManifest.CandidateManifestHash -cne [string]$DecisionManifest.CandidateManifestHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: candidate/build linkage mismatch.' }
    if ([string]$GenerationManifest.DecisionManifestHash -cne [string]$DecisionManifest.DecisionManifestHash -or [string]$GenerationManifest.DecisionManifestHash -cne [string]$AcceptedState.DecisionManifestHash -or [string]$GenerationManifest.AcceptedStateHash -cne [string]$AcceptedState.AcceptedStateHash -or [string]$GenerationManifest.AcceptedOutputManifestHash -cne [string]$AcceptedOutputManifest.OutputManifestHash -or [string]$AcceptedState.AcceptedOutputManifestHash -cne [string]$AcceptedOutputManifest.OutputManifestHash -or [string]$AcceptedOutputManifest.AcceptedStateHash -cne [string]$AcceptedState.AcceptedStateHash -or [string]$GenerationManifest.ActiveM3UHash -cne [string]$AcceptedOutputManifest.ActiveM3UHash -or [string]$GenerationManifest.ActiveXMLTVHash -cne [string]$AcceptedOutputManifest.ActiveXMLTVHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: graph hash linkage mismatch.' }
    if ([string]$AcceptedOutputManifest.ActiveXMLTVStatus -cne [string]$AcceptedState.AcceptedXMLTVStatus -or [string]$DecisionManifest.XMLTVDecisionStatus -cne [string]$AcceptedState.AcceptedXMLTVStatus -or (($DecisionManifest.DecisionIds -join ',') -cne ($AcceptedState.AcceptedBindingIds -join ','))) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: decision/XMLTV linkage mismatch.' }
    Assert-ChannelForgeAcceptanceIds $AcceptedState.IncludedCandidateEntryIds 'AcceptedState.IncludedCandidateEntryIds'; Assert-ChannelForgeAcceptanceIds $AcceptedState.ExcludedCandidateEntryIds 'AcceptedState.ExcludedCandidateEntryIds'; Assert-ChannelForgeAcceptanceIds $AcceptedState.AcceptedBindingIds 'AcceptedState.AcceptedBindingIds'; Assert-ChannelForgeAcceptanceDisjointIds $AcceptedState.IncludedCandidateEntryIds $AcceptedState.ExcludedCandidateEntryIds
    if ([string]$AcceptedState.AcceptedXMLTVStatus -eq 'Generated') { Assert-ChannelForgeGenerationHash $AcceptedOutputManifest.ActiveXMLTVHash 'AcceptedOutputManifest.ActiveXMLTVHash'; Assert-ChannelForgeGenerationHash $DecisionManifest.XMLTVDecisionHash 'DecisionManifest.XMLTVDecisionHash' } elseif ($null -ne $AcceptedOutputManifest.ActiveXMLTVHash -or $null -ne $DecisionManifest.XMLTVDecisionHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: NotGenerated graph contains XMLTV evidence.' } elseif ([string]$AcceptedState.AcceptedXMLTVStatus -cne 'NotGenerated') { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: invalid XMLTV status.' }
    if (-not (Test-ChannelForgeGenerationProjectionHash $GenerationManifest 'generation-manifest/v2' 'GenerationManifestHash' @('GenerationId')) -or -not (Test-ChannelForgeGenerationProjectionHash $AcceptedState 'accepted-state/v2' 'AcceptedStateHash' @('GenerationId','AcceptedAtUtc')) -or -not (Test-ChannelForgeGenerationProjectionHash $AcceptedOutputManifest 'previous-output-manifest/v2' 'OutputManifestHash' @('GenerationId','AcceptedStateHash')) -or -not (Test-ChannelForgeGenerationProjectionHash $DecisionManifest 'decision-manifest/v2' 'DecisionManifestHash')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: graph semantic hash mismatch.' }
}

function Assert-ChannelForgeGenerationInputs {
    param([Parameter(Mandatory)]$GenerationManifest,[Parameter(Mandatory)]$AcceptedState,[Parameter(Mandatory)]$AcceptedOutputManifest,[Parameter(Mandatory)]$DecisionManifest,[Parameter(Mandatory)][byte[]]$M3UBytes,[AllowNull()][byte[]]$XMLTVBytes)
    $GenerationManifest=[pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $GenerationManifest); $AcceptedState=[pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $AcceptedState); $AcceptedOutputManifest=[pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $AcceptedOutputManifest); $DecisionManifest=[pscustomobject](ConvertTo-ChannelForgeAcceptanceOrdered $DecisionManifest)
    $id=[string]$GenerationManifest.GenerationId; Assert-ChannelForgeGenerationId $id
    $m3uHash=Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('ActiveM3UHash','OutputM3UHash'); if ($M3UBytes.Length -eq 0 -or (Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $M3UBytes) -cne [string]$m3uHash) { throw 'FAIL_CLOSED: M3U bytes do not match output manifest.' }
    $status=[string](Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('ActiveXMLTVStatus','AcceptedXMLTVStatus')); $xmlHash=Get-ChannelForgeGenerationOutputProperty $AcceptedOutputManifest @('ActiveXMLTVHash','OutputXMLTVHash','AcceptedXMLTVHash')
    if ($status -eq 'Generated') { if ($null -eq $XMLTVBytes -or $XMLTVBytes.Length -eq 0 -or (Get-ChannelForgeDomainHash -Domain 'active-xmltv/v2' -Bytes $XMLTVBytes) -cne [string]$xmlHash) { throw 'FAIL_CLOSED: Generated XMLTV bytes do not match output manifest.' } } elseif ($status -eq 'NotGenerated') { if ($null -ne $XMLTVBytes -and $XMLTVBytes.Length -gt 0 -or $null -ne $xmlHash) { throw 'FAIL_CLOSED: NotGenerated output contains XMLTV evidence.' } } else { throw 'FAIL_CLOSED: unknown XMLTV status.' }
    Assert-ChannelForgeGenerationAcceptedGraph -GenerationManifest $GenerationManifest -AcceptedState $AcceptedState -AcceptedOutputManifest $AcceptedOutputManifest -DecisionManifest $DecisionManifest -GenerationId $id
    return $id
}
function New-ChannelForgeGenerationPointer { param([Parameter(Mandatory)]$GenerationManifest,[Parameter(Mandatory)]$AcceptedState,[Parameter(Mandatory)]$AcceptedOutputManifest); $p=[ordered]@{ Version=$script:ChannelForgeGenerationAcceptanceVersion; GenerationId=[string]$GenerationManifest.GenerationId; GenerationManifestHash=[string]$GenerationManifest.GenerationManifestHash; AcceptedStateHash=[string]$AcceptedState.AcceptedStateHash; AcceptedOutputManifestHash=[string]$AcceptedOutputManifest.OutputManifestHash; PointerHash=$null }; $p.PointerHash=Get-ChannelForgeAcceptanceHash -Domain 'pointer/v2' -Projection $p -HashProperty PointerHash; [pscustomobject]$p }
function New-ChannelForgeGenerationMutationRecord { param([int]$Ordinal,[ValidateSet('Create','Replace','Move','Delete','Verify')][string]$Kind,[Parameter(Mandatory)][string]$RelativePath,[AllowNull()]$Old,[AllowNull()]$New); [pscustomobject][ordered]@{ MutationOrdinal=$Ordinal; MutationKind=$Kind; RelativePath=$RelativePath; ExpectedOldPresence=if($null -eq $Old){'Absent'}else{'Present'}; ExpectedOldByteHash=if($null -eq $Old){$null}else{[string]$Old.ContentHash}; ExpectedOldFileIdentity=if($null -eq $Old){$null}else{$Old.FileIdentity}; ExpectedNewPresence=if($null -eq $New){'Absent'}else{'Present'}; ExpectedNewByteHash=if($null -eq $New){$null}else{[string]$New.ContentHash}; ExpectedNewFileIdentity=if($null -eq $New){$null}else{$New.FileIdentity} } }
function New-ChannelForgeGenerationJournal { param([Parameter(Mandatory)][ValidateSet('Prepared','GenerationPublished','PointerSwapped','Committed')][string]$Stage,[Parameter(Mandatory)][string]$TransactionId,[AllowNull()][object]$ExpectedOldPointerHash,[Parameter(Mandatory)][string]$ExpectedNewPointerHash,[AllowNull()][object]$ExpectedOldGenerationId,[Parameter(Mandatory)][string]$ExpectedNewGenerationId,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MutationRecords,[AllowNull()][object]$OldJournalHash); $j=[ordered]@{ Version=2; TransactionId=$TransactionId; JournalStage=$Stage; ExpectedOldPointerHash=$ExpectedOldPointerHash; ExpectedNewPointerHash=$ExpectedNewPointerHash; ExpectedOldGenerationId=$ExpectedOldGenerationId; ExpectedNewGenerationId=$ExpectedNewGenerationId; MutationRecords=@($MutationRecords | ForEach-Object { ConvertTo-ChannelForgeGenerationCanonicalObject $_ }); OldJournalHash=$OldJournalHash; JournalHash=$null }; $j.JournalHash=Get-ChannelForgeDomainHash -Domain 'journal/v2' -InputObject ([ordered]@{Version=$j.Version;TransactionId=$j.TransactionId;JournalStage=$j.JournalStage;ExpectedOldPointerHash=$j.ExpectedOldPointerHash;ExpectedNewPointerHash=$j.ExpectedNewPointerHash;ExpectedOldGenerationId=$j.ExpectedOldGenerationId;ExpectedNewGenerationId=$j.ExpectedNewGenerationId;MutationRecords=$j.MutationRecords;OldJournalHash=$j.OldJournalHash}); [pscustomobject]$j }

function Assert-ChannelForgeGenerationJournal {
    param([Parameter(Mandatory)]$Journal,[Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    Assert-ChannelForgeGenerationPropertySequence $Journal @('Version','TransactionId','JournalStage','ExpectedOldPointerHash','ExpectedNewPointerHash','ExpectedOldGenerationId','ExpectedNewGenerationId','MutationRecords','OldJournalHash','JournalHash') 'Journal'
    if ([int]$Journal.Version -ne 2 -or [string]$Journal.TransactionId -cnotmatch '^[0-9a-f]{32}$' -or [string]$Journal.JournalStage -notin $script:ChannelForgeGenerationStages) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal identity or phase is invalid.' }
    foreach ($name in @('ExpectedOldPointerHash','OldJournalHash')) { $value=Get-ChannelForgeGenerationPropertyValue $Journal $name; if($null-ne$value){Assert-ChannelForgeGenerationHash $value $name} }; foreach($name in @('ExpectedOldGenerationId')){$value=Get-ChannelForgeGenerationPropertyValue $Journal $name;if($null-ne$value){Assert-ChannelForgeGenerationId ([string]$value)}}; Assert-ChannelForgeGenerationHash $Journal.ExpectedNewPointerHash 'ExpectedNewPointerHash'; Assert-ChannelForgeGenerationId ([string]$Journal.ExpectedNewGenerationId)
    if (-not (Test-ChannelForgeGenerationProjectionHash $Journal 'journal/v2' 'JournalHash')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal hash is invalid.' }
    $records=@($Journal.MutationRecords); if ($records.Count -lt 6 -or $records.Count -gt 7) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: mutation record set is incomplete.' }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal); $id=[string]$Journal.ExpectedNewGenerationId; $required=@('state/accepted-lineup.json'); foreach($name in @('generation.manifest.json','accepted-state.json','accepted-output.manifest.json','decision-manifest.json','merged.m3u')){$required+="state/generations/$id/$name"}
    foreach ($record in $records) {
        Assert-ChannelForgeGenerationPropertySequence $record @('MutationOrdinal','MutationKind','RelativePath','ExpectedOldPresence','ExpectedOldByteHash','ExpectedOldFileIdentity','ExpectedNewPresence','ExpectedNewByteHash','ExpectedNewFileIdentity') 'MutationRecord'
        if ([int]$record.MutationOrdinal -ne $seen.Count -or -not $seen.Add([string]$record.RelativePath)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: mutation ordinal/path is invalid.' }
        if ([string]$record.RelativePath -notin $required -and [string]$record.RelativePath -cne "state/generations/$id/merged.xml") { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: mutation path is unrelated.' }
        $kind=[string]$record.MutationKind; if ($kind -notin @('Create','Replace','Move','Delete','Verify')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: mutation kind is invalid.' }
        if ($kind -eq 'Create' -and ($record.ExpectedOldPresence -ne 'Absent' -or $record.ExpectedNewPresence -ne 'Present')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: invalid Create mutation.' }
        if ($kind -eq 'Replace' -and ($record.ExpectedOldPresence -ne 'Present' -or $record.ExpectedNewPresence -ne 'Present')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: invalid Replace mutation.' }
        if ($kind -eq 'Delete' -and ($record.ExpectedOldPresence -ne 'Present' -or $record.ExpectedNewPresence -ne 'Absent')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: invalid Delete mutation.' }
        if ($kind -in @('Move','Verify')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: unsupported unpaired mutation kind.' }
        foreach($field in @('ExpectedOldByteHash','ExpectedNewByteHash')) { $present=if($field -like '*Old*'){$record.ExpectedOldPresence}else{$record.ExpectedNewPresence}; $value=Get-ChannelForgeGenerationPropertyValue $record $field; if($present -eq 'Present'){Assert-ChannelForgeGenerationHash $value $field}elseif($null -ne $value){throw 'FAIL_CLOSED_RECOVERY_REQUIRED: absent mutation has a hash.'} }
        foreach($field in @('ExpectedOldFileIdentity','ExpectedNewFileIdentity')) { $present=if($field -like '*Old*'){$record.ExpectedOldPresence}else{$record.ExpectedNewPresence}; $value=Get-ChannelForgeGenerationPropertyValue $record $field; if($present -eq 'Present'){foreach($n in @('VolumeSerial','FileId','ByteLength','LastWriteUtcTicks')){if($null -eq (Get-ChannelForgeGenerationPropertyValue $value $n)){throw 'FAIL_CLOSED_RECOVERY_REQUIRED: incomplete mutation identity.'}}}elseif($null -ne $value){throw 'FAIL_CLOSED_RECOVERY_REQUIRED: absent mutation has identity.'} }
    }
    foreach($path in $required){if(-not $seen.Contains($path)){throw "FAIL_CLOSED_RECOVERY_REQUIRED: journal missing mutation $path."}}
}

function Publish-ChannelForgeGenerationJournal {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$AuthoritativePath,[Parameter(Mandatory)][string]$StagedPath,[Parameter(Mandatory)]$Journal,[AllowNull()][string]$FaultHook,[Parameter(Mandatory)][string]$StageName)
    $bytes=ConvertTo-ChannelForgeGenerationBytes $Journal; $suffix=if($StageName -eq 'Prepared'){'Prepared'}else{$StageName}
    Invoke-ChannelForgeGenerationFaultHook $FaultHook "JournalStageWrite.$suffix"
    Write-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path $StagedPath -Bytes $bytes -FaultHook $FaultHook -WriteHook "JournalWrite.$suffix" -FlushHook "JournalFlush.$suffix" -ReopenHook "JournalReopenHash.$suffix" -Domain 'journal/v2' | Out-Null
    Invoke-ChannelForgeGenerationFaultHook $FaultHook "JournalStageFlush.$suffix"; Invoke-ChannelForgeGenerationFaultHook $FaultHook "JournalStageReopenHash.$suffix"
    Invoke-ChannelForgeGenerationFaultHook $FaultHook "JournalBeforeReplace.$suffix"
    $backup="$AuthoritativePath.previous"; Assert-ChannelForgeGenerationMutationPath -RepositoryRoot $RepositoryRoot -Path $StagedPath -AllowMissing | Out-Null; Assert-ChannelForgeGenerationMutationPath -RepositoryRoot $RepositoryRoot -Path $AuthoritativePath -AllowMissing | Out-Null; Assert-ChannelForgeGenerationMutationPath -RepositoryRoot $RepositoryRoot -Path $backup -AllowMissing | Out-Null; Assert-ChannelForgeGenerationSameVolume -RepositoryRoot $RepositoryRoot -Paths @($StagedPath,$AuthoritativePath,$backup)
    if ([IO.File]::Exists($AuthoritativePath)) { if ([IO.File]::Exists($backup)) { $prior=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $backup -Domain 'journal/v2'; $authority=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $AuthoritativePath -Domain 'journal/v2'; if ([string]$prior.Object.JournalHash -cne [string]$authority.Object.OldJournalHash){throw 'FAIL_CLOSED: journal chain backup is invalid.'}; [ChannelForge.GenerationStore]::DeleteFile($backup) }; [ChannelForge.GenerationStore]::ReplaceFile($StagedPath,$AuthoritativePath,$backup) } else { [ChannelForge.GenerationStore]::MoveFile($StagedPath,$AuthoritativePath) }
    $verified=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $AuthoritativePath -Domain 'journal/v2'; Assert-ChannelForgeGenerationJournal -Journal $verified.Object -RepositoryRoot $RepositoryRoot -Paths (Get-ChannelForgeGenerationPaths $RepositoryRoot); if ([string]$verified.Object.JournalHash -cne [string]$Journal.JournalHash){throw 'FAIL_CLOSED: authoritative journal hash mismatch.'}
    Invoke-ChannelForgeGenerationFaultHook $FaultHook "JournalAfterReplace.$suffix"
    return $verified
}

function Get-ChannelForgeGenerationCurrentSnapshot {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    if (-not [IO.File]::Exists($Paths.Current)) { return $null }
    $pointer=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $Paths.Current -Domain 'pointer/v2'; Assert-ChannelForgeGenerationPropertySequence $pointer.Object @('Version','GenerationId','GenerationManifestHash','AcceptedStateHash','AcceptedOutputManifestHash','PointerHash') 'Pointer'; Assert-ChannelForgeGenerationHash $pointer.Object.PointerHash 'PointerHash'; Assert-ChannelForgeGenerationId ([string]$pointer.Object.GenerationId); if(-not(Test-ChannelForgeGenerationProjectionHash $pointer.Object 'pointer/v2' 'PointerHash')){throw 'FAIL_CLOSED: current pointer hash is invalid.'}
    $generation=Join-Path $Paths.Generations ([string]$pointer.Object.GenerationId); if(-not [IO.Directory]::Exists($generation)){throw 'FAIL_CLOSED: current generation is missing.'}
    $manifest=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'generation.manifest.json') -Domain 'generation-manifest/v2'; $state=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'accepted-state.json') -Domain 'accepted-state/v2'; $output=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'accepted-output.manifest.json') -Domain 'previous-output-manifest/v2'; $decision=Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'decision-manifest.json') -Domain 'decision-manifest/v2'; Assert-ChannelForgeGenerationAcceptedGraph $manifest.Object $state.Object $output.Object $decision.Object ([string]$pointer.Object.GenerationId)
    if([string]$pointer.Object.GenerationManifestHash -cne [string]$manifest.Object.GenerationManifestHash -or [string]$pointer.Object.AcceptedStateHash -cne [string]$state.Object.AcceptedStateHash -or [string]$pointer.Object.AcceptedOutputManifestHash -cne [string]$output.Object.OutputManifestHash){throw 'FAIL_CLOSED: pointer graph mismatch.'}
    $m3u=Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'merged.m3u') -Domain 'active-m3u/v2'; if([string]$m3u.ContentHash -cne [string]$output.Object.ActiveM3UHash){throw 'FAIL_CLOSED: current M3U hash mismatch.'}
    $xml=$null; if([string]$output.Object.ActiveXMLTVStatus -eq 'Generated'){$xml=Read-ChannelForgeGenerationFile -RepositoryRoot $RepositoryRoot -Path (Join-Path $generation 'merged.xml') -Domain 'active-xmltv/v2'; if([string]$xml.ContentHash -cne [string]$output.Object.ActiveXMLTVHash){throw 'FAIL_CLOSED: current XMLTV hash mismatch.'}}elseif([IO.File]::Exists((Join-Path $generation 'merged.xml'))){throw 'FAIL_CLOSED: NotGenerated generation contains XMLTV.'}
    $allowed=@('generation.manifest.json','accepted-state.json','accepted-output.manifest.json','decision-manifest.json','merged.m3u');if($null -ne $xml){$allowed+='merged.xml'};foreach($child in [IO.Directory]::GetFileSystemEntries($generation)){if([IO.Path]::GetFileName($child)-notin $allowed){throw 'FAIL_CLOSED: generation contains unexpected child.'}}
    [pscustomobject][ordered]@{Pointer=$pointer;GenerationPath=$generation;Manifest=$manifest;State=$state;Output=$output;Decision=$decision;M3U=$m3u;XMLTV=$xml}
}

function Assert-ChannelForgeGenerationCleanupOwnership {
    param([Parameter(Mandatory)]$Journal,[Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    $transactionRoot = Join-Path $Paths.Staging ([string]$Journal.TransactionId)
    if (-not [IO.Directory]::Exists($transactionRoot)) { return }
    Assert-ChannelForgeGenerationMutationPath -RepositoryRoot $RepositoryRoot -Path $transactionRoot | Out-Null
    $id = [string]$Journal.ExpectedNewGenerationId
    $records = @($Journal.MutationRecords)
    $expected = @{}
    foreach ($record in $records) { if ([string]$record.RelativePath -like "state/generations/$id/*") { $expected[[IO.Path]::GetFileName([string]$record.RelativePath)] = $record } }
    $pointerRecord = $records | Where-Object { [string]$_.RelativePath -eq 'state/accepted-lineup.json' } | Select-Object -First 1
    foreach ($entry in [IO.Directory]::GetFileSystemEntries($transactionRoot)) {
        $name = [IO.Path]::GetFileName($entry)
        if ($name -eq 'generation') {
            $generationRoot = Join-Path $transactionRoot "generation/$id"
            if (-not [IO.Directory]::Exists($generationRoot)) { $generationRoot = Join-Path $Paths.Generations $id }
            if (-not [IO.Directory]::Exists($generationRoot)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: cleanup generation owner missing.' }
            foreach ($child in [IO.Directory]::GetFileSystemEntries($generationRoot)) {
                $childName = [IO.Path]::GetFileName($child)
                if (-not $expected.ContainsKey($childName)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: unrelated cleanup evidence.' }
                $record = $expected[$childName]
                $domain = if ($childName -like '*.json') { Get-ChannelForgeGenerationDocumentDomain $childName } elseif ($childName -eq 'merged.m3u') { 'active-m3u/v2' } else { 'active-xmltv/v2' }
                $actual = if ($childName -like '*.json') { Read-ChannelForgeGenerationDocument $RepositoryRoot $child $domain } else { Read-ChannelForgeGenerationFile $RepositoryRoot $child $domain }
                if ([string]$actual.ContentHash -cne [string]$record.ExpectedNewByteHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: cleanup bytes are not owned.' }
                Assert-ChannelForgeGenerationIdentity -Expected $record.ExpectedNewFileIdentity -Actual $actual.FileIdentity -Name $child
            }
            if ([IO.Path]::GetFullPath($generationRoot) -eq [IO.Path]::GetFullPath((Join-Path $Paths.Generations $id)) -and [IO.Directory]::Exists($generationRoot)) {
                foreach ($immutableFile in [IO.Directory]::GetFiles($generationRoot)) {
                    [IO.File]::SetAttributes($immutableFile, ([IO.File]::GetAttributes($immutableFile) -bor [IO.FileAttributes]::ReadOnly))
                }
            }
        } elseif ($name -eq 'accepted-lineup.json') {
            if ($null -eq $pointerRecord) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: cleanup pointer has no owner.' }
            $actual = Read-ChannelForgeGenerationDocument $RepositoryRoot $entry 'pointer/v2'
            if ([string]$actual.ContentHash -cne [string]$pointerRecord.ExpectedNewByteHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: cleanup pointer is not owned.' }
            Assert-ChannelForgeGenerationIdentity -Expected $pointerRecord.ExpectedNewFileIdentity -Actual $actual.FileIdentity -Name $entry
        } elseif ($name -eq 'accepted-lineup.journal.json') {
            $actual = Read-ChannelForgeGenerationDocument $RepositoryRoot $entry 'journal/v2'
            if ([string]$actual.Object.JournalHash -cne [string]$Journal.JournalHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: cleanup journal is unrelated.' }
        } else { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: unrelated transaction child.' }
    }
}

function Publish-ChannelForgeGenerationCore {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$GenerationManifest,[Parameter(Mandatory)]$AcceptedState,[Parameter(Mandatory)]$AcceptedOutputManifest,[Parameter(Mandatory)]$DecisionManifest,[Parameter(Mandatory)][byte[]]$M3UBytes,[AllowNull()][byte[]]$XMLTVBytes,[AllowNull()][string]$FaultHook)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [IO.Directory]::Exists($root)) { Ensure-ChannelForgeGenerationDirectory $root $root | Out-Null }
    Assert-ChannelForgeGenerationSafePath $root $root | Out-Null
    $id = Assert-ChannelForgeGenerationInputs $GenerationManifest $AcceptedState $AcceptedOutputManifest $DecisionManifest $M3UBytes $XMLTVBytes
    $paths = Get-ChannelForgeGenerationPaths $root
    Ensure-ChannelForgeGenerationDirectory $root $paths.State | Out-Null
    Ensure-ChannelForgeGenerationDirectory $root $paths.Generations | Out-Null
    Ensure-ChannelForgeGenerationDirectory $root $paths.Staging | Out-Null
    Assert-ChannelForgeGenerationSameVolume $root @($paths.State,$paths.Generations,$paths.Staging,$paths.Current,$paths.Previous,$paths.Journal)
    $lease = $null
    $tx = [guid]::NewGuid().ToString('N')
    $transactionRoot = Join-Path $paths.Staging $tx
    $stagedGeneration = Join-Path $transactionRoot "generation/$id"
    $finalGeneration = Join-Path $paths.Generations $id
    try {
        try { $lease = [ChannelForge.GenerationStore]::AcquireLock($paths.Lock) } catch { throw "FAIL_CLOSED: $($_.Exception.Message)" }
        $lease.WriteMetadata([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json ([ordered]@{TransactionId=$tx;ProcessId=$PID}) -Compress)))
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'VerifyCurrentPointer.Before'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.GenerationManifest.Before'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.AcceptedState.Before'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.OutputManifest.Before'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.M3U.Before'
        if ([string]$AcceptedOutputManifest.ActiveXMLTVStatus -eq 'Generated') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.XMLTV.Before' }
        $current = Get-ChannelForgeGenerationCurrentSnapshot $root $paths
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.GenerationManifest.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.AcceptedState.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.OutputManifest.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.M3U.After'
        if ([string]$AcceptedOutputManifest.ActiveXMLTVStatus -eq 'Generated') { Invoke-ChannelForgeGenerationFaultHook $FaultHook 'Verify.XMLTV.After' }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'VerifyCurrentPointer.After'
        if ($null -eq $current -and [IO.File]::Exists($paths.Previous)) { throw 'FAIL_CLOSED: previous pointer without current.' }
        if ($null -ne $current -and [string]::IsNullOrEmpty([string]$AcceptedState.PreviousStateHash)) { throw 'FAIL_CLOSED: missing parent state hash.' }
        if ($null -ne $current -and [string]$AcceptedState.PreviousStateHash -cne [string]$current.State.Object.AcceptedStateHash) { throw 'FAIL_CLOSED: parent state mismatch.' }
        if ($null -eq $current -and -not [string]::IsNullOrEmpty([string]$AcceptedState.PreviousStateHash)) { throw 'FAIL_CLOSED: first generation has parent.' }
        if ($null -ne $current) {
            if ($null -eq $GenerationManifest.PreviousOutputManifestHash -or [string]$GenerationManifest.PreviousOutputManifestHash -cne [string]$current.Output.Object.OutputManifestHash) { throw 'FAIL_CLOSED: previous output manifest mismatch.' }
        } elseif ($null -ne $GenerationManifest.PreviousOutputManifestHash) { throw 'FAIL_CLOSED: first generation has previous output manifest.' }
        if ([IO.Directory]::Exists($finalGeneration)) { throw 'FAIL_CLOSED: generation collision.' }
        Ensure-ChannelForgeGenerationDirectory $root $stagedGeneration | Out-Null
        $files = @(
            @('generation.manifest.json',(ConvertTo-ChannelForgeGenerationBytes $GenerationManifest),'generation-manifest/v2','GenerationManifest','A01','A02','A03'),
            @('accepted-state.json',(ConvertTo-ChannelForgeGenerationBytes $AcceptedState),'accepted-state/v2','AcceptedState','A04','A05','A06'),
            @('accepted-output.manifest.json',(ConvertTo-ChannelForgeGenerationBytes $AcceptedOutputManifest),'previous-output-manifest/v2','AcceptedOutputManifest','A07','A08','A09'),
            @('decision-manifest.json',(ConvertTo-ChannelForgeGenerationBytes $DecisionManifest),'decision-manifest/v2','DecisionManifest','A10','A11','A12'),
            @('merged.m3u',$M3UBytes,'active-m3u/v2','M3U','A13','A14','A15')
        )
        if ([string]$AcceptedOutputManifest.ActiveXMLTVStatus -eq 'Generated') { $files += ,@('merged.xml',$XMLTVBytes,'active-xmltv/v2','XMLTV','A16','A17','A18') }
        $snap = @{}
        foreach ($file in $files) { $snap[$file[0]] = Write-ChannelForgeGenerationFile $root (Join-Path $stagedGeneration $file[0]) $file[1] $FaultHook "StageWrite.$($file[3])" "StageFlush.$($file[3])" "StageReopenHash.$($file[3])" $file[2] }
        $pointer = New-ChannelForgeGenerationPointer $GenerationManifest $AcceptedState $AcceptedOutputManifest
        $stagedPointer = Write-ChannelForgeGenerationFile $root (Join-Path $transactionRoot 'accepted-lineup.json') (ConvertTo-ChannelForgeGenerationBytes $pointer) $FaultHook 'StageWrite.Pointer' 'StageFlush.Pointer' 'StageReopenHash.Pointer' 'pointer/v2'
        $oldPointerHash = if ($null -eq $current) { $null } else { [string]$current.Pointer.Object.PointerHash }
        $oldGenerationId = if ($null -eq $current) { $null } else { [string]$current.Pointer.Object.GenerationId }
        $oldJournalHash = if ([IO.File]::Exists($paths.Journal)) { [string](Read-ChannelForgeGenerationDocument $root $paths.Journal 'journal/v2').Object.JournalHash } else { $null }
        $records = [Collections.Generic.List[object]]::new()
        $ordinal = 0
        foreach ($file in $files) { [void]$records.Add((New-ChannelForgeGenerationMutationRecord $ordinal Create "state/generations/$id/$($file[0])" $null $snap[$file[0]])); $ordinal++ }
        $pointerKind = if ($null -eq $current) { 'Create' } else { 'Replace' }
        [void]$records.Add((New-ChannelForgeGenerationMutationRecord $ordinal $pointerKind 'state/accepted-lineup.json' $(if ($null -eq $current) { $null } else { $current.Pointer }) $stagedPointer))
        $stagedJournal = Join-Path $transactionRoot 'accepted-lineup.journal.json'
        $journal = New-ChannelForgeGenerationJournal Prepared $tx $oldPointerHash $pointer.PointerHash $oldGenerationId $id @($records) $oldJournalHash
        Publish-ChannelForgeGenerationJournal $root $paths.Journal $stagedJournal $journal $FaultHook Prepared | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'GenerationDirectoryMove.Before'
        Assert-ChannelForgeGenerationMutationPath $root $stagedGeneration | Out-Null
        Assert-ChannelForgeGenerationMutationPath $root $finalGeneration -AllowMissing | Out-Null
        [ChannelForge.GenerationStore]::MoveDirectory($stagedGeneration,$finalGeneration)
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'GenerationDirectoryMove.After'
        $journal = New-ChannelForgeGenerationJournal GenerationPublished $tx $oldPointerHash $pointer.PointerHash $oldGenerationId $id @($records) $journal.JournalHash
        Publish-ChannelForgeGenerationJournal $root $paths.Journal $stagedJournal $journal $FaultHook GenerationPublished | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'PointerReplace.Before'
        Assert-ChannelForgeGenerationMutationPath $root (Join-Path $transactionRoot 'accepted-lineup.json') -AllowMissing | Out-Null
        Assert-ChannelForgeGenerationMutationPath $root $paths.Current -AllowMissing | Out-Null
        Assert-ChannelForgeGenerationMutationPath $root $paths.Previous -AllowMissing | Out-Null
        if ($null -ne $current) { [ChannelForge.GenerationStore]::ReplaceFile((Join-Path $transactionRoot 'accepted-lineup.json'),$paths.Current,$paths.Previous) } else { [ChannelForge.GenerationStore]::MoveFile((Join-Path $transactionRoot 'accepted-lineup.json'),$paths.Current) }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'PointerReplace.After'
        $journal = New-ChannelForgeGenerationJournal PointerSwapped $tx $oldPointerHash $pointer.PointerHash $oldGenerationId $id @($records) $journal.JournalHash
        Publish-ChannelForgeGenerationJournal $root $paths.Journal $stagedJournal $journal $FaultHook PointerSwapped | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'VerifyCurrentPointer.Before'
        $null = Get-ChannelForgeGenerationCurrentSnapshot $root $paths
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'VerifyCurrentPointer.After'
        $journal = New-ChannelForgeGenerationJournal Committed $tx $oldPointerHash $pointer.PointerHash $oldGenerationId $id @($records) $journal.JournalHash
        Publish-ChannelForgeGenerationJournal $root $paths.Journal $stagedJournal $journal $FaultHook Committed | Out-Null
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.GenerationStage.Before'
        Assert-ChannelForgeGenerationCleanupOwnership $journal $root $paths
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.TransactionDirectory.Before'
        if ([IO.Directory]::Exists($transactionRoot)) { Assert-ChannelForgeGenerationMutationPath $root $transactionRoot | Out-Null; [ChannelForge.GenerationStore]::DeleteDirectory($transactionRoot) }
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.TransactionDirectory.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.GenerationStage.After'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.PointerJournalBackup.Before'
        Invoke-ChannelForgeGenerationFaultHook $FaultHook 'CleanupDelete.PointerJournalBackup.After'
        if ($null -ne $lease) { $lease.Dispose(); $lease = $null }
        if ([IO.File]::Exists($paths.Lock)) { Assert-ChannelForgeGenerationMutationPath $root $paths.Lock | Out-Null; [ChannelForge.GenerationStore]::DeleteFile($paths.Lock) }
        [pscustomobject][ordered]@{Outcome='NEW';TransactionId=$tx;GenerationId=$id;PointerHash=[string]$pointer.PointerHash;GenerationManifestHash=[string]$GenerationManifest.GenerationManifestHash}
    } finally { if ($null -ne $lease) { $lease.Dispose() } }
}

function Get-ChannelForgeGenerationDocumentDomain { param([Parameter(Mandatory)][string]$Name); switch($Name){'generation.manifest.json'{'generation-manifest/v2'}'accepted-state.json'{'accepted-state/v2'}'accepted-output.manifest.json'{'previous-output-manifest/v2'}'decision-manifest.json'{'decision-manifest/v2'}'accepted-lineup.json'{'pointer/v2'}default{$null}} }
function Assert-ChannelForgeGenerationJournalEvidence {
    param([Parameter(Mandatory)]$Journal,[Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    Assert-ChannelForgeGenerationJournal $Journal $RepositoryRoot $Paths
    $tx = Join-Path $Paths.Staging ([string]$Journal.TransactionId)
    $stage = [string]$Journal.JournalStage
    $id = [string]$Journal.ExpectedNewGenerationId
    $generationPath = if ($stage -eq 'Prepared') { Join-Path $tx "generation/$id" } else { Join-Path $Paths.Generations $id }
    if (-not [IO.Directory]::Exists($generationPath)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal generation evidence missing.' }
    $manifest = Read-ChannelForgeGenerationDocument $RepositoryRoot (Join-Path $generationPath 'generation.manifest.json') 'generation-manifest/v2'
    $state = Read-ChannelForgeGenerationDocument $RepositoryRoot (Join-Path $generationPath 'accepted-state.json') 'accepted-state/v2'
    $output = Read-ChannelForgeGenerationDocument $RepositoryRoot (Join-Path $generationPath 'accepted-output.manifest.json') 'previous-output-manifest/v2'
    $decision = Read-ChannelForgeGenerationDocument $RepositoryRoot (Join-Path $generationPath 'decision-manifest.json') 'decision-manifest/v2'
    $m3u = Read-ChannelForgeGenerationFile $RepositoryRoot (Join-Path $generationPath 'merged.m3u') 'active-m3u/v2'
    $xml = $null
    if ([string]$output.Object.ActiveXMLTVStatus -eq 'Generated') { $xml = Read-ChannelForgeGenerationFile $RepositoryRoot (Join-Path $generationPath 'merged.xml') 'active-xmltv/v2' }
    $allowed = @('generation.manifest.json','accepted-state.json','accepted-output.manifest.json','decision-manifest.json','merged.m3u')
    if ($null -ne $xml) { $allowed += 'merged.xml' }
    foreach ($child in [IO.Directory]::GetFileSystemEntries($generationPath)) { if ([IO.Path]::GetFileName($child) -notin $allowed) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal generation has unexpected child.' } }
    Assert-ChannelForgeGenerationAcceptedGraph $manifest.Object $state.Object $output.Object $decision.Object $id
    if ([string]$m3u.ContentHash -cne [string]$output.Object.ActiveM3UHash -or ($null -ne $xml -and [string]$xml.ContentHash -cne [string]$output.Object.ActiveXMLTVHash)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal artifact hash mismatch.' }
    $stagedPointer = Join-Path $tx 'accepted-lineup.json'
    $currentPointer = if ([IO.File]::Exists($Paths.Current)) { Read-ChannelForgeGenerationDocument $RepositoryRoot $Paths.Current 'pointer/v2' } else { $null }
    $previousPointer = if ([IO.File]::Exists($Paths.Previous)) { Read-ChannelForgeGenerationDocument $RepositoryRoot $Paths.Previous 'pointer/v2' } else { $null }
    $pointer = if ($stage -eq 'Prepared' -or ($stage -eq 'GenerationPublished' -and [IO.File]::Exists($stagedPointer))) { Read-ChannelForgeGenerationDocument $RepositoryRoot $stagedPointer 'pointer/v2' } else { $currentPointer }
    if ($null -eq $pointer -or [string]$pointer.Object.PointerHash -cne [string]$Journal.ExpectedNewPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal pointer evidence mismatch.' }
    if ([string]$pointer.Object.GenerationId -cne $id -or [string]$pointer.Object.GenerationManifestHash -cne [string]$manifest.Object.GenerationManifestHash -or [string]$pointer.Object.AcceptedStateHash -cne [string]$state.Object.AcceptedStateHash -or [string]$pointer.Object.AcceptedOutputManifestHash -cne [string]$output.Object.OutputManifestHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal pointer graph mismatch.' }
    if ($null -ne $Journal.OldJournalHash) {
        if (-not [IO.File]::Exists($Paths.JournalPrevious)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal predecessor missing.' }
        $predecessor = Read-ChannelForgeGenerationDocument $RepositoryRoot $Paths.JournalPrevious 'journal/v2'
        Assert-ChannelForgeGenerationJournal $predecessor.Object $RepositoryRoot $Paths
        if ([string]$predecessor.Object.JournalHash -cne [string]$Journal.OldJournalHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: journal predecessor hash mismatch.' }
    }
    if ($stage -eq 'Prepared') {
        if ([IO.Directory]::Exists((Join-Path $Paths.Generations $id))) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: Prepared final generation exists.' }
        if ($null -ne $currentPointer) {
            if ($null -eq $Journal.ExpectedOldPointerHash -or [string]$currentPointer.Object.PointerHash -cne [string]$Journal.ExpectedOldPointerHash -or [string]$currentPointer.Object.GenerationId -cne [string]$Journal.ExpectedOldGenerationId) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: Prepared old pointer mismatch.' }
        } elseif ($null -ne $Journal.ExpectedOldPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: Prepared old pointer is missing.' }
    } elseif ($stage -eq 'GenerationPublished') {
        $hasStagedPointer = [IO.File]::Exists($stagedPointer)
        if ($hasStagedPointer) {
            if ($null -ne $currentPointer) {
                if ($null -eq $Journal.ExpectedOldPointerHash -or [string]$currentPointer.Object.PointerHash -cne [string]$Journal.ExpectedOldPointerHash -or [string]$currentPointer.Object.GenerationId -cne [string]$Journal.ExpectedOldGenerationId) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: GenerationPublished old pointer mismatch. actual=$($currentPointer.Object.PointerHash)/$($currentPointer.Object.GenerationId) expected=$($Journal.ExpectedOldPointerHash)/$($Journal.ExpectedOldGenerationId)" }
            } elseif ($null -ne $Journal.ExpectedOldPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: GenerationPublished old pointer is missing.' }
        } elseif ($null -eq $currentPointer -or [string]$currentPointer.Object.PointerHash -cne [string]$Journal.ExpectedNewPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: GenerationPublished pointer state is ambiguous.' }
    } else {
        if ($null -eq $currentPointer -or [string]$currentPointer.Object.PointerHash -cne [string]$Journal.ExpectedNewPointerHash) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: swapped current pointer mismatch. actual=$($currentPointer.Object.PointerHash) expected=$($Journal.ExpectedNewPointerHash)" }
        if ($null -eq $Journal.ExpectedOldPointerHash) {
            if ($null -ne $previousPointer) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: first-generation previous pointer exists.' }
        } elseif ($null -eq $previousPointer -or [string]$previousPointer.Object.PointerHash -cne [string]$Journal.ExpectedOldPointerHash -or [string]$previousPointer.Object.GenerationId -cne [string]$Journal.ExpectedOldGenerationId) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: swapped previous pointer mismatch.' }
    }
    foreach ($record in @($Journal.MutationRecords)) {
        $relative = [string]$record.RelativePath
        $actualPath = if ($relative -eq 'state/accepted-lineup.json') {
            if ($stage -eq 'Prepared' -or ($stage -eq 'GenerationPublished' -and [IO.File]::Exists($stagedPointer))) { $stagedPointer } else { $Paths.Current }
        } else { Join-Path $generationPath ([IO.Path]::GetFileName($relative)) }
        if (-not [IO.File]::Exists($actualPath)) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: journal mutation evidence missing '$relative'." }
        $name = [IO.Path]::GetFileName($relative)
        $domain = if ($relative -eq 'state/accepted-lineup.json') { 'pointer/v2' } elseif ($name -like '*.json') { Get-ChannelForgeGenerationDocumentDomain $name } elseif ($name -eq 'merged.m3u') { 'active-m3u/v2' } else { 'active-xmltv/v2' }
        $actual = if ($name -like '*.json') { Read-ChannelForgeGenerationDocument $RepositoryRoot $actualPath $domain } else { Read-ChannelForgeGenerationFile $RepositoryRoot $actualPath $domain }
        if ([string]$actual.ContentHash -cne [string]$record.ExpectedNewByteHash) { throw "FAIL_CLOSED_RECOVERY_REQUIRED: journal mutation bytes mismatch '$relative'." }
        Assert-ChannelForgeGenerationIdentity -Expected $record.ExpectedNewFileIdentity -Actual $actual.FileIdentity -Name $actualPath
    }
}
function Get-ChannelForgeNoJournalRecoveryOutcome {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Paths)
    if ([IO.File]::Exists($Paths.JournalPrevious)) {
        $previousJournal = Read-ChannelForgeGenerationDocument $RepositoryRoot $Paths.JournalPrevious 'journal/v2'
        Assert-ChannelForgeGenerationJournal $previousJournal.Object $RepositoryRoot $Paths
    }
    if ([IO.Directory]::Exists($Paths.Staging) -and @([IO.Directory]::GetDirectories($Paths.Staging)).Count -gt 0) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: staging remnant.' }
    if (-not [IO.File]::Exists($Paths.Current)) {
        if ([IO.Directory]::Exists($Paths.Generations) -and @([IO.Directory]::GetDirectories($Paths.Generations)).Count -gt 0) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: generation without pointer.' }
        return [pscustomobject][ordered]@{ Outcome='INITIAL_BASELINE_REQUIRED'; Mutation='None' }
    }
    $current = Get-ChannelForgeGenerationCurrentSnapshot $RepositoryRoot $Paths
    return [pscustomobject][ordered]@{ Outcome='ACCEPTED_STATE_VALID'; Mutation='None'; GenerationId=[string]$current.Pointer.Object.GenerationId; PointerHash=[string]$current.Pointer.Object.PointerHash }
}

function Recover-ChannelForgeAcceptedStateCore {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $null = Initialize-ChannelForgeGenerationStore
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if ($root.StartsWith('\\')) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: UNC/SMB roots are not accepted.' }
    if (-not [IO.Directory]::Exists($root)) { return [pscustomobject][ordered]@{ Outcome='INITIAL_BASELINE_REQUIRED'; Mutation='None' } }
    Assert-ChannelForgeGenerationSafePath $root $root | Out-Null
    $paths = Get-ChannelForgeGenerationPaths $root
    if (-not [IO.Directory]::Exists($paths.State)) { return [pscustomobject][ordered]@{ Outcome='INITIAL_BASELINE_REQUIRED'; Mutation='None' } }
    Assert-ChannelForgeGenerationSafePath $root $paths.State | Out-Null
    $lease = $null
    try {
        $lease = [ChannelForge.GenerationStore]::AcquireLock($paths.Lock)
        if (-not [IO.File]::Exists($paths.Journal)) { return Get-ChannelForgeNoJournalRecoveryOutcome $root $paths }
        $journal = Read-ChannelForgeGenerationDocument $root $paths.Journal 'journal/v2'
        $object = $journal.Object
        Assert-ChannelForgeGenerationJournalEvidence $object $root $paths
        $current = if ([IO.File]::Exists($paths.Current)) { Get-ChannelForgeGenerationCurrentSnapshot $root $paths } else { $null }
        $transactionRoot = Join-Path $paths.Staging ([string]$object.TransactionId)
        $stagePointer = Join-Path $transactionRoot 'accepted-lineup.json'
        if ($object.JournalStage -eq 'Prepared') { return [pscustomobject][ordered]@{ Outcome='OLD'; Mutation='None'; JournalStage='Prepared' } }
        if ($object.JournalStage -eq 'GenerationPublished') {
            $isNew = $null -ne $current -and [string]$current.Pointer.Object.PointerHash -ceq [string]$object.ExpectedNewPointerHash
            if (-not $isNew) {
                if (-not [IO.File]::Exists($stagePointer)) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: staged pointer missing.' }
                if ($null -ne $current) { [ChannelForge.GenerationStore]::ReplaceFile($stagePointer,$paths.Current,$paths.Previous) } else { [ChannelForge.GenerationStore]::MoveFile($stagePointer,$paths.Current) }
                $current = Get-ChannelForgeGenerationCurrentSnapshot $root $paths
                if ([string]$current.Pointer.Object.PointerHash -cne [string]$object.ExpectedNewPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: pointer replacement postcondition mismatch.' }
            }
            $next = New-ChannelForgeGenerationJournal PointerSwapped $object.TransactionId $object.ExpectedOldPointerHash $object.ExpectedNewPointerHash $object.ExpectedOldGenerationId $object.ExpectedNewGenerationId @($object.MutationRecords) $object.JournalHash
            Publish-ChannelForgeGenerationJournal $root $paths.Journal (Join-Path $transactionRoot 'accepted-lineup.journal.json') $next $null PointerSwapped | Out-Null
            return [pscustomobject][ordered]@{ Outcome='NEW'; Mutation='PublishPointerSwapped'; JournalStage='PointerSwapped' }
        }
        if ($object.JournalStage -eq 'PointerSwapped') {
            if ($null -eq $current -or [string]$current.Pointer.Object.PointerHash -cne [string]$object.ExpectedNewPointerHash) { throw 'FAIL_CLOSED_RECOVERY_REQUIRED: pointer-swapped authority mismatch.' }
            $next = New-ChannelForgeGenerationJournal Committed $object.TransactionId $object.ExpectedOldPointerHash $object.ExpectedNewPointerHash $object.ExpectedOldGenerationId $object.ExpectedNewGenerationId @($object.MutationRecords) $object.JournalHash
            Publish-ChannelForgeGenerationJournal $root $paths.Journal (Join-Path $transactionRoot 'accepted-lineup.journal.json') $next $null Committed | Out-Null
            return [pscustomobject][ordered]@{ Outcome='NEW'; Mutation='PublishCommitted'; JournalStage='Committed' }
        }
        if ($object.JournalStage -eq 'Committed') {
            $null = Get-ChannelForgeGenerationCurrentSnapshot $root $paths
            Assert-ChannelForgeGenerationCleanupOwnership $object $root $paths
            if ([IO.Directory]::Exists($transactionRoot)) { [ChannelForge.GenerationStore]::DeleteDirectory($transactionRoot) }
            return [pscustomobject][ordered]@{ Outcome='NEW'; Mutation='CleanupOnly'; JournalStage='Committed'; GenerationId=[string]$current.Pointer.Object.GenerationId }
        }
        throw 'FAIL_CLOSED_RECOVERY_REQUIRED: unsupported journal stage.'
    } catch {
        if ($_.Exception.Message -like 'FAIL_CLOSED_RECOVERY_REQUIRED*') { throw }
        throw "FAIL_CLOSED_RECOVERY_REQUIRED: $($_.Exception.Message)"
    } finally { if ($null -ne $lease) { $lease.Dispose() } }
}
