function Clear-ChannelForgeScheduleAnswer {
    <#
    .SYNOPSIS
    Removes your saved answer for one event channel so the build asks again.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[^|\r\n]{1,200}$')][string]$ChannelId,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $path = Join-Path $paths.StateRoot 'schedule-answers.json'
    $records = @(Read-ChannelForgeScheduleAnswers -Path $path)
    $others = @($records | Where-Object { -not $_.key.StartsWith("$ChannelId|", [StringComparison]::Ordinal) })
    if ($others.Count -eq $records.Count) { Write-Warning 'That channel has no saved answer. Nothing was written.'; return }
    if ($PSCmdlet.ShouldProcess($path, 'Clear schedule answer')) {
        $document = [ordered]@{ version = 'schedule-answer/v1'; answers = @($others | Sort-Object { $_.key }) }
        Write-ChannelForgeSourceEnrollmentAtomicJson -Path $path -Value $document -AllowedRoot $paths.StateRoot
    }
}
