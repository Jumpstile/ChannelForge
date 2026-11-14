function Set-ChannelForgeCategoryOverride {
    <#
    .SYNOPSIS
    Saves, replaces or removes your category correction for one channel.

    .DESCRIPTION
    Writes state\category-overrides.json (contract category-quality/v1). Copy the
    ChannelKey from Get-ChannelForgeCategoryReport. Only the record for that key changes.
    A damaged overrides file stops the command; it is never repaired or replaced.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Set')]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ChannelKey,
        [Parameter(Mandatory, ParameterSetName = 'Set')][string]$Category,
        [Parameter(ParameterSetName = 'Set')][string]$Name = '',
        [Parameter(Mandatory, ParameterSetName = 'Clear')][switch]$Clear,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $path = Join-Path $paths.StateRoot 'category-overrides.json'
    $records = @(Read-ChannelForgeCategoryOverrides -Path $path)
    $others = @($records | Where-Object { $_.key -cne $ChannelKey })
    $existing = @($records | Where-Object { $_.key -ceq $ChannelKey }) | Select-Object -First 1

    if ($Clear) {
        if ($null -eq $existing) { Write-Warning 'That channel has no override. Nothing was written.'; return }
        $new = $others
    }
    else {
        $allowed = @(Get-ChannelForgeOneGuideCategoryRegistry | Where-Object { $_.Group -ne 'temporal' } | ForEach-Object { $_.Key })
        if ($allowed -cnotcontains $Category) { throw "Unknown category. Use one of: $($allowed -join ', '). Nothing was written." }
        $label = if ($Name) { $Name } elseif ($existing) { $existing.name } else { '' }
        $new = $others + [pscustomobject][ordered]@{
            key       = $ChannelKey
            name      = ConvertTo-ChannelForgeGuideSafeText -Value $label
            category  = $Category
            decidedAt = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        }
    }

    if ($PSCmdlet.ShouldProcess($path, 'Save category overrides')) {
        $document = [ordered]@{ version = 'category-quality/v1'; overrides = @($new | Sort-Object { $_.key }) }
        Write-ChannelForgeSourceEnrollmentAtomicJson -Path $path -Value $document -AllowedRoot $paths.StateRoot
    }
}
