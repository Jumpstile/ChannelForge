function Read-ChannelForgeXmltvDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

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

        [long]$MaxDocumentBytes = 268435456
    )

    if ([string]::IsNullOrWhiteSpace($SourceId)) {
        throw 'XMLTV SourceId cannot be empty.'
    }

    if ($SourceKind -eq 'remote' -and [string]::IsNullOrWhiteSpace($SourceReference)) {
        throw 'Remote XMLTV SourceReference cannot be empty.'
    }

    if ($MaxDocumentBytes -le 0) {
        throw 'MaxDocumentBytes must be greater than zero.'
    }

    $timestampParser = {
        param(
            [string]$Value,
            [string]$AttributeName
        )

        if ([string]::IsNullOrWhiteSpace($Value)) {
            throw "XMLTV programme attribute '$AttributeName' cannot be empty."
        }

        $raw = $Value.Trim()
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $allowWhitespace = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces

        try {
            if ($raw -match '^(?<stamp>\d{14})\s*(?<offset>[+-]\d{4})$') {
                $offset = $Matches['offset']
                $normalized = "{0} {1}:{2}" -f $Matches['stamp'], $offset.Substring(0, 3), $offset.Substring(3, 2)
                return [datetimeoffset]::ParseExact($normalized, 'yyyyMMddHHmmss zzz', $culture, $allowWhitespace)
            }

            if ($raw -match '^\d{14}$') {
                $styles = $allowWhitespace -bor [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
                return [datetimeoffset]::ParseExact($raw, 'yyyyMMddHHmmss', $culture, $styles)
            }

            return [datetimeoffset]::Parse($raw, $culture, $allowWhitespace)
        }
        catch {
            throw "Invalid XMLTV programme $AttributeName timestamp '$Value'."
        }
    }

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.IgnoreComments = $true
    $settings.IgnoreWhitespace = $true
    $settings.CloseInput = $false
    $settings.MaxCharactersInDocument = $MaxDocumentBytes
    $settings.MaxCharactersFromEntities = 0

    $reader = $null
    $programmes = [System.Collections.Generic.List[Programme]]::new()
    $channelIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sawRoot = $false

    try {
        $reader = [System.Xml.XmlReader]::Create($Stream, $settings)

        while ($reader.Read()) {
            if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                continue
            }

            if (-not $sawRoot) {
                if ($reader.Depth -ne 0 -or $reader.LocalName -ne 'tv') {
                    throw 'XMLTV document root must be <tv>.'
                }

                $sawRoot = $true
                continue
            }

            if ($reader.Depth -ne 1) {
                continue
            }

            switch ($reader.LocalName) {
                'channel' {
                    $channelId = $reader.GetAttribute('id')
                    if ([string]::IsNullOrWhiteSpace($channelId)) {
                        throw 'XMLTV channel elements require a non-empty id attribute.'
                    }

                    [void]$channelIds.Add($channelId.Trim())
                }

                'programme' {
                    $programmeDepth = $reader.Depth
                    $channelId = $reader.GetAttribute('channel')
                    $startValue = $reader.GetAttribute('start')
                    $endValue = $reader.GetAttribute('stop')
                    $title = ''
                    $subtitle = ''
                    $description = ''
                    $categories = [System.Collections.Generic.List[string]]::new()
                    $episodeNumber = ''
                    $isNew = $false
                    $isLive = $false
                    $isPremiere = $false

                    if ([string]::IsNullOrWhiteSpace($channelId)) {
                        throw 'XMLTV programme elements require a non-empty channel attribute.'
                    }

                    if ($reader.IsEmptyElement) {
                        throw 'XMLTV programme elements cannot be empty.'
                    }

                    if (-not $reader.Read()) {
                        throw 'XMLTV programme element is incomplete.'
                    }

                    while ($true) {
                        if ($reader.NodeType -eq [System.Xml.XmlNodeType]::EndElement -and
                            $reader.Depth -eq $programmeDepth -and
                            $reader.LocalName -eq 'programme') {
                            break
                        }

                        if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                            $reader.Depth -eq ($programmeDepth + 1)) {
                            switch ($reader.LocalName) {
                            'title' {
                                $value = $reader.ReadElementContentAsString()
                                if ([string]::IsNullOrWhiteSpace($title) -and -not [string]::IsNullOrWhiteSpace($value)) {
                                    $title = $value.Trim()
                                }
                            }

                            'sub-title' {
                                $value = $reader.ReadElementContentAsString()
                                if ([string]::IsNullOrWhiteSpace($subtitle) -and -not [string]::IsNullOrWhiteSpace($value)) {
                                    $subtitle = $value.Trim()
                                }
                            }

                            'desc' {
                                $value = $reader.ReadElementContentAsString()
                                if ([string]::IsNullOrWhiteSpace($description) -and -not [string]::IsNullOrWhiteSpace($value)) {
                                    $description = $value.Trim()
                                }
                            }

                            'category' {
                                $value = $reader.ReadElementContentAsString()
                                if (-not [string]::IsNullOrWhiteSpace($value)) {
                                    [void]$categories.Add($value.Trim())
                                }
                            }

                            'episode-num' {
                                $value = $reader.ReadElementContentAsString()
                                if ([string]::IsNullOrWhiteSpace($episodeNumber) -and -not [string]::IsNullOrWhiteSpace($value)) {
                                    $episodeNumber = $value.Trim()
                                }
                            }

                            'new' {
                                $isNew = $true
                                $reader.Skip()
                            }

                            'live' {
                                $isLive = $true
                                $reader.Skip()
                            }

                            'premiere' {
                                $isPremiere = $true
                                $reader.Skip()
                            }

                            default {
                                $reader.Skip()
                            }
                            }

                            continue
                        }

                        if (-not $reader.Read()) {
                            throw 'XMLTV programme element is incomplete.'
                        }
                    }

                    if ($reader.NodeType -ne [System.Xml.XmlNodeType]::EndElement -or
                        $reader.LocalName -ne 'programme') {
                        throw 'XMLTV programme element is incomplete.'
                    }

                    $start = & $timestampParser $startValue 'start'
                    $end = & $timestampParser $endValue 'stop'
                    $programme = New-ChannelForgeProgramme `
                        -ChannelId $channelId `
                        -Start $start `
                        -End $end `
                        -Title $title `
                        -Subtitle $subtitle `
                        -Description $description `
                        -Categories @($categories) `
                        -EpisodeNumber $episodeNumber `
                        -IsNew $isNew `
                        -IsLive $isLive `
                        -IsPremiere $isPremiere `
                        -SourceId $SourceId

                    [void]$programmes.Add($programme)
                }

                default {
                }
            }
        }

        if (-not $sawRoot) {
            throw 'XMLTV document is empty.'
        }

        $documentBytes = 0
        if ($Stream -is [BoundedStream]) {
            # Preserve the local BoundedStream limit probe and byte accounting.
            $Stream.EnsureWithinLimit()
            $documentBytes = $Stream.BytesRead
        }
        elseif ($Stream -is [BoundedDecompressionStream]) {
            # This stream is already the decompressed-byte boundary. Drain it
            # without wrapping it so truncated codings and trailing bytes are
            # observed before a document is considered Fetched.
            $drainBuffer = [byte[]]::new(8192)
            while ($true) {
                $read = $Stream.Read($drainBuffer, 0, $drainBuffer.Length)
                if ($read -eq 0) {
                    break
                }
            }

            $documentBytes = $Stream.BytesRead
        }

        $comparison = [System.Comparison[Programme]]{
            param(
                [Programme]$Left,
                [Programme]$Right
            )

            $result = [System.StringComparer]::Ordinal.Compare($Left.ChannelId, $Right.ChannelId)
            if ($result -ne 0) { return $result }

            $result = [datetimeoffset]::Compare($Left.Start, $Right.Start)
            if ($result -ne 0) { return $result }

            $result = [datetimeoffset]::Compare($Left.End, $Right.End)
            if ($result -ne 0) { return $result }

            $result = [System.StringComparer]::Ordinal.Compare($Left.Title, $Right.Title)
            if ($result -ne 0) { return $result }

            $result = [System.StringComparer]::Ordinal.Compare($Left.Subtitle, $Right.Subtitle)
            if ($result -ne 0) { return $result }

            $result = [System.StringComparer]::Ordinal.Compare($Left.Description, $Right.Description)
            if ($result -ne 0) { return $result }

            $result = [System.StringComparer]::Ordinal.Compare($Left.EpisodeNumber, $Right.EpisodeNumber)
            if ($result -ne 0) { return $result }

            $leftCategories = [string]::Join([char]31, [string[]]$Left.Categories)
            $rightCategories = [string]::Join([char]31, [string[]]$Right.Categories)
            return [System.StringComparer]::Ordinal.Compare($leftCategories, $rightCategories)
        }

        $programmes.Sort($comparison)
        $evidenceParameters = @{
            SourceId       = $SourceId
            SourcePath     = $SourcePath
            Compression    = $Compression
            SourceKind     = $SourceKind
            SourceReference = $SourceReference
            TransportContractVersion = $TransportContractVersion
            HttpStatusCode  = $HttpStatusCode
            ContentType     = $ContentType
            ContentEncodings = $ContentEncodings
            RawContentLength = $RawContentLength
            ProgrammeCount  = $programmes.Count
            ChannelCount    = $channelIds.Count
            DocumentBytes   = $documentBytes
        }
        $evidence = New-ChannelForgeXmltvEvidenceRecord @evidenceParameters

        foreach ($programme in $programmes) {
            $programme.Evidence = $evidence
        }

        return @($programmes.ToArray())
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
    }
}
