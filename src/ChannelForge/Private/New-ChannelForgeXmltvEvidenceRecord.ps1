function New-ChannelForgeXmltvEvidenceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [AllowEmptyString()]
        [string]$SourcePath = '',

        [ValidateSet('none', 'gzip', 'zip')]
        [string]$Compression = 'none',

        [ValidateSet('local', 'remote')]
        [string]$SourceKind = 'local',

        [AllowEmptyString()]
        [string]$SourceReference = '',

        [int]$TransportContractVersion = 0,

        [int]$HttpStatusCode = 0,

        [AllowEmptyString()]
        [string]$ContentType = '',

        [AllowEmptyCollection()]
        [string[]]$ContentEncodings = @(),

        [AllowNull()]
        [Nullable[long]]$RawContentLength,

        [Parameter(Mandatory)]
        [int]$ProgrammeCount,

        [Parameter(Mandatory)]
        [int]$ChannelCount,

        [AllowEmptyCollection()]
        [object[]]$ChannelIdOccurrences = @(),

        [Parameter(Mandatory)]
        [long]$DocumentBytes
    )

    if ([string]::IsNullOrWhiteSpace($SourceId)) {
        throw 'XMLTV evidence SourceId cannot be empty.'
    }

    if ($ProgrammeCount -lt 0 -or $ChannelCount -lt 0 -or $DocumentBytes -lt 0) {
        throw 'XMLTV evidence counts and byte totals cannot be negative.'
    }

    $orderedChannelIdOccurrences = [System.Collections.Generic.List[object]]::new()
    $seenChannelIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($occurrence in @($ChannelIdOccurrences)) {
        if ($null -eq $occurrence -or
            $null -eq $occurrence.PSObject.Properties['Id'] -or
            $null -eq $occurrence.PSObject.Properties['OccurrenceCount']) {
            throw 'XMLTV evidence channel identity occurrences must contain Id and OccurrenceCount.'
        }

        # Channel identity is binding evidence. Preserve it ordinally; do not
        # trim or canonicalize a value that will be compared with M3U tvg-id.
        $channelId = if ($null -eq $occurrence.Id) { '' } else { [string]$occurrence.Id }
        $occurrenceCount = [int]$occurrence.OccurrenceCount
        if ([string]::IsNullOrWhiteSpace($channelId) -or $occurrenceCount -le 0) {
            throw 'XMLTV evidence channel identity occurrences must contain a non-empty Id and positive OccurrenceCount.'
        }

        if (-not $seenChannelIds.Add($channelId)) {
            throw "XMLTV evidence contains duplicate channel identity '$channelId'."
        }

        [void]$orderedChannelIdOccurrences.Add([pscustomobject][ordered]@{
                Id              = $channelId
                OccurrenceCount = $occurrenceCount
            })
    }

    $orderedChannelIdOccurrences.Sort([System.Comparison[object]]{
            param($left, $right)
            return [System.StringComparer]::Ordinal.Compare(
                [string]$left.Id,
                [string]$right.Id)
        })

    if ($orderedChannelIdOccurrences.Count -gt 0 -and
        $ChannelCount -ne $orderedChannelIdOccurrences.Count) {
        throw 'XMLTV evidence ChannelCount must equal the number of unique channel identity occurrences.'
    }

    if ($SourceKind -eq 'local') {
        if ([string]::IsNullOrWhiteSpace($SourcePath)) {
            throw 'XMLTV evidence SourcePath cannot be empty.'
        }
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
            throw 'Remote XMLTV evidence cannot contain a local SourcePath.'
        }

        if ([string]::IsNullOrWhiteSpace($SourceReference) -or
            $SourceReference -match '://|[\\/?#@]') {
            throw 'Remote XMLTV evidence SourceReference is not safe.'
        }

        if ($TransportContractVersion -ne 5) {
            throw 'Remote XMLTV evidence requires transport contract version 5.'
        }

        if ($HttpStatusCode -ne 200) {
            throw 'Remote XMLTV evidence requires HTTP status 200.'
        }

        if ($ContentType -notin @('application/xml', 'text/xml')) {
            throw 'Remote XMLTV evidence requires an XML content type.'
        }

        foreach ($encoding in @($ContentEncodings)) {
            if ([string]::IsNullOrWhiteSpace($encoding) -or
                $encoding.Trim().ToLowerInvariant() -notin @('identity', 'gzip', 'x-gzip')) {
                throw 'Remote XMLTV evidence contains an unsupported content encoding.'
            }
        }

        if ($RawContentLength.HasValue -and $RawContentLength.Value -lt 0) {
            throw 'Remote XMLTV evidence raw content length cannot be negative.'
        }
    }

    $record = [ordered]@{
        EvidenceType   = 'xmltv-source'
        SourceId       = $SourceId.Trim()
    }

    if ($SourceKind -eq 'local') {
        $record.SourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    }

    $record.Format = 'xmltv'
    $record.Compression = $Compression
    $record.ProgrammeCount = $ProgrammeCount
    $record.ChannelCount = $ChannelCount
    $record.ChannelIds = @($orderedChannelIdOccurrences | ForEach-Object { $_.Id })
    $record.ChannelIdOccurrences = @($orderedChannelIdOccurrences.ToArray())
    $record.DocumentBytes = $DocumentBytes

    if ($SourceKind -eq 'remote') {
        $record.SourceKind = 'remote'
        $record.SourceReference = $SourceReference.Trim()
        $record.TransportContractVersion = $TransportContractVersion
        $record.HttpStatusCode = $HttpStatusCode
        $record.ContentType = $ContentType.Trim().ToLowerInvariant()
        $record.ContentEncodings = @($ContentEncodings | ForEach-Object {
            $_.Trim().ToLowerInvariant()
        })
        $record.RawContentLength = if ($RawContentLength.HasValue) {
            $RawContentLength.Value
        }
        else {
            $null
        }
    }

    return [pscustomobject]$record
}
