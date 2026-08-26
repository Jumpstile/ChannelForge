function ConvertTo-ChannelForgeCandidateManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$RawM3UOccurrences,

        [AllowEmptyCollection()]
        [object[]]$M3UIdentityCollisions = @(),

        [AllowEmptyCollection()]
        [object[]]$RawXmltvOccurrences = @(),

        [AllowNull()]
        [object]$IdentityBindingResult,

        [AllowNull()]
        [byte[]]$M3UBytes,

        [AllowNull()]
        [byte[]]$XMLTVBytes,

        [AllowEmptyCollection()]
        [string[]]$SelectedSourceIds = @()
    )

    function Get-SafeCandidateText {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return '' }
        $text = [string]$Value
        if ($text -match '(?i)(https?://|ftp://|file://|[a-z]:[\\/]|^\\\\|ACCOUNT_ID|API_TOKEN|PASSWORD|TOKEN|SECRET)') {
            return '[redacted]'
        }
        return $text
    }

    function Get-StreamFingerprint {
        param([AllowNull()][object]$Channel)
        return Get-ChannelForgeDomainHash -Domain 'stream-fingerprint/v2' -InputObject ([ordered]@{
                Version   = 'blocker-2-contract/v1'
                StreamUrl = if ($null -eq $Channel) { '' } else { [string]$Channel.Url }
            })
    }

    function Get-PresentationFingerprint {
        param([Parameter(Mandatory)][object]$Channel)
        return Get-ChannelForgeDomainHash -Domain 'safe-tvg-name-fingerprint/v2' -InputObject ([ordered]@{
                Version       = 'blocker-2-contract/v1'
                TvgName       = [string]$Channel.TvgName
                DisplayName   = [string]$Channel.DisplayName
                GroupTitle    = [string]$Channel.Group
                Logo          = [string]$Channel.Logo
                ChannelNumber = $Channel.AssignedNumber
            })
    }
    function Get-PropertyValue {
        param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Default = $null)
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
            return $Object.PSObject.Properties[$Name].Value
        }
        return $Default
    }

    function Get-RawIdPresence {
        param([AllowNull()][object]$Occurrence, [Parameter(Mandatory)][string]$PresenceName, [Parameter(Mandatory)][string]$ValueName)
        $value = Get-PropertyValue $Occurrence $ValueName $null
        $presence = Get-PropertyValue $Occurrence $PresenceName $null
        if ($null -eq $presence) { $presence = if ($null -eq $value) { 'Missing' } else { 'Present' } }
        return [pscustomobject][ordered]@{
            Presence = [string]$presence
            Value = if ([string]$presence -eq 'Missing') { $null } else { $value }
        }
    }

    function New-BindingRecord {
        param(
            [Parameter(Mandatory)][string]$BindingKind,
            [AllowNull()][string]$EntryId,
            [AllowNull()][string]$BindingKey,
            [Parameter(Mandatory)][string]$M3UPresence,
            [AllowNull()][object]$M3UValue,
            [Parameter(Mandatory)][string]$XmlPresence,
            [AllowNull()][object]$XmlValue,
            [AllowEmptyCollection()][object[]]$CandidateOrdinals = @(),
            [Parameter(Mandatory)][string]$Status,
            [Parameter(Mandatory)][string]$ReasonCode,
            [AllowNull()][object]$CollisionEvidence
        )
        $recordWithoutIds = [ordered]@{
            Version = 'blocker-2-contract/v1'
            BindingKind = $BindingKind
            EntryId = $EntryId
            BindingKey = $BindingKey
            M3URawIdPresence = $M3UPresence
            M3URawId = $M3UValue
            XMLTVIdPresence = $XmlPresence
            XMLTVId = $XmlValue
            CandidateChannelOccurrenceOrdinals = @($CandidateOrdinals | Sort-Object)
            Status = $Status
            ReasonCode = $ReasonCode
            CollisionEvidence = $CollisionEvidence
        }
        $bindingId = Get-ChannelForgeDomainHash -Domain 'binding-record/v2' -InputObject $recordWithoutIds
        $record = [ordered]@{
            Version = 'blocker-2-contract/v1'
            BindingId = $bindingId
            BindingKind = $BindingKind
            EntryId = $EntryId
            BindingKey = $BindingKey
            M3URawIdPresence = $M3UPresence
            M3URawId = $M3UValue
            XMLTVIdPresence = $XmlPresence
            XMLTVId = $XmlValue
            CandidateChannelOccurrenceOrdinals = @($CandidateOrdinals | Sort-Object)
            Status = $Status
            ReasonCode = $ReasonCode
            CollisionEvidence = $CollisionEvidence
        }
        $record.BindingRecordDigest = Get-ChannelForgeDomainHash -Domain 'binding-record/v2' -InputObject $record
        return [pscustomobject]$record
    }

    function Get-CollisionEvidence {
        param([AllowNull()][object]$Collision)
        if ($null -eq $Collision) { return @() }
        $digests = [System.Collections.Generic.List[string]]::new()
        foreach ($channel in @(Get-PropertyValue $Collision 'Channels' @())) {
            $match = @($orderedM3U | Where-Object { [object]::ReferenceEquals($_.Channel, $channel) }) | Select-Object -First 1
            if ($null -ne $match) { [void]$digests.Add([string]$match.RawM3UOccurrenceDigest) }
        }
        return @($digests | Sort-Object -Unique)
    }

    $orderedM3U = @($RawM3UOccurrences | Sort-Object @{ Expression = { [string]$_.EntryId } })
    $entries = @($orderedM3U | Where-Object { $null -ne $_.Channel -and -not $_.Channel.IsDuplicate } | ForEach-Object {
            [ordered]@{
                EntryId             = [string]$_.EntryId
                LogicalSourceId     = [string]$_.LogicalSourceId
                SourceLocalOrdinal  = [int]$_.SourceLocalOrdinal
                HistoryKey          = $_.HistoryKey
                HistoryIdentityStatus = if ($null -eq $_.HistoryKey) { 'MissingId' } else { 'StableUnique' }
                RawTvgIdPresence    = [string]$_.RawTvgIdPresence
                RawTvgId            = if ($_.RawTvgIdPresence -eq 'Present') { [string]$_.RawTvgId } else { $null }
                TvgName             = Get-SafeCandidateText $_.TvgName
                DisplayName         = Get-SafeCandidateText $_.DisplayName
                GroupTitle          = Get-SafeCandidateText $_.GroupTitle
                Logo                = Get-SafeCandidateText $_.Logo
                ChannelNumber       = $_.ChannelNumber
                StreamFingerprint   = Get-ChannelForgeDomainHash -Domain 'stream-fingerprint/v2' -InputObject ([ordered]@{
                    Version = 'stream-fingerprint-v2'
                    StreamUrl = [string]$_.StreamUrl
                })
                PresentationFingerprint = Get-ChannelForgeDomainHash -Domain 'safe-tvg-name-fingerprint/v2' -InputObject ([ordered]@{
                    Version = 'safe-tvg-name-fingerprint-v2'
                    TvgName = [string]$_.TvgName
                    DisplayName = [string]$_.DisplayName
                    GroupTitle = [string]$_.GroupTitle
                    Logo = [string]$_.Logo
                    ChannelNumber = $_.ChannelNumber
                })
                EntryOutputSlice    = [ordered]@{
                    RelativePath = 'merged.m3u'
                    ByteOffset = $null
                    ByteLength = $null
                    EntryContentHash = $null
                }
            }
        })

    $rawM3UEvidence = @($orderedM3U | ForEach-Object {
            [ordered]@{
                EntryId                = [string]$_.EntryId
                LogicalSourceId        = [string]$_.LogicalSourceId
                SourceLocalOrdinal     = [int]$_.SourceLocalOrdinal
                RawTvgIdPresence       = [string]$_.RawTvgIdPresence
                RawTvgId               = if ($_.RawTvgIdPresence -eq 'Present') { [string]$_.RawTvgId } else { $null }
                RawM3UOccurrenceDigest = [string]$_.RawM3UOccurrenceDigest
            }
        })

    $collisionProjection = @($M3UIdentityCollisions | Where-Object { $null -ne $_ } | ForEach-Object {
            $collision = $_
            $members = @($collision.Channels | ForEach-Object {
                    $channel = $_
                    @($orderedM3U | Where-Object { [object]::ReferenceEquals($_.Channel, $channel) })
                })
            $digests = @($members | ForEach-Object { [string]$_.RawM3UOccurrenceDigest } | Where-Object { $_ } | Sort-Object -Unique)
            $entryIds = @($members | ForEach-Object { [string]$_.EntryId } | Where-Object { $_ } | Sort-Object -Unique)
            $missingCount = @($members | Where-Object { [string]$_.RawTvgIdPresence -eq 'Missing' }).Count
            $presentCount = @($members | Where-Object { [string]$_.RawTvgIdPresence -eq 'Present' }).Count
            $kind = if ($presentCount -eq 0) { 'MissingOnly' }
                    elseif ($missingCount -eq 0) { 'PresentCollision' }
                    else { 'MixedMissingAndPresent' }
            $base = [ordered]@{
                Version = 'blocker-2-contract/v1'
                HistoryKey = if ($null -eq $collision.IdentityKey) { $null } else { [string]$collision.IdentityKey }
                CollisionKind = $kind
                RawIdentityDigests = @($digests)
                EntryIds = @($entryIds)
                MissingIdentityCount = [int]$missingCount
                IdentityPopulation = [int]$members.Count
            }
            $base.CollisionEvidenceDigest = Get-ChannelForgeDomainHash -Domain 'collision-evidence/v2' -InputObject $base
            [pscustomobject]$base
        })

    $xmltvChannels = @($RawXmltvOccurrences | Where-Object {
            $null -ne $_.PSObject.Properties['RawChannelIdPresence']
        })
    $xmltvProgrammes = @($RawXmltvOccurrences | Where-Object {
            $null -ne $_.PSObject.Properties['RawProgrammeChannelIdPresence']
        })
    $guideOccurrences = @(
        $xmltvChannels |
            Group-Object {
                "$([string]$_.LogicalSourceId)`u{001f}$([string]$_.RawChannelIdPresence)`u{001f}$([string]$_.RawChannelId)"
            } |
            ForEach-Object {
                $members = @($_.Group | Sort-Object @{ Expression = { [int]$_.StructuralOccurrenceOrdinal } }, @{ Expression = { [string]$_.RawXMLTVOccurrenceDigest } })
                $first = $members[0]
                $presence = [string]$first.RawChannelIdPresence
                $digests = @($members | ForEach-Object { [string]$_.RawXMLTVOccurrenceDigest } | Sort-Object -Unique)
                $ordinals = @($members | ForEach-Object { [int]$_.StructuralOccurrenceOrdinal } | Sort-Object -Unique)
                [ordered]@{
                    Presence = $presence
                    Value = if ($presence -eq 'Missing') { $null } else { [string]$first.RawChannelId }
                    OccurrenceCount = $members.Count
                    MissingIdentityCount = @($members | Where-Object { [string]$_.RawChannelIdPresence -eq 'Missing' }).Count
                    OccurrenceDigests = $digests
                    OccurrenceOrdinals = $ordinals
                }
            } |
            Sort-Object @{ Expression = { [string]$_.Presence } }, @{ Expression = { [string]$_.Value } }, @{ Expression = { [string]$_.OccurrenceDigests -join ',' } }
    )

    $bindingProjection = [System.Collections.Generic.List[object]]::new()
    $matchedXmltvKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $bindingCandidates = @(
        @($IdentityBindingResult.ExactBindings) +
        @($IdentityBindingResult.UnboundChannels) +
        @($IdentityBindingResult.ReviewNeeded)
    )
    foreach ($occurrence in @($orderedM3U)) {
        if ($null -eq $occurrence.Channel) { continue }
        $binding = @($bindingCandidates | Where-Object {
                $null -ne $_.PSObject.Properties['M3UChannel'] -and
                [object]::ReferenceEquals($_.M3UChannel, $occurrence.Channel)
            }) | Select-Object -First 1
        $xmlId = if ($null -ne $binding -and $null -ne $binding.PSObject.Properties['XmltvChannelId']) { [string]$binding.XmltvChannelId } else { $null }
        $xmlSource = if ($null -ne $binding -and $null -ne $binding.PSObject.Properties['XmltvSourceId']) { [string]$binding.XmltvSourceId } else { $null }
        $xmlMatches = @($xmltvChannels | Where-Object {
                [string]$_.RawChannelIdPresence -eq 'Present' -and
                $null -ne $xmlId -and [string]$_.RawChannelId -ceq $xmlId -and
                [string]$_.LogicalSourceId -eq $xmlSource
            })
        $candidateOrdinals = @($xmlMatches | ForEach-Object {
                [void]$matchedXmltvKeys.Add("$($_.LogicalSourceId)`u{001f}$($_.StructuralOccurrenceOrdinal)")
                [int]$_.StructuralOccurrenceOrdinal
            })
        $xmlPresence = if ($xmlMatches.Count -gt 0) { 'Present' } else { 'Missing' }
        $xmlValue = if ($xmlMatches.Count -gt 0) { [string]$xmlMatches[0].RawChannelId } else { $null }
        $bindingKey = if ($xmlMatches.Count -gt 0) {
            Get-ChannelForgeDomainHash -Domain 'binding-key/v2' -InputObject ([ordered]@{
                LogicalSourceId = [string]$xmlMatches[0].LogicalSourceId
                StructuralOccurrenceOrdinal = [int]$xmlMatches[0].StructuralOccurrenceOrdinal
                RawChannelIdPresence = [string]$xmlMatches[0].RawChannelIdPresence
                RawChannelId = $xmlMatches[0].RawChannelId
            })
        } else { $null }
        $collision = if ($null -ne $binding -and $null -ne $binding.PSObject.Properties['M3UIdentityCollision']) {
            Get-CollisionEvidence $binding.M3UIdentityCollision
        } else { @() }
        $status = if ($null -ne $binding -and $null -ne $binding.Status) { [string]$binding.Status } else { 'Unbound' }
        $reason = if ($null -ne $binding -and $null -ne $binding.Reason) { [string]$binding.Reason } else { 'TvgIdNotFoundInXmltv' }
        [void]$bindingProjection.Add((New-BindingRecord `
                -BindingKind 'M3U' `
                -EntryId ([string]$occurrence.EntryId) `
                -BindingKey $bindingKey `
                -M3UPresence ([string]$occurrence.RawTvgIdPresence) `
                -M3UValue $occurrence.RawTvgId `
                -XmlPresence $xmlPresence `
                -XmlValue $xmlValue `
                -CandidateOrdinals $candidateOrdinals `
                -Status $status `
                -ReasonCode $reason `
                -CollisionEvidence $collision))
    }
    foreach ($occurrence in @($xmltvChannels | Sort-Object @{ Expression = { [string]$_.LogicalSourceId } }, @{ Expression = { [int]$_.StructuralOccurrenceOrdinal } })) {
        $key = "$($occurrence.LogicalSourceId)`u{001f}$($occurrence.StructuralOccurrenceOrdinal)"
        if ($matchedXmltvKeys.Contains($key)) { continue }
        $bindingKey = Get-ChannelForgeDomainHash -Domain 'binding-key/v2' -InputObject ([ordered]@{
                LogicalSourceId = [string]$occurrence.LogicalSourceId
                StructuralOccurrenceOrdinal = [int]$occurrence.StructuralOccurrenceOrdinal
                RawChannelIdPresence = [string]$occurrence.RawChannelIdPresence
                RawChannelId = $occurrence.RawChannelId
            })
        [void]$bindingProjection.Add((New-BindingRecord `
                -BindingKind 'XMLTVOnly' `
                -EntryId $null `
                -BindingKey $bindingKey `
                -M3UPresence 'Missing' `
                -M3UValue $null `
                -XmlPresence ([string]$occurrence.RawChannelIdPresence) `
                -XmlValue $occurrence.RawChannelId `
                -CandidateOrdinals @([int]$occurrence.StructuralOccurrenceOrdinal) `
                -Status 'OrphanedXmltv' `
                -ReasonCode 'NoM3UChannelWithTvgId' `
                -CollisionEvidence @()))
    }
    $bindingProjection = [System.Collections.Generic.List[object]]::new(
        [object[]]@($bindingProjection | Sort-Object `
            @{ Expression = { if ([string]::IsNullOrEmpty([string]$_.EntryId)) { 1 } else { 0 } } }, `
            @{ Expression = { [string]$_.EntryId } }, `
            @{ Expression = { [string]$_.BindingKey } }))

    $inputArtifacts = [ordered]@{
        M3U  = Get-ChannelForgeDomainHash -Domain 'input-m3u/v2' -InputObject $rawM3UEvidence
        XMLTV = Get-ChannelForgeDomainHash -Domain 'input-xmltv/v2' -InputObject @($RawXmltvOccurrences)
    }
    $sourceIds = @($SelectedSourceIds | Sort-Object -Unique)
    $buildInput = [ordered]@{
        ContractVersion       = 'blocker-2-contract/v1'
        IdentityRulesVersion  = 'lineup-history-v1'
        SelectedSourceIds     = $sourceIds
        InputArtifactHashes   = $inputArtifacts
        ParserVersion         = 'm3u-xmltv-parser-v1'
        SerializerVersion     = 'candidate-serializer-v1'
        GuideBindingVersion   = 'exact-ordinal-v1'
    }
    $buildIdentity = Get-ChannelForgeDomainHash -Domain 'candidate-manifest/v2' -InputObject $buildInput

    $artifactRecords = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $M3UBytes) {
        [void]$artifactRecords.Add([ordered]@{
                Role          = 'M3U'
                RelativePath  = 'merged.m3u'
                Status        = 'Generated'
                ByteLength    = $M3UBytes.Length
                ContentDomain = 'candidate-m3u/v2'
                ContentHash   = Get-ChannelForgeDomainHash -Domain 'candidate-m3u/v2' -Bytes $M3UBytes
            })
    }
    if ($null -ne $XMLTVBytes) {
        [void]$artifactRecords.Add([ordered]@{
                Role          = 'XMLTV'
                RelativePath  = 'merged.xml'
                Status        = 'Generated'
                ByteLength    = $XMLTVBytes.Length
                ContentDomain = 'candidate-xmltv/v2'
                ContentHash   = Get-ChannelForgeDomainHash -Domain 'candidate-xmltv/v2' -Bytes $XMLTVBytes
            })
    }

    $manifest = [ordered]@{
        Version               = 'blocker-2-contract/v1'
        ContractVersion       = 'blocker-2-contract/v1'
        BuildIdentity         = $buildIdentity
        IdentityRulesVersion  = 'lineup-history-v1'
        SelectedSources       = $sourceIds
        InputArtifactHashes   = $inputArtifacts
        Entries               = $entries
        M3UIdentityCollisions = $collisionProjection
        GuideOccurrences      = @($guideOccurrences)
        RawProgrammes         = @($xmltvProgrammes)
        BindingRecords        = @($bindingProjection.ToArray())
        ChangeRecords         = @()
        ReviewRecords         = @()
        ArtifactRecords       = @($artifactRecords.ToArray())
    }
    $manifestHash = Get-ChannelForgeDomainHash -Domain 'candidate-manifest/v2' -InputObject $manifest
    return [pscustomobject][ordered]@{
        Manifest             = [pscustomobject]$manifest
        CandidateManifestHash = $manifestHash
        BuildIdentity        = $buildIdentity
        BindingProjection    = @($bindingProjection.ToArray())
    }
}
