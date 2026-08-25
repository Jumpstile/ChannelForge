function Get-ChannelForgeRawXmltvProjection {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Programme
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in @($Programme)) {
        if ($null -eq $value -or $value -isnot [Programme]) { continue }
        $evidence = $value.Evidence
        if ($null -eq $evidence -or $null -eq $evidence.PSObject.Properties['RawProgrammeOccurrences']) {
            $rawChannelId = if ($null -ne $value.PSObject.Properties['RawChannelId']) { [string]$value.RawChannelId } else { [string]$value.ChannelId }
            $raw = [ordered]@{
                Version                       = 'blocker-2-contract/v1'
                LogicalSourceId               = Get-ChannelForgeDomainHash -Domain 'logical-source-id/v2' -InputObject ([ordered]@{ Version = 'lineup-history-v1'; SourceId = [string]$value.SourceId })
                StructuralOccurrenceOrdinal  = 0
                RawProgrammeChannelIdPresence = if ([string]::IsNullOrEmpty($rawChannelId)) { 'Missing' } else { 'Present' }
                RawProgrammeChannelId        = if ([string]::IsNullOrEmpty($rawChannelId)) { $null } else { $rawChannelId }
                StartRaw                      = $value.Start.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                StopRaw                       = $value.End.ToUniversalTime().ToString('O', [Globalization.CultureInfo]::InvariantCulture)
                Title                         = [string]$value.Title
                Subtitle                      = [string]$value.Subtitle
                Description                   = [string]$value.Description
                Categories                    = @($value.Categories)
                EpisodeNumber                 = [string]$value.EpisodeNumber
                IsNew                         = [bool]$value.IsNew
                IsLive                        = [bool]$value.IsLive
                IsPremiere                    = [bool]$value.IsPremiere
            }
            $digest = Get-ChannelForgeDomainHash -Domain 'raw-xmltv-occurrence/v2' -InputObject $raw
            if ($seen.Add($digest)) {
                $records.Add([pscustomobject][ordered]@{ Projection = $raw; Digest = $digest })
            }
            continue
        }

        foreach ($occurrence in @($evidence.RawProgrammeOccurrences)) {
            $raw = [ordered]@{}
            foreach ($property in @($occurrence.PSObject.Properties)) {
                if ($property.Name -notin @('RawProgrammeDigest', 'StructuralOccurrenceOrdinal')) {
                    $raw[$property.Name] = $property.Value
                }
            }
            $raw.Version = 'blocker-2-contract/v1'
            $digest = Get-ChannelForgeDomainHash -Domain 'raw-xmltv-occurrence/v2' -InputObject $raw
            if ($seen.Add($digest)) {
                $records.Add([pscustomobject][ordered]@{ Projection = $raw; Digest = $digest })
            }
        }
    }

    $ordered = @($records | Sort-Object @{ Expression = { $_.Digest } }, @{ Expression = { [string]$_.Projection.RawProgrammeChannelId } }, @{ Expression = { [string]$_.Projection.StartRaw } }, @{ Expression = { [string]$_.Projection.StopRaw } })
    for ($index = 0; $index -lt $ordered.Count; $index++) {
        $ordered[$index].Projection.StructuralOccurrenceOrdinal = $index
    }
    return @($ordered | ForEach-Object {
            $projection = [ordered]@{}
            foreach ($property in @($_.Projection.PSObject.Properties)) { $projection[$property.Name] = $property.Value }
            $projection.RawProgrammeDigest = Get-ChannelForgeDomainHash -Domain 'raw-xmltv-occurrence/v2' -InputObject $projection
            [pscustomobject]$projection
        })
}
