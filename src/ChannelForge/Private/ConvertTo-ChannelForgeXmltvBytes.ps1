function ConvertTo-ChannelForgeXmltvBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$MergeResult
    )

    if ($null -eq $MergeResult) {
        throw 'A merged XMLTV programme result is required.'
    }

    $mergeProperties = @($MergeResult.PSObject.Properties.Name)
    if ($mergeProperties -notcontains 'BoundProgrammes') {
        throw 'Merged XMLTV result must contain BoundProgrammes.'
    }

    if ($mergeProperties -notcontains 'Bindings') {
        throw 'Merged XMLTV result must contain Bindings.'
    }

    if ($mergeProperties -contains 'HasConflicts' -and [bool]$MergeResult.HasConflicts) {
        throw 'Cannot serialize an XMLTV result with conflicts or NeedsReview records.'
    }

    if ($mergeProperties -contains 'Conflicts' -and @($MergeResult.Conflicts).Count -gt 0) {
        throw 'Cannot serialize an XMLTV result with conflicts or NeedsReview records.'
    }

    function Normalize-XmltvText {
        param(
            [object]$Value,
            [Parameter(Mandatory)]
            [string]$FieldName,
            [bool]$Required = $false
        )

        $normalized = if ($null -eq $Value) { '' } else { [string]$Value }
        $normalized = $normalized.Trim()
        $normalized = [regex]::Replace($normalized, "\r\n?", [string][char]10)

        if ($Required -and [string]::IsNullOrWhiteSpace($normalized)) {
            throw "XMLTV $FieldName cannot be empty."
        }

        try {
            [System.Xml.XmlConvert]::VerifyXmlChars($normalized) | Out-Null
        }
        catch {
            throw "XMLTV $FieldName contains invalid XML characters."
        }

        return $normalized
    }

    function Normalize-XmltvProvenance {
        param(
            [object]$Value,
            [Parameter(Mandatory)]
            [string]$FieldName
        )

        $normalized = Normalize-XmltvText -Value $Value -FieldName $FieldName -Required $true
        if ($normalized -match '[\\/]') {
            throw "XMLTV $FieldName cannot contain a path."
        }

        [System.Uri]$uri = $null
        if ([System.Uri]::TryCreate($normalized, [System.UriKind]::Absolute, [ref]$uri)) {
            throw "XMLTV $FieldName cannot contain a URL."
        }

        return $normalized
    }

    $declaredBindings = @($MergeResult.Bindings)
    if ($declaredBindings.Count -eq 0) {
        throw 'Merged XMLTV result must contain at least one binding.'
    }

    $declaredBindingKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($declaredBinding in $declaredBindings) {
        if ($null -eq $declaredBinding -or $declaredBinding -isnot [ProgrammeChannelBinding]) {
            throw 'Merged XMLTV result contains an invalid ProgrammeChannelBinding.'
        }

        $sourceId = Normalize-XmltvProvenance -Value $declaredBinding.SourceId -FieldName 'binding SourceId'
        $channelReference = Normalize-XmltvProvenance -Value $declaredBinding.ChannelReference -FieldName 'binding ChannelReference'
        $bindingKey = Normalize-XmltvText -Value $declaredBinding.BindingKey -FieldName 'binding BindingKey' -Required $true

        if (-not [string]::Equals($declaredBinding.BindingKind, 'SourceScoped', [System.StringComparison]::Ordinal)) {
            throw "Unsupported XMLTV binding kind '$($declaredBinding.BindingKind)'."
        }

        $expectedBindingKey = New-ChannelForgeProgrammeBindingKey -SourceId $sourceId -ChannelReference $channelReference
        if (-not [string]::Equals($bindingKey, $expectedBindingKey, [System.StringComparison]::Ordinal)) {
            throw "XMLTV binding BindingKey '$bindingKey' does not match its source-scoped identity."
        }

        [void]$declaredBindingKeys.Add($bindingKey)
    }

    $boundProgrammes = @($MergeResult.BoundProgrammes)
    if ($boundProgrammes.Count -eq 0) {
        throw 'Merged XMLTV result must contain at least one bound programme.'
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $channels = [System.Collections.Generic.List[object]]::new()
    $seenChannelKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($bound in $boundProgrammes) {
        if ($null -eq $bound) {
            throw 'Merged XMLTV result contains a null bound programme record.'
        }

        $boundProperties = @($bound.PSObject.Properties.Name)
        if ($boundProperties -notcontains 'Programme' -or $boundProperties -notcontains 'Binding') {
            throw 'Each bound XMLTV programme must contain Programme and Binding.'
        }

        $status = if ($boundProperties -contains 'Status') { [string]$bound.Status } else { '' }
        if (-not [string]::Equals($status, 'Unique', [System.StringComparison]::Ordinal) -and
            -not [string]::Equals($status, 'DuplicateMerged', [System.StringComparison]::Ordinal)) {
            throw "Cannot serialize XMLTV programme with status '$status'; conflicts and NeedsReview records are not publishable."
        }

        $programme = $bound.Programme
        $binding = $bound.Binding
        if ($null -eq $programme -or $programme -isnot [Programme]) {
            throw 'Each bound XMLTV record must contain a Programme domain object.'
        }

        if ($null -eq $binding -or $binding -isnot [ProgrammeChannelBinding]) {
            throw 'Each bound XMLTV record must contain a ProgrammeChannelBinding.'
        }

        $sourceId = Normalize-XmltvProvenance -Value $binding.SourceId -FieldName 'binding SourceId'
        $channelReference = Normalize-XmltvProvenance -Value $binding.ChannelReference -FieldName 'binding ChannelReference'
        $bindingKey = Normalize-XmltvText -Value $binding.BindingKey -FieldName 'binding BindingKey' -Required $true
        $expectedBindingKey = New-ChannelForgeProgrammeBindingKey -SourceId $sourceId -ChannelReference $channelReference

        if (-not [string]::Equals($binding.BindingKind, 'SourceScoped', [System.StringComparison]::Ordinal)) {
            throw "Unsupported XMLTV binding kind '$($binding.BindingKind)'."
        }

        if (-not [string]::Equals($bindingKey, $expectedBindingKey, [System.StringComparison]::Ordinal)) {
            throw "XMLTV binding BindingKey '$bindingKey' does not match its source-scoped identity."
        }

        if (-not $declaredBindingKeys.Contains($bindingKey)) {
            throw "XMLTV bound programme references undeclared BindingKey '$bindingKey'."
        }

        $programmeSourceId = Normalize-XmltvProvenance -Value $programme.SourceId -FieldName 'programme SourceId'
        $programmeChannelReference = Normalize-XmltvProvenance -Value $programme.ChannelId -FieldName 'programme ChannelId'
        if (-not [string]::Equals($programmeSourceId, $sourceId, [System.StringComparison]::Ordinal) -or
            -not [string]::Equals($programmeChannelReference, $channelReference, [System.StringComparison]::Ordinal)) {
            throw 'Programme identity does not match its source-scoped binding.'
        }

        $title = Normalize-XmltvText -Value $programme.Title -FieldName 'programme title' -Required $true
        $subtitle = Normalize-XmltvText -Value $programme.Subtitle -FieldName 'programme subtitle'
        $description = Normalize-XmltvText -Value $programme.Description -FieldName 'programme description'
        $episodeNumber = Normalize-XmltvText -Value $programme.EpisodeNumber -FieldName 'programme episode number'

        if ($programme.Start -eq [System.DateTimeOffset]::MinValue -or $programme.End -eq [System.DateTimeOffset]::MinValue) {
            throw 'XMLTV programme start and end are required.'
        }

        if ($programme.End -le $programme.Start) {
            throw 'XMLTV programme interval must have End later than Start.'
        }

        $startUtc = $programme.Start.ToUniversalTime()
        $endUtc = $programme.End.ToUniversalTime()
        $categories = [System.Collections.Generic.List[string]]::new()
        foreach ($category in @($programme.Categories)) {
            $normalizedCategory = Normalize-XmltvText -Value $category -FieldName 'programme category'
            if (-not [string]::IsNullOrWhiteSpace($normalizedCategory)) {
                $categories.Add($normalizedCategory)
            }
        }
        $categories.Sort([System.StringComparer]::Ordinal)
        $categoryKey = [string]::Join([char]31, [string[]]$categories.ToArray())

        $record = [pscustomobject][ordered]@{
            BindingKey       = $bindingKey
            SourceId         = $sourceId
            ChannelReference = $channelReference
            Programme        = $programme
            StartUtc         = $startUtc
            EndUtc           = $endUtc
            StartTicks       = $startUtc.Ticks
            EndTicks         = $endUtc.Ticks
            Title            = $title
            Subtitle         = $subtitle
            Description      = $description
            Categories       = @($categories.ToArray())
            CategoryKey      = $categoryKey
            EpisodeNumber    = $episodeNumber
            IsNew            = [bool]$programme.IsNew
            IsLive           = [bool]$programme.IsLive
            IsPremiere       = [bool]$programme.IsPremiere
        }
        $records.Add($record)

        if ($seenChannelKeys.Add($bindingKey)) {
            $channels.Add([pscustomobject][ordered]@{
                BindingKey       = $bindingKey
                SourceId         = $sourceId
                ChannelReference = $channelReference
            })
        }
    }

    $recordComparison = [System.Comparison[object]]{
        param($left, $right)

        $comparison = [System.StringComparer]::Ordinal.Compare($left.BindingKey, $right.BindingKey)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = if ($left.StartTicks -lt $right.StartTicks) { -1 } elseif ($left.StartTicks -gt $right.StartTicks) { 1 } else { 0 }
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = if ($left.EndTicks -lt $right.EndTicks) { -1 } elseif ($left.EndTicks -gt $right.EndTicks) { 1 } else { 0 }
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [System.StringComparer]::Ordinal.Compare($left.Title, $right.Title)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [System.StringComparer]::Ordinal.Compare($left.Subtitle, $right.Subtitle)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [System.StringComparer]::Ordinal.Compare($left.Description, $right.Description)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [System.StringComparer]::Ordinal.Compare($left.CategoryKey, $right.CategoryKey)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [System.StringComparer]::Ordinal.Compare($left.EpisodeNumber, $right.EpisodeNumber)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [int]$left.IsNew - [int]$right.IsNew
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [int]$left.IsLive - [int]$right.IsLive
        if ($comparison -ne 0) {
            return $comparison
        }

        return [int]$left.IsPremiere - [int]$right.IsPremiere
    }
    $records.Sort($recordComparison)

    $channelComparison = [System.Comparison[object]]{
        param($left, $right)

        return [System.StringComparer]::Ordinal.Compare($left.BindingKey, $right.BindingKey)
    }
    $channels.Sort($channelComparison)

    $namespace = 'urn:channelforge'
    $timestampFormat = "yyyyMMddHHmmss '+0000'"
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = [string][char]10
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Entitize
    $settings.OmitXmlDeclaration = $false
    $settings.CloseOutput = $false
    $settings.CheckCharacters = $true

    $stream = [System.IO.MemoryStream]::new()
    $writer = $null
    $bytes = $null

    function Write-XmltvTextElement {
        param(
            [Parameter(Mandatory)]
            [System.Xml.XmlWriter]$Writer,

            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Value,

            [bool]$Namespaced = $false
        )

        if ([string]::IsNullOrEmpty($Value)) {
            return
        }

        if ($Namespaced) {
            $Writer.WriteStartElement('channelforge', $Name, 'urn:channelforge')
        }
        else {
            $Writer.WriteStartElement($Name)
        }
        $Writer.WriteString($Value)
        $Writer.WriteEndElement()
    }

    try {
        $writer = [System.Xml.XmlWriter]::Create($stream, $settings)
        $writer.WriteStartDocument()
        $writer.WriteStartElement('tv')
        $writer.WriteAttributeString('generator-info-name', 'ChannelForge')
        $writer.WriteAttributeString('xmlns', 'channelforge', 'http://www.w3.org/2000/xmlns/', $namespace)

        foreach ($channel in $channels) {
            $writer.WriteStartElement('channel')
            $writer.WriteAttributeString('id', $channel.BindingKey)
            Write-XmltvTextElement -Writer $writer -Name 'display-name' -Value $channel.ChannelReference
            Write-XmltvTextElement -Writer $writer -Name 'source-id' -Value $channel.SourceId -Namespaced $true
            Write-XmltvTextElement -Writer $writer -Name 'channel-reference' -Value $channel.ChannelReference -Namespaced $true
            $writer.WriteEndElement()
        }

        foreach ($record in $records) {
            $writer.WriteStartElement('programme')
            $writer.WriteAttributeString('start', $record.StartUtc.ToString($timestampFormat, [System.Globalization.CultureInfo]::InvariantCulture))
            $writer.WriteAttributeString('stop', $record.EndUtc.ToString($timestampFormat, [System.Globalization.CultureInfo]::InvariantCulture))
            $writer.WriteAttributeString('channel', $record.BindingKey)
            Write-XmltvTextElement -Writer $writer -Name 'source-id' -Value $record.SourceId -Namespaced $true
            Write-XmltvTextElement -Writer $writer -Name 'title' -Value $record.Title
            if (-not [string]::IsNullOrEmpty($record.Subtitle)) {
                Write-XmltvTextElement -Writer $writer -Name 'sub-title' -Value $record.Subtitle
            }
            if (-not [string]::IsNullOrEmpty($record.Description)) {
                Write-XmltvTextElement -Writer $writer -Name 'desc' -Value $record.Description
            }

            foreach ($category in $record.Categories) {
                Write-XmltvTextElement -Writer $writer -Name 'category' -Value $category
            }

            if (-not [string]::IsNullOrEmpty($record.EpisodeNumber)) {
                $writer.WriteStartElement('episode-num')
                $writer.WriteAttributeString('system', 'onscreen')
                $writer.WriteString($record.EpisodeNumber)
                $writer.WriteEndElement()
            }

            if ($record.IsNew) {
                $writer.WriteStartElement('new')
                $writer.WriteEndElement()
            }

            if ($record.IsLive) {
                $writer.WriteStartElement('live')
                $writer.WriteEndElement()
            }

            if ($record.IsPremiere) {
                $writer.WriteStartElement('premiere')
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
        $writer.Flush()
        $stream.WriteByte([byte][char]10)
        $bytes = $stream.ToArray()
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
        $stream.Dispose()
    }

    return (, [byte[]]$bytes)
}
