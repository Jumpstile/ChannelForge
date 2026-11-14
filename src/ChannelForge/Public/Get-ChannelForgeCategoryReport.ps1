function Get-ChannelForgeCategoryReport {
    <#
    .SYNOPSIS
    Shows the category, confidence and plain reason for every channel of a candidate.

    .DESCRIPTION
    Read-only report (contract category-quality/v1). Reads merged.m3u from a sealed
    candidate directory and any corrections in state\category-overrides.json. It never
    changes the candidate, a channel, a group-title or the overrides file. The report is
    returned and also saved as output\category-reports\<candidate-hash>.json.
    A damaged candidate or overrides file stops the command and nothing is written.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $directory = [System.IO.Path]::GetFullPath($CandidateDirectory).TrimEnd([char]92, [char]47)
    $hash = Split-Path -Leaf $directory
    if (-not (Test-ChannelForgeCandidateNamespace -Directory $directory -ManifestHash $hash)) {
        throw 'The candidate directory is not a valid sealed candidate. Nothing was written.'
    }
    $m3uPath = Join-Path $directory 'merged.m3u'
    if (-not (Test-Path -LiteralPath $m3uPath -PathType Leaf)) {
        throw 'The candidate has no merged.m3u, so there are no channels to sort. Nothing was written.'
    }

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $overridePath = Join-Path $paths.StateRoot 'category-overrides.json'
    $records = @(Read-ChannelForgeCategoryOverrides -Path $overridePath)
    $overrideMap = @{}
    foreach ($record in $records) { $overrideMap[$record.key] = $record.category }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $manifest = $utf8.GetString([System.IO.File]::ReadAllBytes((Join-Path $directory 'manifest.json'))) | ConvertFrom-Json
    $reader = [System.IO.StreamReader]::new($m3uPath, $utf8)
    try { $channels = @(Read-ChannelForgeM3UReader -Reader $reader -CandidateContractVersion ([string]$manifest.ContractVersion)) }
    finally { $reader.Dispose() }

    $registry = @(Get-ChannelForgeOneGuideCategoryRegistry)
    $rows = @(foreach ($channel in $channels) {
            $key = Get-ChannelForgeChannelKey -Url ([string]$channel.Url)
            $name = ConvertTo-ChannelForgeGuideSafeText -Value $channel.DisplayName
            $group = ConvertTo-ChannelForgeGuideSafeText -Value $channel.Group
            $decision = Get-ChannelForgeChannelCategory -Name $name -ProviderGroup $group -Key $key -Override $overrideMap -Registry $registry
            [pscustomobject][ordered]@{
                ChannelKey    = $key
                DisplayName   = $name
                ProviderGroup = $group
                Category      = $decision.Category
                Confidence    = $decision.Confidence
                Decision      = $decision.Decision
                Reason        = $decision.Reason
            }
        })

    $perCategory = [ordered]@{}
    foreach ($entry in $registry) { $perCategory[$entry.Key] = @($rows | Where-Object { $_.Category -ceq $entry.Key }).Count }
    $channelKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($rows | ForEach-Object { $_.ChannelKey }), [System.StringComparer]::Ordinal)
    $stale = @($records | Where-Object { -not $channelKeys.Contains($_.key) } | ForEach-Object {
            [pscustomobject][ordered]@{ Key = $_.key; Name = $_.name; Category = $_.category }
        })
    $applied = @($rows | Where-Object { $_.Decision -ceq 'override' }).Count

    $report = [pscustomobject][ordered]@{
        Contract              = 'category-quality/v1'
        CandidateManifestHash = $hash
        ChannelCount          = $rows.Count
        Summary               = [pscustomobject][ordered]@{
            Categories       = [pscustomobject]$perCategory
            Ungrouped        = @($rows | Where-Object { $null -eq $_.Category }).Count
            High             = @($rows | Where-Object { $_.Confidence -ceq 'high' }).Count
            Medium           = @($rows | Where-Object { $_.Confidence -ceq 'medium' }).Count
            None             = @($rows | Where-Object { $_.Confidence -ceq 'none' }).Count
            OverridesApplied = $applied
            OverridesStale   = $stale.Count
        }
        Overrides             = [pscustomobject][ordered]@{
            File    = if (Test-Path -LiteralPath $overridePath -PathType Leaf) { 'Loaded' } else { 'Absent' }
            Applied = $applied
            Stale   = $stale
        }
        Rows                  = $rows
    }

    $reportDirectory = [System.IO.Directory]::CreateDirectory((Join-Path $paths.RepositoryRoot 'output\category-reports')).FullName
    $reportPath = Join-Path $reportDirectory "$hash.json"
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path $reportPath -Value $report -AllowedRoot (Join-Path $paths.RepositoryRoot 'output')
    return $report
}
