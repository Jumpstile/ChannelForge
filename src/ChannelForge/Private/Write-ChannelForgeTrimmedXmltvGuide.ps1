function Write-ChannelForgeTrimmedXmltvGuide {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ChannelId,

        [Parameter(Mandatory)]
        [string]$TempRoot
    )

    $keep = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($id in @($ChannelId)) {
        if (-not [string]::IsNullOrEmpty($id)) { [void]$keep.Add($id) }
    }

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.IgnoreComments = $true
    $settings.IgnoreWhitespace = $true
    $settings.CloseInput = $false
    $settings.MaxCharactersFromEntities = 0

    # The trimmer opens the source itself; the shared 256 MB size gate is not bypassed by a switch.
    # Each pass streams the whole decompressed document and never holds it in memory.
    $readGuide = {
        param([scriptblock]$Visit)
        $opened = Open-ChannelForgeXmltvSourceStream -Path $Path -MaxDocumentBytes ([long]::MaxValue)
        try {
            $reader = [System.Xml.XmlReader]::Create($opened.Stream, $settings)
            try {
                & $Visit $reader
            }
            finally { $reader.Dispose() }
            $opened.Stream.CopyTo([System.IO.Stream]::Null)
            return $opened.Stream.BytesRead
        }
        finally {
            $opened.Stream.Dispose()
            for ($i = $opened.Resources.Count - 1; $i -ge 0; $i--) { $opened.Resources[$i].Dispose() }
        }
    }

    # Visits each element directly under <tv>; the visitor must consume the element it is given.
    $eachGuideElement = {
        param([System.Xml.XmlReader]$Reader, [scriptblock]$OnElement, [scriptblock]$OnRoot)
        $Reader.MoveToContent() | Out-Null
        if ($Reader.NodeType -ne [System.Xml.XmlNodeType]::Element -or $Reader.LocalName -ne 'tv') {
            throw 'XMLTV document root must be <tv>.'
        }
        & $OnRoot
        $Reader.Read() | Out-Null
        while (-not $Reader.EOF -and $Reader.NodeType -ne [System.Xml.XmlNodeType]::EndElement) {
            if ($Reader.NodeType -eq [System.Xml.XmlNodeType]::Element) { & $OnElement } else { $Reader.Read() | Out-Null }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void](& $readGuide {
            param($reader)
            & $eachGuideElement $reader {
                $id = switch ($reader.LocalName) { 'channel' { $reader.GetAttribute('id') } 'programme' { $reader.GetAttribute('channel') } }
                if (-not [string]::IsNullOrEmpty($id)) { [void]$seen.Add($id) }
                $reader.Skip()
            } {}
        })

    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
    $tempPath = Join-Path $TempRoot ('trimmed-guide-' + [guid]::NewGuid().ToString('N') + '.xml')
    $originalBytes = 0L
    try {
        $out = [System.IO.FileStream]::new($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $writerSettings = [System.Xml.XmlWriterSettings]::new()
            $writerSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
            $writerSettings.CloseOutput = $false
            $writer = [System.Xml.XmlWriter]::Create($out, $writerSettings)
            try {
                $originalBytes = [long](& $readGuide {
                        param($reader)
                        & $eachGuideElement $reader {
                            $id = switch ($reader.LocalName) { 'channel' { $reader.GetAttribute('id') } 'programme' { $reader.GetAttribute('channel') } }
                            if ($null -ne $id -and $keep.Contains($id)) { $writer.WriteNode($reader, $true) } else { $reader.Skip() }
                        } {
                            $writer.WriteStartElement('tv')
                            $writer.WriteAttributes($reader, $true)
                        }
                        $writer.WriteEndElement()
                    })
                $writer.Flush()
            }
            finally { $writer.Dispose() }
        }
        finally { $out.Dispose() }
    }
    catch {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw
    }

    $keptChannels = 0
    foreach ($id in $seen) { if ($keep.Contains($id)) { $keptChannels++ } }
    [pscustomobject][ordered]@{
        Path              = $tempPath
        KeptChannelCount  = $keptChannels
        GuideChannelCount = $seen.Count
        OriginalBytes     = $originalBytes
        KeptBytes         = (Get-Item -LiteralPath $tempPath).Length
    }
}
