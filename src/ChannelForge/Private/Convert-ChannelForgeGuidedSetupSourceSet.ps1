function ConvertFrom-ChannelForgeGuidedSetupMultiSourceRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Text.Json.JsonElement]$Root,
        [Parameter(Mandatory)]$Limits
    )

    $properties = @{}
    foreach ($property in $Root.EnumerateObject()) {
        if ($properties.ContainsKey($property.Name)) {
            throw [System.ArgumentException]::new('The proposal request contains duplicate properties.')
        }
        if ($property.Name -notin @('schemaVersion', 'playlists', 'guides', 'bindings')) {
            throw [System.ArgumentException]::new('The proposal request contains an unsupported property.')
        }
        $properties[$property.Name] = $property.Value
    }

    if (-not $properties.ContainsKey('playlists') -or
        $properties['playlists'].ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        throw [System.ArgumentException]::new('At least one M3U playlist is required.')
    }
    if (-not $properties.ContainsKey('guides') -or
        $properties['guides'].ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        throw [System.ArgumentException]::new('The guides property must be an array.')
    }
    if ($properties.ContainsKey('bindings') -and
        $properties['bindings'].ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        throw [System.ArgumentException]::new('The bindings property must be an array.')
    }

    $playlistsJson = @($properties['playlists'].EnumerateArray())
    $guidesJson = @($properties['guides'].EnumerateArray())
    if ($playlistsJson.Count -lt 1 -or $playlistsJson.Count -gt $Limits.MaxPlaylists) {
        throw [System.ArgumentException]::new("The proposal must contain between 1 and $($Limits.MaxPlaylists) playlists.")
    }
    if ($guidesJson.Count -gt $Limits.MaxGuides) {
        throw [System.ArgumentException]::new("The proposal must contain no more than $($Limits.MaxGuides) guides.")
    }

    $aggregate = [pscustomobject]@{ Value = [int64]0 }
    $parseSource = {
        param([System.Text.Json.JsonElement]$Element, [string]$Kind, [int]$Index)

        if ($Element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw [System.ArgumentException]::new("The $Kind source descriptor is invalid.")
        }
        $sourceProperties = @{}
        foreach ($property in $Element.EnumerateObject()) {
            if ($sourceProperties.ContainsKey($property.Name)) {
                throw [System.ArgumentException]::new("The $Kind source descriptor contains duplicate properties.")
            }
            if ($property.Name -notin @('sourceKey', 'label', 'priority', 'contentBase64', 'url')) {
                throw [System.ArgumentException]::new("The $Kind source descriptor contains an unsupported property.")
            }
            $sourceProperties[$property.Name] = $property.Value
        }

        if (-not $sourceProperties.ContainsKey('sourceKey') -or
            $sourceProperties['sourceKey'].ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
            throw [System.ArgumentException]::new("The $Kind source key is required.")
        }
        $sourceKey = $sourceProperties['sourceKey'].GetString()
        if ([string]::IsNullOrWhiteSpace($sourceKey) -or $sourceKey -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
            throw [System.ArgumentException]::new("The $Kind source key is invalid.")
        }

        $label = "$Kind source"
        if ($sourceProperties.ContainsKey('label')) {
            if ($sourceProperties['label'].ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                throw [System.ArgumentException]::new("The $Kind source label is invalid.")
            }
            $label = $sourceProperties['label'].GetString()
            if ([string]::IsNullOrWhiteSpace($label) -or $label.Length -gt $Limits.MaxLabelLength -or $label -match '[\x00-\x1F\x7F]') {
                throw [System.ArgumentException]::new("The $Kind source label is invalid.")
            }
        }

        $priority = 100
        if ($sourceProperties.ContainsKey('priority')) {
            if ($sourceProperties['priority'].ValueKind -ne [System.Text.Json.JsonValueKind]::Number -or
                -not $sourceProperties['priority'].TryGetInt32([ref]$priority) -or $priority -lt 0) {
                throw [System.ArgumentException]::new("The $Kind source priority is invalid.")
            }
        }

        $hasContent = $sourceProperties.ContainsKey('contentBase64')
        $hasUrl = $sourceProperties.ContainsKey('url')
        if ($hasContent -eq $hasUrl) {
            throw [System.ArgumentException]::new("Each $Kind source must provide exactly one contentBase64 or url value.")
        }

        $sourceKind = if ($hasContent) { 'managed-file' } else { 'public-https' }
        $bytes = $null
        $url = $null
        if ($hasContent) {
            if ($sourceProperties['contentBase64'].ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                throw [System.ArgumentException]::new("The $Kind source content is invalid.")
            }
            $encoded = $sourceProperties['contentBase64'].GetString()
            if ([string]::IsNullOrWhiteSpace($encoded)) {
                throw [System.ArgumentException]::new("The $Kind source content is required.")
            }
            try { $bytes = [Convert]::FromBase64String($encoded) }
            catch { throw [System.ArgumentException]::new("The $Kind source content is invalid.") }
            $maxBytes = if ($Kind -eq 'M3U') { $Limits.MaxM3UBytes } else { $Limits.MaxXMLTVBytes }
            if ($bytes.Length -eq 0) { throw [System.ArgumentException]::new("The $Kind source content is empty.") }
            if ($bytes.Length -gt $maxBytes) { throw [System.InvalidOperationException]::new("The $Kind source content is too large.") }
            $aggregate.Value += $bytes.Length
            if ($aggregate.Value -gt $Limits.MaxAggregateSourceBytes) {
                throw [System.InvalidOperationException]::new('The aggregate source content is too large.')
            }
        }
        else {
            if ($sourceProperties['url'].ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                throw [System.ArgumentException]::new("The $Kind source URL is invalid.")
            }
            $url = $sourceProperties['url'].GetString()
            $parsed = $null
            if (-not (Test-ChannelForgeSourceUrl -Url $url) -or
                -not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsed) -or
                -not [string]::IsNullOrEmpty($parsed.UserInfo) -or
                -not [string]::IsNullOrEmpty($parsed.Query) -or
                -not [string]::IsNullOrEmpty($parsed.Fragment)) {
                throw [System.ArgumentException]::new("The $Kind source URL is not a supported public HTTPS URL.")
            }
        }

        return [pscustomobject][ordered]@{
            Kind       = $Kind
            SourceKey  = $sourceKey
            Label      = $label
            Priority   = $priority
            SourceKind = $sourceKind
            Bytes      = $bytes
            Url        = $url
            SourceId   = Get-ChannelForgeSourceSetSourceId -Kind $Kind -SourceKind $sourceKind -SourceKey $sourceKey
            InputIndex = $Index
        }
    }

    $playlists = @()
    $playlistKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $playlistsJson) {
        $source = & $parseSource $item 'M3U' $playlists.Count
        if (-not $playlistKeys.Add([string]$source.SourceKey)) {
            throw [System.ArgumentException]::new('Duplicate playlist source identity is not allowed.')
        }
        $playlists += $source
    }

    $guides = @()
    $guideKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $guidesJson) {
        $source = & $parseSource $item 'XMLTV' $guides.Count
        if (-not $guideKeys.Add([string]$source.SourceKey)) {
            throw [System.ArgumentException]::new('Duplicate guide source identity is not allowed.')
        }
        $guides += $source
    }

    $playlistByKey = @{}
    foreach ($source in $playlists) { $playlistByKey[[string]$source.SourceKey] = $source }
    $guideByKey = @{}
    foreach ($source in $guides) { $guideByKey[[string]$source.SourceKey] = $source }

    $bindingJson = if ($properties.ContainsKey('bindings')) { @($properties['bindings'].EnumerateArray()) } else { @() }
    if ($bindingJson.Count -gt $Limits.MaxBindings) {
        throw [System.ArgumentException]::new("The proposal must contain no more than $($Limits.MaxBindings) bindings.")
    }
    $bindings = @()
    $boundGuideKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $effectiveBindings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($element in $bindingJson) {
        if ($element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw [System.ArgumentException]::new('The guide binding descriptor is invalid.')
        }
        $bindingProperties = @{}
        foreach ($property in $element.EnumerateObject()) {
            if ($bindingProperties.ContainsKey($property.Name)) {
                throw [System.ArgumentException]::new('The guide binding descriptor contains duplicate properties.')
            }
            if ($property.Name -notin @('guideRef', 'playlistRefs', 'appliesToAll')) {
                throw [System.ArgumentException]::new('The guide binding descriptor contains an unsupported property.')
            }
            $bindingProperties[$property.Name] = $property.Value
        }
        if (-not $bindingProperties.ContainsKey('guideRef') -or
            $bindingProperties['guideRef'].ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
            throw [System.ArgumentException]::new('A guide binding must identify a guide reference.')
        }
        $guideKey = $bindingProperties['guideRef'].GetString()
        if (-not $guideByKey.ContainsKey($guideKey)) { throw [System.ArgumentException]::new('A guide binding references an unknown guide.') }
        if (-not $boundGuideKeys.Add($guideKey)) { throw [System.ArgumentException]::new('Each guide may have only one binding descriptor.') }
        if (-not $bindingProperties.ContainsKey('playlistRefs') -or
            $bindingProperties['playlistRefs'].ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
            throw [System.ArgumentException]::new('A guide binding must provide playlistRefs.')
        }
        $playlistKeysForBinding = @()
        foreach ($playlistRef in @($bindingProperties['playlistRefs'].EnumerateArray())) {
            if ($playlistRef.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { throw [System.ArgumentException]::new('A guide binding playlist reference is invalid.') }
            $playlistKey = $playlistRef.GetString()
            if ($playlistKey -in $playlistKeysForBinding) { throw [System.ArgumentException]::new('A guide binding contains duplicate playlist references.') }
            if (-not $playlistByKey.ContainsKey($playlistKey)) { throw [System.ArgumentException]::new('A guide binding references an unknown playlist.') }
            $playlistKeysForBinding += $playlistKey
        }
        if (-not $bindingProperties.ContainsKey('appliesToAll') -or
            $bindingProperties['appliesToAll'].ValueKind -notin @([System.Text.Json.JsonValueKind]::True, [System.Text.Json.JsonValueKind]::False)) {
            throw [System.ArgumentException]::new('A guide binding must declare appliesToAll.')
        }
        $appliesToAll = $bindingProperties['appliesToAll'].GetBoolean()
        if ($appliesToAll -and $playlistKeysForBinding.Count -gt 0) { throw [System.ArgumentException]::new('ALL/shared bindings cannot list playlist references.') }
        if (-not $appliesToAll -and $playlistKeysForBinding.Count -eq 0) { throw [System.ArgumentException]::new('A non-ALL guide binding must select at least one playlist.') }
        $sortedPlaylistKeys = @($playlistKeysForBinding | Sort-Object)
        $effectiveKey = "$guideKey|$appliesToAll|$($sortedPlaylistKeys -join ',')"
        if (-not $effectiveBindings.Add($effectiveKey)) { throw [System.ArgumentException]::new('Duplicate effective guide binding is not allowed.') }
        $bindings += [pscustomobject][ordered]@{
            GuideKey    = $guideKey
            GuideId     = [string]$guideByKey[$guideKey].SourceId
            PlaylistKeys = $sortedPlaylistKeys
            PlaylistIds = @($sortedPlaylistKeys | ForEach-Object { [string]$playlistByKey[$_].SourceId })
            AppliesToAll = $appliesToAll
            Revision    = 1
            Enabled     = $true
        }
    }


    return [pscustomobject][ordered]@{
        SchemaVersion = 2
        Legacy = $false
        Playlists = @($playlists)
        Guides = @($guides)
        Bindings = @($bindings)
        AggregateSourceBytes = [int64]$aggregate.Value
    }
}

function Read-ChannelForgeGuidedSetupRemoteBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][int]$MaxBytes
    )

    $opened = $null
    $memory = $null
    try {
        $source = [pscustomobject]@{ Name = "guided-$Kind"; Url = $Url; ProviderId = 'guided-setup' }
        $opened = if ($Kind -eq 'M3U') {
            Open-ChannelForgeRemoteM3USourceStream -Source $source -MaxDocumentBytes $MaxBytes -MaxRawResponseBytes 16MB
        }
        else {
            Open-ChannelForgeRemoteXmltvSourceStream -Source $source -MaxDocumentBytes $MaxBytes -MaxRawResponseBytes 16MB
        }
        $memory = [System.IO.MemoryStream]::new()
        $opened.Stream.CopyTo($memory)
        $bytes = $memory.ToArray()
        if ($bytes.Length -eq 0) { throw "The remote $Kind source is empty." }
        if ($bytes.Length -gt $MaxBytes) { throw "The remote $Kind source is too large." }
        return [byte[]]$bytes
    }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $opened) {
            if ($null -ne $opened.Stream) { try { $opened.Stream.Dispose() } catch {} }
            foreach ($resource in @($opened.Resources)) { if ($null -ne $resource) { try { $resource.Dispose() } catch {} } }
        }
    }
}

function Write-ChannelForgeGuidedSetupStagedSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$RequestRoot,
        [Parameter(Mandatory)][int]$MaxBytes,
        [Parameter(Mandatory)][ValidateSet('playlists', 'guides')][string]$DirectoryName
    )

    $directory = Join-Path (Join-Path $RequestRoot 'sources') $DirectoryName
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $extension = if ([string]$Source.Kind -eq 'M3U') { 'm3u' } else { 'xml' }
    $relativePath = "sources/$DirectoryName/$([string]$Source.SourceId).$extension"
    $path = Join-Path $RequestRoot ($relativePath -replace '/', '\')
    $bytes = if ([string]$Source.SourceKind -eq 'managed-file') {
        [byte[]]$Source.Bytes
    }
    else {
        try {
            Read-ChannelForgeGuidedSetupRemoteBytes -Kind ([string]$Source.Kind) -Url ([string]$Source.Url) -MaxBytes $MaxBytes
        }
        catch {
            $_.Exception.Data['ChannelForgeGuidedSetupErrorCode'] = 'source-unavailable'
            throw
        }
    }
    if ($null -eq $bytes -or $bytes.Length -eq 0) { throw "The $($Source.Kind) source is empty." }
    if ($bytes.Length -gt $MaxBytes) { throw "The $($Source.Kind) source is too large." }
[IO.File]::WriteAllBytes($path, $bytes)
    $contentDomain = if ([string]$Source.Kind -eq 'M3U') { 'input-m3u/v2' } else { 'input-xmltv/v2' }
    return [pscustomobject][ordered]@{
        Kind = [string]$Source.Kind
        SourceId = [string]$Source.SourceId
        SourceKey = [string]$Source.SourceKey
        SourceKind = [string]$Source.SourceKind
        Label = [string]$Source.Label
        Priority = [int]$Source.Priority
        Url = if ([string]$Source.SourceKind -eq 'public-https') { [string]$Source.Url } else { $null }
        Path = [System.IO.Path]::GetFullPath($path)
        RelativePath = $relativePath
        ContentHash = Get-ChannelForgeDomainHash -Domain $contentDomain -Bytes $bytes
        ByteLength = [int]$bytes.Length
    }
}

function Write-ChannelForgeGuidedSetupSourceStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$RequestRoot,
        [Parameter(Mandatory)]$Limits
    )

    $aggregate = [int64]0
    $playlists = @()
    foreach ($source in @($Request.Playlists)) {
        $record = Write-ChannelForgeGuidedSetupStagedSource -Source $source -RequestRoot $RequestRoot -MaxBytes $Limits.MaxM3UBytes -DirectoryName 'playlists'
        $aggregate += [int64]$record.ByteLength
        if ($aggregate -gt $Limits.MaxAggregateSourceBytes) { throw [System.InvalidOperationException]::new('The aggregate source content is too large.') }
        $playlists += $record
    }
    $guides = @()
    foreach ($source in @($Request.Guides)) {
        $record = Write-ChannelForgeGuidedSetupStagedSource -Source $source -RequestRoot $RequestRoot -MaxBytes $Limits.MaxXMLTVBytes -DirectoryName 'guides'
        $aggregate += [int64]$record.ByteLength
        if ($aggregate -gt $Limits.MaxAggregateSourceBytes) { throw [System.InvalidOperationException]::new('The aggregate source content is too large.') }
        $guides += $record
    }
    return [pscustomobject][ordered]@{
        Playlists = $playlists
        Guides = $guides
        Bindings = @($Request.Bindings)
    }
}

function Get-ChannelForgeGuidedSetupSourceSetInputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Session
    )

    $proposalDirectory = Get-ChannelForgeWebProposalDirectory -RepositoryRoot $RepositoryRoot -ProposalId ([string]$Session.ProposalId)
    $sourceSet = $Session.SourceSet
    if ($null -eq $sourceSet) { throw 'FAIL_CLOSED: guided setup source-set metadata is missing.' }
    $makeSources = {
        param($Records, [string]$ExpectedDirectory, [string]$Kind, [int]$MaxBytes)
        $output = @()
        foreach ($record in @($Records)) {
            $relative = [string]$record.RelativePath
            if ($relative -notmatch "^sources/$ExpectedDirectory/[0-9a-f]{64}\.$(if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' })$") {
                throw 'FAIL_CLOSED: guided setup source reference is invalid.'
            }
            $path = Assert-ChannelForgeSourceEnrollmentPath -Path (Join-Path $proposalDirectory ($relative -replace '/', '\')) -AllowedRoot $proposalDirectory
            if (-not [IO.File]::Exists($path)) { throw 'FAIL_CLOSED: guided setup source bytes are unavailable.' }
            $bytes = [IO.File]::ReadAllBytes($path)
            if ($bytes.Length -eq 0 -or $bytes.Length -gt $MaxBytes) { throw 'FAIL_CLOSED: guided setup source bytes are invalid.' }
            if ($null -eq $record.ByteLength -or [int64]$bytes.Length -ne [int64]$record.ByteLength) {
                throw 'FAIL_CLOSED: guided setup source length changed.'
            }
            $contentDomain = if ($Kind -eq 'M3U') { 'input-m3u/v2' } else { 'input-xmltv/v2' }
            $actualContentHash = Get-ChannelForgeDomainHash -Domain $contentDomain -Bytes $bytes
            if ([string]$record.ContentHash -cne $actualContentHash) {
                throw 'FAIL_CLOSED: guided setup source bytes changed.'
            }
            $descriptor = [ordered]@{
                Kind = $Kind
                SourceId = [string]$record.SourceId
                SourceKey = [string]$record.SourceKey
                SourceKind = [string]$record.SourceKind
                Label = [string]$record.Label
                Priority = [int]$record.Priority
                Path = $path
                Url = if ([string]$record.SourceKind -eq 'public-https') { [string]$record.Url } else { $null }
                ContentHash = [string]$record.ContentHash
                ByteLength = [int64]$record.ByteLength
            }
            if ([string]$record.SourceKind -in @('managed-file', 'public-https')) {
                $descriptor.Bytes = $bytes
            }
            $output += [pscustomobject]$descriptor
        }
        return @($output)
    }

    $playlists = & $makeSources $sourceSet.Playlists 'playlists' 'M3U' 4MB
    $guides = & $makeSources $sourceSet.Guides 'guides' 'XMLTV' 12MB
    return [pscustomobject][ordered]@{
        PlaylistSources = @($playlists)
        GuideSources = @($guides)
        Bindings = @($sourceSet.Bindings | ForEach-Object {
            [pscustomobject][ordered]@{
                GuideId = [string]$_.GuideId
                PlaylistIds = @($_.PlaylistIds | ForEach-Object { [string]$_ })
                AppliesToAll = [bool]$_.AppliesToAll
                Revision = if ($null -eq $_.Revision) { 1 } else { [int]$_.Revision }
                Enabled = if ($null -eq $_.Enabled) { $true } else { [bool]$_.Enabled }
            }
        })
        StagedPaths = @(@($playlists.Path) + @($guides.Path) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
}
