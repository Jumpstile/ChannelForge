function Read-ChannelForgeXmltvSourceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [string]$SourcePath,

        [Parameter(Mandatory)]
        [long]$MaxDocumentBytes,

        [Parameter(Mandatory)]
        [string]$CandidateContractVersion,

        [switch]$SkipBadProgrammeTimes
    )

    $opened = $null
    try {
        $opened = Open-ChannelForgeXmltvSourceStream `
            -Path $Path `
            -MaxDocumentBytes $MaxDocumentBytes

        return @(Read-ChannelForgeXmltvDocument `
            -Stream $opened.Stream `
            -SourceId $SourceId `
            -SourcePath $(if ([string]::IsNullOrEmpty($SourcePath)) { $opened.SourcePath } else { $SourcePath }) `
            -Compression $opened.Compression `
            -MaxDocumentBytes $MaxDocumentBytes `
            -CandidateContractVersion $CandidateContractVersion `
            -SkipBadProgrammeTimes:$SkipBadProgrammeTimes)
    }
    catch {
        # A compressed guide over the limit is cut short, so the parser fails on truncated XML before the size check runs.
        if ($null -ne $opened -and $opened.Stream.LimitExceeded) {
            throw "XMLTV document exceeds the configured maximum of $MaxDocumentBytes bytes."
        }

        throw
    }
    finally {
        # Stream disposal below is parser cleanup only.
        if ($null -ne $opened) {
            try {
                $opened.Stream.Dispose()
            }
            catch {
                # Preserve the parse/open result while still attempting all cleanup.
            }

            for ($i = $opened.Resources.Count - 1; $i -ge 0; $i--) {
                try {
                    $opened.Resources[$i].Dispose()
                }
                catch {
                    # Preserve the parse/open result while still attempting all cleanup.
                }
            }
        }
    }
}
