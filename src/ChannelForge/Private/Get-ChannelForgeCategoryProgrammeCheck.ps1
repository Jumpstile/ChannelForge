function Get-ChannelForgeProgrammeTitleCategory {
    # The one category a programme title points at, or nothing. A generic Sports word is
    # not enough, and a title that points at two categories is not classified.
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Title = '', [Parameter(Mandatory)][object[]]$Registry)

    $hits = @(Find-ChannelForgeCategoryWord -Text $Title -Registry $Registry -Property NameTokens) +
        @(Find-ChannelForgeCategoryWord -Text $Title -Registry $Registry -Property Aliases)
    $keys = @($hits | ForEach-Object { $_.Key } | Where-Object { $_ -cne 'other-sports' } | Select-Object -Unique)
    if ($keys.Count -eq 1) { return $keys[0] }
}

function Read-ChannelForgeProgrammeTitles {
    # Guide channel id (channelforge:channel-reference) -> its first programme titles, file order.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [int]$SampleSize = 20)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $xmlReader = [System.Xml.XmlReader]::Create($Path, $settings)
    try { $document = [System.Xml.XmlDocument]::new(); $document.Load($xmlReader) }
    finally { $xmlReader.Dispose() }

    $referenceById = @{}
    foreach ($node in $document.SelectNodes('/tv/channel')) {
        $reference = @($node.ChildNodes | Where-Object { $_.LocalName -ceq 'channel-reference' }) | Select-Object -First 1
        if ($reference) { $referenceById[[string]$node.GetAttribute('id')] = [string]$reference.InnerText }
    }
    $titles = @{}
    foreach ($node in $document.SelectNodes('/tv/programme')) {
        $reference = $referenceById[[string]$node.GetAttribute('channel')]
        if ($null -eq $reference) { continue }
        if (-not $titles.ContainsKey($reference)) { $titles[$reference] = [System.Collections.Generic.List[string]]::new() }
        if ($titles[$reference].Count -lt $SampleSize) { $titles[$reference].Add([string]$node.SelectSingleNode('title').InnerText) }
    }
    return $titles
}

function Get-ChannelForgeCategoryProgrammeCheck {
    # category-programme-check/v1: names of channels (with a category) whose programme titles
    # mostly point at another category. Needs 3 classified titles out of the first 20, and a
    # simple majority. Report only; reads the candidate and changes nothing.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][object]$Report
    )

    $registry = @(Get-ChannelForgeOneGuideCategoryRegistry)
    $groupOf = @{}
    foreach ($entry in $registry) { $groupOf[[string]$entry.Key] = [string]$entry.Group }
    $categoryOf = @{}
    foreach ($row in $Report.Rows) { if ($null -ne $row.Category) { $categoryOf[[string]$row.ChannelKey] = [string]$row.Category } }
    $guidePath = Join-Path $CandidateDirectory 'merged.xml'
    if (-not (Test-Path -LiteralPath $guidePath -PathType Leaf)) { return }
    $titlesOf = Read-ChannelForgeProgrammeTitles -Path $guidePath

    foreach ($channel in @(Read-ChannelForgeCandidateChannels -Directory $CandidateDirectory)) {
        $category = $categoryOf[(Get-ChannelForgeChannelKey -Url ([string]$channel.Url))]
        $titles = $titlesOf[[string]$channel.TvgId]
        if ($null -eq $category -or $null -eq $titles) { continue }

        $found = @($titles | ForEach-Object { Get-ChannelForgeProgrammeTitleCategory -Title $_ -Registry $registry })
        if ($found.Count -lt 3) { continue }
        $top = @($found | Group-Object | Sort-Object Count -Descending) | Select-Object -First 1
        if ($top.Count * 2 -le $found.Count -or $top.Name -ceq $category) { continue }
        if ($category -ceq 'other-sports' -and $groupOf[$top.Name] -ceq 'sports') { continue }
        ConvertTo-ChannelForgeGuideSafeText -Value $channel.DisplayName
    }
}
