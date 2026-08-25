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

    $orderedM3U = @($RawM3UOccurrences | Sort-Object @{ Expression = { [string]$_.EntryId } })
    $entries = @($orderedM3U | Where-Object { $null -ne $_.Channel -and -not $_.Channel.IsDuplicate } | ForEach-Object {
            [ordered]@{
                EntryId             = [string]$_.EntryId
                LogicalSourceId     = [string]$_.LogicalSourceId
                SourceLocalOrdinal  = [int]$_.SourceLocalOrdinal
                HistoryKey          = $_.HistoryKey
                HistoryIdentityStatus = if ($null -eq $_.HistoryKey) { 'MissingId' } else { 'StableUnique' }
                RawTvgIdPresence    = [string]$_.RawTvgIdPresence
                RawTvgId            = if ($_.RawTvgIdPresence -eq 'Present') { Get-SafeCandidateText $_.RawTvgId } else { $null }
                TvgName             = Get-SafeCandidateText $_.Channel.TvgName
                DisplayName         = Get-SafeCandidateText $_.Channel.DisplayName
                GroupTitle          = Get-SafeCandidateText $_.Channel.Group
                Logo                = Get-SafeCandidateText $_.Channel.Logo
                ChannelNumber       = $_.Channel.AssignedNumber
                StreamFingerprint   = Get-StreamFingerprint -Channel $_.Channel
                PresentationFingerprint = Get-PresentationFingerprint -Channel $_.Channel
                EntryOutputSlice    = [ordered]@{
                    RelativePath   = 'merged.m3u'
                    ByteOffset     = $null
                    ByteLength     = $null
                    EntryContentHash = $null
                }
            }
        })

    $rawM3UEvidence = @($orderedM3U | ForEach-Object {
            [ordered]@{
                EntryId                 = [string]$_.EntryId
                LogicalSourceId         = [string]$_.LogicalSourceId
                SourceLocalOrdinal      = [int]$_.SourceLocalOrdinal
                RawTvgIdPresence        = [string]$_.RawTvgIdPresence
                RawTvgId                = if ($_.RawTvgIdPresence -eq 'Present') { Get-SafeCandidateText $_.RawTvgId } else { $null }
                RawM3UOccurrenceDigest  = [string]$_.RawM3UOccurrenceDigest
            }
        })

    $collisionProjection = @($M3UIdentityCollisions | Where-Object { $null -ne $_ } | ForEach-Object {
            $collision = $_
            $raw = @($collision.Channels | ForEach-Object {
                    $collisionChannel = $_
                    $match = $orderedM3U | Where-Object {
                        [object]::ReferenceEquals($_.Channel, $collisionChannel)
                    } | Select-Object -First 1
                    if ($null -ne $match) { [string]$match.RawM3UOccurrenceDigest }
                    else {
                        Get-ChannelForgeDomainHash -Domain 'raw-m3u-occurrence/v2' -InputObject ([ordered]@{
                            Version = 'blocker-2-contract/v1'
                            RawTvgIdPresence = if ($null -ne $collisionChannel.PSObject.Properties['RawTvgIdPresence']) { [string]$collisionChannel.RawTvgIdPresence } else { 'Missing' }
                            RawTvgId = if ($null -ne $collisionChannel.PSObject.Properties['RawTvgIdPresence'] -and [string]$collisionChannel.RawTvgIdPresence -eq 'Present') { [string]$collisionChannel.RawTvgId } else { $null }
                            DisplayName = [string]$collisionChannel.DisplayName
                            StreamUrl = [string]$collisionChannel.Url
                        })
                    }
                } | Sort-Object)
            [ordered]@{
                IdentityKey        = Get-SafeCandidateText $collision.IdentityKey
                RawIdentityDigests  = @($raw)
                CollisionKind       = if ($raw.Count -gt 1) { 'PresentCollision' } else { 'None' }
                IdentityPopulation  = $raw.Count
            }
        })

    $bindingProjection = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $IdentityBindingResult) {
        $bindingRecords = @($IdentityBindingResult.ExactBindings) +
            @($IdentityBindingResult.UnboundChannels) +
            @($IdentityBindingResult.ReviewNeeded) +
            @($IdentityBindingResult.OrphanedXmltvChannels)
        foreach ($bindingRecord in $bindingRecords) {
            if ($null -eq $bindingRecord) { continue }
            $record = [ordered]@{
                Status       = if ($null -ne $bindingRecord.Status) { [string]$bindingRecord.Status } else { '' }
                Reason       = if ($null -ne $bindingRecord.Reason) { [string]$bindingRecord.Reason } else { '' }
                TvgId        = if ($null -ne $bindingRecord.TvgId) { Get-SafeCandidateText $bindingRecord.TvgId } else { $null }
                XmltvChannelId = if ($null -ne $bindingRecord.XmltvChannelId) { Get-SafeCandidateText $bindingRecord.XmltvChannelId } else { $null }
                XmltvSourceId = if ($null -ne $bindingRecord.XmltvSourceId) { Get-SafeCandidateText $bindingRecord.XmltvSourceId } else { $null }
            }
            [void]$bindingProjection.Add([pscustomobject]$record)
        }
    }

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
        GuideOccurrences      = @($RawXmltvOccurrences)
        RawProgrammes         = @($RawXmltvOccurrences)
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
