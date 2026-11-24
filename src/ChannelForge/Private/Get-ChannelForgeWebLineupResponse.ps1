$script:ChannelForgeLineupProjectionCache = $null

function Read-ChannelForgeWebAcceptedPointer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)]$Paths)

    $pointer = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $Paths.Current -Domain 'pointer/v2'
    Assert-ChannelForgeGenerationPropertySequence $pointer.Object @('Version', 'GenerationId', 'GenerationManifestHash', 'AcceptedStateHash', 'AcceptedOutputManifestHash', 'PointerHash') 'Pointer'
    Assert-ChannelForgeGenerationHash $pointer.Object.PointerHash 'PointerHash'
    Assert-ChannelForgeGenerationId ([string]$pointer.Object.GenerationId)
    if (-not (Test-ChannelForgeGenerationProjectionHash $pointer.Object 'pointer/v2' 'PointerHash')) { throw 'FAIL_CLOSED: current pointer hash is invalid.' }
    return $pointer
}

function Get-ChannelForgeWebAcceptedKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)]$Pointer)

    return @(
        [IO.Path]::GetFullPath($RepositoryRoot),
        [string]$Pointer.GenerationId,
        [string]$Pointer.GenerationManifestHash,
        [string]$Pointer.AcceptedStateHash,
        [string]$Pointer.AcceptedOutputManifestHash,
        [string]$Pointer.PointerHash
    ) -join '|'
}

function Get-ChannelForgeWebLineupHash {
    param([Parameter(Mandatory)][string]$Text)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Get-ChannelForgeWebLineupText {
    param([AllowNull()][string]$Text, [int]$MaximumLength = 120)

    $value = ([string]$Text).Trim()
    if ($value.Length -gt $MaximumLength) { return $value.Substring(0, $MaximumLength) }
    return $value
}

function Get-ChannelForgeWebLineupProgrammeIndex {
    param([AllowNull()]$Snapshot)

    $index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    if ($null -eq $Snapshot.XMLTV) { return $index }
    $bytes = [byte[]]$Snapshot.XMLTV.Bytes
    if ($bytes.Length -gt 268435456) { throw 'Accepted guide exceeds the read projection limit.' }
    $stream = [System.IO.MemoryStream]::new($bytes, $false)
    try {
        $programmes = @(Read-ChannelForgeXmltvDocument `
            -Stream $stream `
            -SourceId 'accepted-guide' `
            -SourcePath $Snapshot.XMLTV.Path `
            -SourceKind local `
            -MaxDocumentBytes 268435456 `
            -CandidateContractVersion 'blocker-2-contract/v8')
    }
    finally { $stream.Dispose() }
    # The accepted guide rewrites channel ids; channelforge:channel-reference keeps the playlist tvg-id (as in Read-ChannelForgeProgrammeTitles).
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.MemoryStream]::new($bytes, $false), $settings)
    try { $document = [System.Xml.XmlDocument]::new(); $document.Load($xmlReader) }
    finally { $xmlReader.Dispose() }
    $referenceById = [hashtable]::new([StringComparer]::Ordinal)
    foreach ($node in $document.SelectNodes('/tv/channel')) {
        $reference = @($node.ChildNodes | Where-Object { $_.LocalName -ceq 'channel-reference' }) | Select-Object -First 1
        if ($reference) { $referenceById[[string]$node.GetAttribute('id')] = [string]$reference.InnerText }
    }
    $lists = [hashtable]::new([StringComparer]::Ordinal)
    foreach ($programme in $programmes) {
        $id = [string]$programme.RawChannelId
        if ($referenceById.ContainsKey($id)) { $id = $referenceById[$id] }
        if (-not $lists.ContainsKey($id)) { $lists[$id] = [System.Collections.Generic.List[object]]::new() }
        $lists[$id].Add($programme)
    }
    foreach ($id in $lists.Keys) { $index[[string]$id] = @($lists[$id] | Sort-Object -Property Start) }
    return $index
}

function Get-ChannelForgeWebLineupRows {
    param([Parameter(Mandatory)]$Snapshot)

    $reader = [System.IO.StringReader]::new([Text.Encoding]::UTF8.GetString([byte[]]$Snapshot.M3U.Bytes))
    try { $channels = @(Read-ChannelForgeM3UReader -Reader $reader) }
    finally { $reader.Dispose() }
    $ordinal = 0
    return @(
        foreach ($channel in $channels) {
            $ordinal++
            $name = Get-ChannelForgeWebLineupText $channel.DisplayName
            $number = 0
            $attention = [System.Collections.Generic.List[string]]::new()
            $guideKey = [string]$channel.TvgId
            if ([string]::IsNullOrWhiteSpace($guideKey)) { $attention.Add('no-guide') }
            if ([string]::IsNullOrWhiteSpace([string]$channel.Logo)) { $attention.Add('no-logo') }
            [pscustomobject][ordered]@{
                Id = Get-ChannelForgeWebLineupHash "lineup-channel/v1|$ordinal|$name"
                Number = if ([int]::TryParse([string]$channel.RawChannelNumber, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { $number } else { $null }
                Name = $name
                Group = Get-ChannelForgeWebLineupText $channel.Group
                LogoStatus = if ($attention.Contains('no-logo')) { 'missing' } else { 'present' }
                GuideState = if ($attention.Contains('no-guide')) { 'none' } else { 'bound' }
                Attention = @($attention)
                GuideKey = $guideKey
            }
        }
    )
}

function Get-ChannelForgeWebLineupProjection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    if (-not [IO.File]::Exists($paths.Current)) {
        $script:ChannelForgeLineupProjectionCache = $null
        throw 'Accepted lineup is unavailable because no accepted generation exists.'
    }
    $pointer = Read-ChannelForgeWebAcceptedPointer -RepositoryRoot $RepositoryRoot -Paths $paths
    $key = Get-ChannelForgeWebAcceptedKey -RepositoryRoot $RepositoryRoot -Pointer $pointer.Object
    if ($null -ne $script:ChannelForgeLineupProjectionCache -and [string]$script:ChannelForgeLineupProjectionCache.Key -ceq $key) {
        return $script:ChannelForgeLineupProjectionCache
    }
    $snapshot = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths
    if ($null -eq $snapshot) {
        $script:ChannelForgeLineupProjectionCache = $null
        throw 'Accepted lineup is unavailable because the accepted generation could not be loaded.'
    }
    if ((Get-ChannelForgeWebAcceptedKey -RepositoryRoot $RepositoryRoot -Pointer $snapshot.Pointer.Object) -cne $key) {
        throw 'Accepted generation changed while the lineup projection was loading.'
    }
    $script:ChannelForgeLineupProjectionCache = [pscustomobject]@{
        Key = $key
        # Opaque snapshot token for paging pins; derived so the accepted pointer hash itself is never exposed.
        GenerationToken = Get-ChannelForgeWebLineupHash "lineup-page-snapshot/v1|$key"
        Rows = @(Get-ChannelForgeWebLineupRows -Snapshot $snapshot)
        Programmes = Get-ChannelForgeWebLineupProgrammeIndex -Snapshot $snapshot
    }
    return $script:ChannelForgeLineupProjectionCache
}

function Get-ChannelForgeWebLineupProgramme {
    param([AllowNull()]$Programme)

    if ($null -eq $Programme) { return $null }
    return [ordered]@{
        title = Get-ChannelForgeWebLineupText $Programme.Title
        startUtc = ([datetimeoffset]$Programme.Start).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        stopUtc = ([datetimeoffset]$Programme.End).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    }
}

# programmeState: current, gap (next exists, nothing airing), stale (guide ended), no-programme (guide id has none), no-guide.
function Get-ChannelForgeWebLineupItem {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)]$ProgrammeIndex, [Parameter(Mandatory)][datetimeoffset]$Now, [AllowNull()]$Window = $null, [AllowNull()]$PinnedIds = $null)

    $current = $null
    $next = $null
    $state = 'no-guide'
    $list = @()
    if ($Row.GuideState -ceq 'bound') {
        if ($ProgrammeIndex.ContainsKey($Row.GuideKey)) { $list = @($ProgrammeIndex[$Row.GuideKey]) }
        $current = $list | Where-Object { $_.Start -le $Now -and $_.End -gt $Now } | Select-Object -First 1
        $next = $list | Where-Object { $_.Start -gt $Now } | Select-Object -First 1
        $state = if ($list.Count -eq 0) { 'no-programme' } elseif ($null -ne $current) { 'current' } elseif ($null -ne $next) { 'gap' } else { 'stale' }
    }
    $item = [ordered]@{
        id = $Row.Id
        number = $Row.Number
        name = $Row.Name
        group = $Row.Group
        logoStatus = if ($null -ne $PinnedIds -and $Row.LogoStatus -ceq 'present' -and $PinnedIds.Contains($Row.GuideKey)) { 'pinned' } else { $Row.LogoStatus }
        guideState = $Row.GuideState
        attention = @($Row.Attention)
        programmeState = $state
        current = Get-ChannelForgeWebLineupProgramme $current
        next = Get-ChannelForgeWebLineupProgramme $next
    }
    # Only a from/to request adds programmes (every accepted programme that overlaps the window); the default response is unchanged.
    if ($null -ne $Window) {
        $item.programmes = @($list | Where-Object { $_.Start -lt $Window.To -and $_.End -gt $Window.From } | ForEach-Object { Get-ChannelForgeWebLineupProgramme $_ })
    }
    return $item
}

# Optional UTC schedule window: from and to together, to after from, at most 3 hours. Returns $null when neither is given.
function Get-ChannelForgeWebLineupWindow {
    # Untyped on purpose: a [string] parameter would turn a missing (null) bound into an empty string.
    param([AllowNull()]$From, [AllowNull()]$To)

    if ($null -eq $From -and $null -eq $To) { return $null }
    if ($null -eq $From -or $null -eq $To) { throw 'Lineup window needs both from and to.' }
    $bounds = foreach ($text in $From, $To) {
        $parsed = [datetimeoffset]::MinValue
        if ($text -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or -not [datetimeoffset]::TryParseExact($text, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { throw 'Lineup window times must be UTC like 2026-01-01T00:00:00Z.' }
        $parsed
    }
    $span = $bounds[1] - $bounds[0]
    if ($span -le [timespan]::Zero -or $span -gt [timespan]::FromHours(3)) { throw 'Lineup window must be longer than zero and at most 3 hours.' }
    return [pscustomobject]@{ From = $bounds[0]; To = $bounds[1] }
}

function Get-ChannelForgeWebLineupQuery {
    param([AllowEmptyString()][string]$QueryString = '')

    if ($QueryString.Length -gt 300) { throw 'Lineup query is too long.' }
    $query = [ordered]@{ Limit = 100; Offset = 0; Generation = $null; Group = $null; NeedsReview = $false; Search = $null; Window = $null }
    $windowFrom = $null
    $windowTo = $null
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrEmpty($QueryString)) {
        foreach ($part in $QueryString.Split('&')) {
            $pair = $part.Split('=', 2)
            if ($pair.Length -ne 2 -or [string]::IsNullOrWhiteSpace($pair[0]) -or -not $seen.Add($pair[0])) { throw 'Lineup query parameters are invalid.' }
            $text = [Uri]::UnescapeDataString($pair[1].Replace('+', ' '))
            $value = [long]0
            switch ($pair[0].ToLowerInvariant()) {
                'generation' {
                    if ($pair[1] -cnotmatch '^[a-f0-9]{64}$') { throw 'Lineup generation is invalid.' }
                    $query.Generation = $pair[1]
                }
                'group' {
                    if ($text.Length -lt 1 -or $text.Length -gt 120) { throw 'Lineup group is invalid.' }
                    $query.Group = $text
                }
                'search' {
                    if ($text.Length -lt 1 -or $text.Length -gt 64) { throw 'Lineup search is invalid.' }
                    $query.Search = $text
                }
                'attention' {
                    if ($text -cnotin @('all', 'needs-review')) { throw 'Lineup attention filter is unsupported.' }
                    $query.NeedsReview = ($text -ceq 'needs-review')
                }
                { $_ -in @('from', 'to') } {
                    if ($_ -eq 'from') { $windowFrom = $text } else { $windowTo = $text }
                }
                { $_ -in @('limit', 'offset') } {
                    if (-not [long]::TryParse($pair[1], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { throw 'Lineup query values must be decimal integers.' }
                    if ($_ -eq 'limit') {
                        if ($value -lt 1 -or $value -gt 100) { throw 'Lineup limit is outside the supported range.' }
                        $query.Limit = [int]$value
                    }
                    else {
                        if ($value -gt [int]::MaxValue) { throw 'Lineup offset is outside the supported range.' }
                        $query.Offset = [int]$value
                    }
                }
                default { throw 'Lineup query parameters are unsupported.' }
            }
        }
    }
    $query.Window = Get-ChannelForgeWebLineupWindow -From $windowFrom -To $windowTo
    if ($query.Offset -gt 0 -and $null -eq $query.Generation) { throw 'Lineup pages after the first require the generation cursor.' }
    return [pscustomobject]$query
}

function Get-ChannelForgeWebLineupResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [Parameter(Mandatory)][string]$ContentType,
        [AllowEmptyString()][string]$QueryString = ''
    )

    try { $query = Get-ChannelForgeWebLineupQuery -QueryString $QueryString }
    catch {
        return New-ChannelForgeWebResponse -StatusCode 400 -ContentType $ContentType -Body (@{ Error = 'invalid-query'; Message = 'Lineup query parameters are invalid.' } | ConvertTo-Json -Compress) -Headers $Headers
    }
    try {
        $projection = Get-ChannelForgeWebLineupProjection -RepositoryRoot $RepositoryRoot
        if ($null -ne $query.Generation -and $query.Generation -cne $projection.GenerationToken) {
            return New-ChannelForgeWebResponse -StatusCode 409 -ContentType $ContentType -Body (@{ Error = 'generation-changed'; Message = 'The accepted lineup changed; reload from the first page.' } | ConvertTo-Json -Compress) -Headers $Headers
        }
        $rows = @($projection.Rows)
        if ($null -ne $query.Group) { $rows = @($rows | Where-Object { $_.Group -ceq $query.Group }) }
        if ($query.NeedsReview) { $rows = @($rows | Where-Object { $_.Attention.Count -gt 0 }) }
        if ($null -ne $query.Search) { $rows = @($rows | Where-Object { $_.Name.IndexOf($query.Search, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
        $now = [datetimeoffset]::FromUnixTimeMilliseconds([datetimeoffset]::UtcNow.ToUnixTimeMilliseconds())
        # Pins live in state\logo-pins.json and change on their own, so they are read per request (never cached with the accepted lineup). A missing or corrupt file means no pin is shown.
        $pins = Read-ChannelForgeLogoPin -RepositoryRoot $RepositoryRoot
        $pinnedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        if ($pins.Status -ceq 'Ok') { foreach ($pin in $pins.Pins) { [void]$pinnedIds.Add([string]$pin.TvgId) } }
        $items = @($rows | Select-Object -Skip $query.Offset -First $query.Limit | ForEach-Object { Get-ChannelForgeWebLineupItem -Row $_ -ProgrammeIndex $projection.Programmes -Now $now -Window $query.Window -PinnedIds $pinnedIds })
        $body = ConvertTo-Json -InputObject ([ordered]@{
                version = 'lineup-workspace/channel/v1'
                generation = $projection.GenerationToken
                evaluatedAtUtc = $now.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
                total = $rows.Count
                offset = $query.Offset
                limit = $query.Limit
                count = $items.Count
                items = $items
            }) -Depth 6 -Compress
        $responseHeaders = [ordered]@{}
        foreach ($key in $Headers.Keys) { $responseHeaders[$key] = $Headers[$key] }
        $responseHeaders['X-ChannelForge-Generation'] = [string]$projection.GenerationToken
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType $ContentType -Body $body -Headers $responseHeaders
    }
    catch {
        return New-ChannelForgeWebResponse -StatusCode 503 -ContentType $ContentType -Body (@{
            Error = 'lineup-unavailable'
            Message = 'The accepted lineup is temporarily unavailable.'
        } | ConvertTo-Json -Compress) -Headers $Headers
    }
}
