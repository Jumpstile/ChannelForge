function New-ChannelForgeXmltvEvidenceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [ValidateSet('none', 'gzip', 'zip')]
        [string]$Compression = 'none',

        [Parameter(Mandatory)]
        [int]$ProgrammeCount,

        [Parameter(Mandatory)]
        [int]$ChannelCount,

        [Parameter(Mandatory)]
        [long]$DocumentBytes
    )

    if ([string]::IsNullOrWhiteSpace($SourceId)) {
        throw 'XMLTV evidence SourceId cannot be empty.'
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        throw 'XMLTV evidence SourcePath cannot be empty.'
    }

    if ($ProgrammeCount -lt 0 -or $ChannelCount -lt 0 -or $DocumentBytes -lt 0) {
        throw 'XMLTV evidence counts and byte totals cannot be negative.'
    }

    return [pscustomobject][ordered]@{
        EvidenceType   = 'xmltv-source'
        SourceId       = $SourceId.Trim()
        SourcePath     = [System.IO.Path]::GetFullPath($SourcePath)
        Format         = 'xmltv'
        Compression    = $Compression
        ProgrammeCount = $ProgrammeCount
        ChannelCount   = $ChannelCount
        DocumentBytes  = $DocumentBytes
    }
}
