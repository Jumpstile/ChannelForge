function Import-ChannelForgeXmltvSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$SourceId = '',

        [long]$MaxDocumentBytes = 268435456,

        [System.Collections.IDictionary]$AcquisitionStatus,

        [ValidateSet('blocker-2-contract/v7','blocker-2-contract/v8','blocker-2-contract/v10')]
        [string]$CandidateContractVersion = 'blocker-2-contract/v7',

        # Playlist tvg-ids. Only used when the guide is over the size limit (guide-trim/v2).
        [string[]]$TrimToChannelId,

        # Staging folder for the trimmed temp guide. Trimming needs both this and -TrimToChannelId.
        [string]$TrimTempRoot
    )

    if ($Path -match '^[a-z][a-z0-9+.-]*://') {
        throw 'XMLTV ingestion accepts local file paths only; URL or network sources are not supported.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XMLTV source not found: $Path"
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedSourceId = if ([string]::IsNullOrWhiteSpace($SourceId)) { $fullPath } else { $SourceId.Trim() }
    $readArguments = @{
        SourceId                 = $resolvedSourceId
        MaxDocumentBytes         = $MaxDocumentBytes
        CandidateContractVersion = $CandidateContractVersion
    }
    $hashPath = $fullPath
    $trim = $null
    try {
        # Trimming needs the playlist ids and a staging folder. A file already bigger than the limit
        # (even compressed) is trimmed at once instead of reading up to the limit first.
        $canTrim = $null -ne $TrimToChannelId -and -not [string]::IsNullOrWhiteSpace($TrimTempRoot)
        $needTrim = $canTrim -and (Get-Item -LiteralPath $fullPath).Length -gt $MaxDocumentBytes
        if (-not $needTrim) {
            try {
                $programmes = @(Read-ChannelForgeXmltvSourceFile -Path $fullPath @readArguments)
            }
            catch {
                $sizeExceeded = $false
                for ($e = $_.Exception; $null -ne $e; $e = $e.InnerException) {
                    if ($e.Message -like 'XMLTV document exceeds the configured maximum*') { $sizeExceeded = $true }
                }
                if (-not $sizeExceeded -or -not $canTrim) { throw }
                $needTrim = $true
            }
        }
        if ($needTrim) {
            $trim = Write-ChannelForgeTrimmedXmltvGuide -Path $fullPath -ChannelId $TrimToChannelId -TempRoot $TrimTempRoot
            $hashPath = $trim.Path
            try {
                $programmes = @(Read-ChannelForgeXmltvSourceFile -Path $hashPath -SourcePath $fullPath @readArguments)
            }
            catch {
                if ($_.Exception.Message -like 'XMLTV document exceeds the configured maximum*') {
                    throw "The guide is still too big after keeping only the channels your playlist uses: $($trim.KeptChannelCount) playlist channels matched, and the kept guide is $([math]::Round($trim.KeptBytes / 1MB, 1)) MB (limit $([math]::Round($MaxDocumentBytes / 1MB, 1)) MB)."
                }
                throw
            }
        }

        if ($null -ne $AcquisitionStatus) {
            $AcquisitionStatus.Clear()
            # The hash is over exact file bytes: the guide itself, or the trimmed temp file when trimmed.
            $AcquisitionStatus['InputArtifactHash'] = Get-ChannelForgeDomainHash `
                -Domain 'input-xmltv/v2' `
                -Bytes ([System.IO.File]::ReadAllBytes($hashPath))
            if ($null -ne $trim) {
                $AcquisitionStatus['GuideTrim'] = [pscustomobject][ordered]@{
                    KeptChannelCount  = $trim.KeptChannelCount
                    GuideChannelCount = $trim.GuideChannelCount
                    KeptProgrammeCount    = $trim.KeptProgrammeCount
                    DroppedProgrammeCount = $trim.DroppedProgrammeCount
                    OriginalBytes     = $trim.OriginalBytes
                    KeptBytes         = $trim.KeptBytes
                }
            }
        }
        return $programmes
    }
    finally {
        if ($null -ne $trim) { Remove-Item -LiteralPath $trim.Path -Force -ErrorAction SilentlyContinue }
    }
}
