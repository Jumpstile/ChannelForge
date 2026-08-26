function Get-ChannelForgeRawXmltvProjection {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Programme
    )

    function Get-PropertyValue {
        param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Default = $null)
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
            return $Object.PSObject.Properties[$Name].Value
        }
        return $Default
    }
    function Get-LogicalSourceId {
        param([AllowNull()][object]$Occurrence, [AllowNull()][object]$Evidence)
        $value = Get-PropertyValue $Occurrence 'LogicalSourceId'
        if ($null -ne $value -and -not [string]::IsNullOrEmpty([string]$value)) { return [string]$value }
        $sourceId = [string](Get-PropertyValue $Evidence 'SourceId' '')
        if ([string]::IsNullOrEmpty($sourceId)) { $sourceId = [string](Get-PropertyValue $Occurrence 'SourceId' '') }
        return Get-ChannelForgeDomainHash -Domain 'logical-source-id/v2' -InputObject ([ordered]@{
                Version = 'lineup-history-v1'
                SourceId = $sourceId
            })
    }
    function Get-ArrayValue {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return @() }
        return @($Value)
    }
    function Get-Digest {
        param([Parameter(Mandatory)][object]$Projection, [Parameter(Mandatory)][string]$Domain)
        $input = [ordered]@{}
        foreach ($property in @($Projection.PSObject.Properties)) {
            if ($property.Name -notin @('StructuralOccurrenceOrdinal', 'RawXMLTVOccurrenceDigest', 'RawProgrammeDigest')) {
                $input[$property.Name] = $property.Value
            }
        }
        return Get-ChannelForgeDomainHash -Domain $Domain -InputObject $input
    }
    function Get-ChannelSortKey {
        param([Parameter(Mandatory)][object]$Projection)
        $presenceRank = if ([string]$Projection.RawChannelIdPresence -eq 'Missing') { '0' } else { '1' }
        return @(
            $presenceRank
            [string]$Projection.RawChannelId
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.DisplayNameNodes))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.IconNodes))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.RawChannelExtensions))
            [string]$Projection.RawXMLTVOccurrenceDigest
        ) -join [char]31
    }
    function Get-ProgrammeSortKey {
        param([Parameter(Mandatory)][object]$Projection)
        $presenceRank = if ([string]$Projection.RawProgrammeChannelIdPresence -eq 'Missing') { '0' } else { '1' }
        return @(
            $presenceRank
            [string]$Projection.RawProgrammeChannelId
            [string]$Projection.StartRaw
            [string]$Projection.StopRaw
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.TitleNodes))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.SubTitleNodes))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.DescNodes))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.CategoryNodes))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.EpisodeNumbers))
            (ConvertTo-ChannelForgeCanonicalJson -InputObject @($Projection.RawProgrammeExtensions))
            [string]$Projection.RawProgrammeDigest
        ) -join [char]31
    }

    $channelRecords = [System.Collections.Generic.List[object]]::new()
    $programmeRecords = [System.Collections.Generic.List[object]]::new()
    $seenEvidence = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in @($Programme)) {
        if ($null -eq $value -or $value -isnot [Programme]) { continue }
        $evidence = $value.Evidence
        $evidenceKey = if ($null -eq $evidence) {
            "fallback`u{001f}$([string]$value.SourceId)"
        }
        else {
            @(
                [string](Get-PropertyValue $evidence 'SourceId' '')
                [string](Get-PropertyValue $evidence 'SourcePath' '')
                [string](Get-PropertyValue $evidence 'SourceReference' '')
                [string](Get-PropertyValue $evidence 'DocumentBytes' '')
            ) -join [char]31
        }
        if ($null -ne $evidence -and $seenEvidence.Add($evidenceKey)) {
            foreach ($occurrence in @(Get-PropertyValue $evidence 'RawChannelOccurrences' @())) {
                if ($null -eq $occurrence) { continue }
                $rawId = Get-PropertyValue $occurrence 'RawChannelId'
                $presence = [string](Get-PropertyValue $occurrence 'RawChannelIdPresence' $(if ($null -eq $rawId) { 'Missing' } else { 'Present' }))
                if ($presence -eq 'Missing') { $rawId = $null }
                $projection = [pscustomobject][ordered]@{
                    Version = 'blocker-2-contract/v6'
                    LogicalSourceId = Get-LogicalSourceId $occurrence $evidence
                    StructuralOccurrenceOrdinal = 0
                    RawChannelIdPresence = $presence
                    RawChannelId = $rawId
                    DisplayNameNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'DisplayNameNodes' @())
                    IconNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'IconNodes' @())
                    RawChannelExtensions = Get-ArrayValue (Get-PropertyValue $occurrence 'RawChannelExtensions' @())
                }
                [void]$channelRecords.Add([pscustomobject][ordered]@{
                        Projection = $projection
                        Digest = Get-Digest $projection 'raw-xmltv-occurrence/v2'
                    })
                $projection | Add-Member -NotePropertyName RawXMLTVOccurrenceDigest -NotePropertyValue $channelRecords[$channelRecords.Count - 1].Digest -Force
            }
            foreach ($occurrence in @(Get-PropertyValue $evidence 'RawProgrammeOccurrences' @())) {
                if ($null -eq $occurrence) { continue }
                $rawId = Get-PropertyValue $occurrence 'RawProgrammeChannelId'
                $presence = [string](Get-PropertyValue $occurrence 'RawProgrammeChannelIdPresence' $(if ($null -eq $rawId) { 'Missing' } else { 'Present' }))
                if ($presence -eq 'Missing') { $rawId = $null }
                $projection = [pscustomobject][ordered]@{
                    Version = 'blocker-2-contract/v6'
                    LogicalSourceId = Get-LogicalSourceId $occurrence $evidence
                    StructuralOccurrenceOrdinal = 0
                    RawProgrammeChannelIdPresence = $presence
                    RawProgrammeChannelId = $rawId
                    StartRaw = [string](Get-PropertyValue $occurrence 'StartRaw' '')
                    StopRaw = [string](Get-PropertyValue $occurrence 'StopRaw' '')
                    TitleNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'TitleNodes' @())
                    SubTitleNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'SubTitleNodes' @())
                    DescNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'DescNodes' @())
                    CategoryNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'CategoryNodes' @())
                    EpisodeNumbers = Get-ArrayValue (Get-PropertyValue $occurrence 'EpisodeNumbers' @())
                    Rating = Get-PropertyValue $occurrence 'Rating' $null
                    StarRating = Get-PropertyValue $occurrence 'StarRating' $null
                    PreviouslyShown = Get-PropertyValue $occurrence 'PreviouslyShown' $false
                    Premiere = Get-PropertyValue $occurrence 'Premiere' (Get-PropertyValue $occurrence 'IsPremiere' $false)
                    LastChance = Get-PropertyValue $occurrence 'LastChance' $false
                    Credits = Get-ArrayValue (Get-PropertyValue $occurrence 'Credits' @())
                    Date = Get-PropertyValue $occurrence 'Date' $null
                    IconNodes = Get-ArrayValue (Get-PropertyValue $occurrence 'IconNodes' @())
                    RawProgrammeExtensions = Get-ArrayValue (Get-PropertyValue $occurrence 'RawProgrammeExtensions' @())
                }
                $record = [pscustomobject][ordered]@{
                    Projection = $projection
                    Digest = Get-Digest $projection 'raw-programme/v2'
                }
                [void]$programmeRecords.Add($record)
                $projection | Add-Member -NotePropertyName RawProgrammeDigest -NotePropertyValue $record.Digest -Force
            }
        }
        if ($null -eq $evidence) {
            $rawId = Get-PropertyValue $value 'RawChannelId' $value.ChannelId
            $projection = [pscustomobject][ordered]@{
            Version = 'blocker-2-contract/v6'
                LogicalSourceId = Get-LogicalSourceId $value $null
                StructuralOccurrenceOrdinal = 0
                RawProgrammeChannelIdPresence = if ($null -eq $rawId) { 'Missing' } else { 'Present' }
                RawProgrammeChannelId = if ($null -eq $rawId) { $null } else { [string]$rawId }
                StartRaw = $value.Start.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                StopRaw = $value.End.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                TitleNodes = @([string]$value.Title)
                SubTitleNodes = @([string]$value.Subtitle)
                DescNodes = @([string]$value.Description)
                CategoryNodes = @($value.Categories)
                EpisodeNumbers = @([string]$value.EpisodeNumber)
                Rating = $null
                StarRating = $null
                PreviouslyShown = $false
                Premiere = [bool]$value.IsPremiere
                LastChance = $false
                Credits = @()
                Date = $null
                IconNodes = @()
                RawProgrammeExtensions = @()
            }
            $record = [pscustomobject][ordered]@{
                    Projection = $projection
                    Digest = Get-Digest $projection 'raw-programme/v2'
                }
            [void]$programmeRecords.Add($record)
            $projection | Add-Member -NotePropertyName RawProgrammeDigest -NotePropertyValue $record.Digest -Force
        }
    }

    foreach ($group in @($channelRecords | Group-Object { [string]$_.Projection.LogicalSourceId })) {
        $ordered = @($group.Group | Sort-Object @{ Expression = { Get-ChannelSortKey $_.Projection } })
        for ($index = 0; $index -lt $ordered.Count; $index++) {
            $ordered[$index].Projection.StructuralOccurrenceOrdinal = $index
            $ordered[$index].Projection | Add-Member -NotePropertyName RawXMLTVOccurrenceDigest -NotePropertyValue $ordered[$index].Digest -Force
        }
    }
    foreach ($group in @($programmeRecords | Group-Object { [string]$_.Projection.LogicalSourceId })) {
        $ordered = @($group.Group | Sort-Object @{ Expression = { Get-ProgrammeSortKey $_.Projection } })
        for ($index = 0; $index -lt $ordered.Count; $index++) {
            $ordered[$index].Projection.StructuralOccurrenceOrdinal = $index
            $ordered[$index].Projection | Add-Member -NotePropertyName RawProgrammeDigest -NotePropertyValue $ordered[$index].Digest -Force
        }
    }

    $output = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($channelRecords | Sort-Object `
                @{ Expression = { [string]$_.Projection.LogicalSourceId } }, `
                @{ Expression = { [int]$_.Projection.StructuralOccurrenceOrdinal } })) {
        $projection = [ordered]@{}
        foreach ($property in @($record.Projection.PSObject.Properties)) { $projection[$property.Name] = $property.Value }
        $projection.RawXMLTVOccurrenceDigest = [string]$record.Digest
        [void]$output.Add([pscustomobject]$projection)
    }
    foreach ($record in @($programmeRecords | Sort-Object `
                @{ Expression = { [string]$_.Projection.LogicalSourceId } }, `
                @{ Expression = { [int]$_.Projection.StructuralOccurrenceOrdinal } })) {
        $projection = [ordered]@{}
        foreach ($property in @($record.Projection.PSObject.Properties)) { $projection[$property.Name] = $property.Value }
        $projection.RawProgrammeDigest = [string]$record.Digest
        [void]$output.Add([pscustomobject]$projection)
    }
    return @($output.ToArray())
}
