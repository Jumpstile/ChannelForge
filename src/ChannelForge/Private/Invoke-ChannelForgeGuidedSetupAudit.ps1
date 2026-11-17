$script:ChannelForgeGuidedSetupAuditVersion = 'guided-setup/audit/v1'

function Get-ChannelForgeGuidedSetupAuditPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$GenerationManifestHash)
    if ($GenerationManifestHash -cnotmatch '^[0-9a-f]{64}$') { throw 'FAIL_CLOSED: audit key is not a hash.' }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    return [pscustomobject][ordered]@{ StateRoot = $paths.StateRoot; Path = Join-Path (Join-Path $paths.StateRoot 'guided-setup-audit') "acceptance-$GenerationManifestHash.json" }
}

function Get-ChannelForgeGuidedSetupAuditHash {
    param([Parameter(Mandatory)]$Record)
    $projection = [ordered]@{}
    foreach ($property in @($Record.PSObject.Properties)) { if ($property.Name -cne 'RecordHash') { $projection[$property.Name] = $property.Value } }
    return Get-ChannelForgeDomainHash -Domain 'guided-setup-audit/v1' -InputObject $projection
}

function ConvertTo-ChannelForgeGuidedSetupAuditSource {
    param([AllowNull()][object[]]$Source)
    return @(@($Source) | Where-Object { $null -ne $_ } | ForEach-Object {
        [ordered]@{ SourceId = [string]$_.SourceId; SourceKind = [string]$_.SourceKind; Priority = [int]$_.Priority; ContentHash = [string]$_.ContentHash; ByteLength = [int]$_.ByteLength }
    })
}

function New-ChannelForgeGuidedSetupAuditRecord {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)]$Accepted,
        [AllowNull()]$Enrollment,
        [Parameter(Mandatory)][ValidateSet(1, 2)][int]$RequestSchemaVersion
    )
    $isV2 = [string]$Session.Version -ceq 'guided-setup/review/v2'
    $set = if ($isV2) { $Session.SourceSet } else { $null }
    $orNull = { param($Value) if ([string]::IsNullOrWhiteSpace([string]$Value)) { $null } else { [string]$Value } }
    $record = [ordered]@{
        Version = $script:ChannelForgeGuidedSetupAuditVersion
        ProposalId = [string]$Session.ProposalId
        SessionVersion = [string]$Session.Version
        SessionHash = [string]$Session.SessionHash
        CandidateManifestHash = [string]$Session.CandidateManifestHash
        BuildIdentity = [string]$Session.BuildIdentity
        CandidateContractVersion = if ($isV2) { 'blocker-2-contract/v7' } else { 'blocker-2-contract/v8' }
        SourceSetVersion = if ($isV2) { [string]$Session.SourceSetVersion } else { $null }
        Playlists = @(ConvertTo-ChannelForgeGuidedSetupAuditSource -Source $set.Playlists)
        Guides = @(ConvertTo-ChannelForgeGuidedSetupAuditSource -Source $set.Guides)
        Bindings = @(@($set.Bindings) | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{ GuideId = [string]$_.GuideId; PlaylistIds = @(@($_.PlaylistIds) | ForEach-Object { [string]$_ }); AppliesToAll = [bool]$_.AppliesToAll; ExplicitlyUnbound = [bool]$_.ExplicitlyUnbound; Revision = [int]$_.Revision; Enabled = [bool]$_.Enabled }
        })
        Outcome = [ordered]@{
            ChannelCount = [int]$Session.ChannelCount; ExactGuideMatchCount = [int]$Session.ExactGuideMatchCount; AmbiguityCount = [int]$Session.AmbiguityCount
            UnmatchedPlaylistCount = [int]$Session.UnmatchedPlaylistCount; GuideOnlyCount = [int]$Session.GuideOnlyCount; GuideCount = [int]$Session.GuideCount
            BoundGuideCount = [int]$Session.BoundGuideCount; UnboundGuideCount = [int]$Session.UnboundGuideCount; GuideStatus = [string]$Session.GuideStatus
            CanAccept = [bool]$Session.CanAccept; BlockingReasons = @(@($Session.BlockingReasons) | ForEach-Object { [string]$_ })
        }
        Acknowledgement = [ordered]@{ Explicit = $true; RequestSchemaVersion = $RequestSchemaVersion }
        AcceptedAtUtc = [string]$Accepted.AcceptedState.AcceptedAtUtc
        Prior = [ordered]@{ GenerationManifestHash = (& $orNull $Session.ParentGenerationManifestHash); AcceptedStateHash = (& $orNull $Session.ParentAcceptedStateHash); OutputManifestHash = (& $orNull $Session.ParentOutputManifestHash) }
        Result = [ordered]@{ GenerationManifestHash = [string]$Accepted.GenerationManifest.GenerationManifestHash; AcceptedStateHash = [string]$Accepted.AcceptedState.AcceptedStateHash; OutputManifestHash = [string]$Accepted.AcceptedOutputManifest.OutputManifestHash; DecisionManifestHash = [string]$Accepted.DecisionManifest.DecisionManifestHash }
        Enrollment = [ordered]@{ Status = if ($null -eq $Enrollment) { 'REPAIR_REQUIRED' } else { 'SAVED' }; EnrollmentHash = if ($null -eq $Enrollment) { $null } else { [string]$Enrollment.EnrollmentHash } }
    }
    $record.RecordHash = Get-ChannelForgeGuidedSetupAuditHash -Record ([pscustomobject]$record)
    return [pscustomobject]$record
}

function Write-ChannelForgeGuidedSetupAuditRecord {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Record)
    $target = Get-ChannelForgeGuidedSetupAuditPath -RepositoryRoot $RepositoryRoot -GenerationManifestHash ([string]$Record.Result.GenerationManifestHash)
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $target.StateRoot -Create | Out-Null
    Assert-ChannelForgeSourceEnrollmentDirectory -Path (Split-Path -Parent $target.Path) -Create | Out-Null
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path $target.Path -Value $Record -AllowedRoot $target.StateRoot -NoReplace
}

function Test-ChannelForgeGuidedSetupAuditAgainstGeneration {
    param([Parameter(Mandatory)]$Record,[AllowNull()]$Snapshot)
    if ($null -eq $Snapshot) { return $false }
    $result = $Record.Result; $prior = $Record.Prior
    return ([string]$result.GenerationManifestHash -ceq [string]$Snapshot.Manifest.Object.GenerationManifestHash) -and
        ([string]$result.AcceptedStateHash -ceq [string]$Snapshot.State.Object.AcceptedStateHash) -and
        ([string]$result.OutputManifestHash -ceq [string]$Snapshot.Output.Object.OutputManifestHash) -and
        ([string]$result.DecisionManifestHash -ceq [string]$Snapshot.Decision.Object.DecisionManifestHash) -and
        ([string]$prior.AcceptedStateHash -ceq [string]$Snapshot.State.Object.PreviousStateHash) -and
        ([string]$prior.OutputManifestHash -ceq [string]$Snapshot.Manifest.Object.PreviousOutputManifestHash)
}

function Read-ChannelForgeGuidedSetupAuditRecord {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$GenerationManifestHash,[AllowNull()]$Snapshot)
    $target = Get-ChannelForgeGuidedSetupAuditPath -RepositoryRoot $RepositoryRoot -GenerationManifestHash $GenerationManifestHash
    if (-not [System.IO.File]::Exists($target.Path)) { return [pscustomobject][ordered]@{ Status = 'AUDIT_MISSING'; Record = $null } }
    try {
        Assert-ChannelForgeSourceEnrollmentPath -Path $target.Path -AllowedRoot $target.StateRoot | Out-Null
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $text = $utf8.GetString([System.IO.File]::ReadAllBytes($target.Path))
        $record = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop
        if ($utf8.GetString($utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $record))) -cne $text) { throw 'not canonical' }
        if ([string]$record.Version -cne $script:ChannelForgeGuidedSetupAuditVersion -or [string]$record.RecordHash -cne (Get-ChannelForgeGuidedSetupAuditHash -Record $record) -or [string]$record.Result.GenerationManifestHash -cne $GenerationManifestHash) { throw 'not authentic' }
    }
    catch { return [pscustomobject][ordered]@{ Status = 'AUDIT_INVALID'; Record = $null } }
    if ($PSBoundParameters.ContainsKey('Snapshot') -and -not (Test-ChannelForgeGuidedSetupAuditAgainstGeneration -Record $record -Snapshot $Snapshot)) { return [pscustomobject][ordered]@{ Status = 'AUDIT_MISMATCH'; Record = $record } }
    return [pscustomobject][ordered]@{ Status = 'AUDIT_OK'; Record = $record }
}
