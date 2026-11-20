function Set-ChannelForgeScheduleAnswer {
    <#
    .SYNOPSIS
    Saves your answer to a schedule question so the build does not ask it again.

    .DESCRIPTION
    Writes state\schedule-answers.json (contract schedule-answer/v1). The answer applies only while
    the evidence state (NoEvidence, GuideMissing or Review) stays the same. It changes what the
    build asks and prints. It never changes the guide, the playlist or any hash.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[^|\r\n]{1,200}$')][string]$ChannelId,
        [Parameter(Mandatory)][ValidateSet('NoEvidence', 'GuideMissing', 'Review')][string]$State,
        [Parameter(Mandatory)][ValidateSet('StillOn', 'Cancelled', 'NotSure')][string]$Answer,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $path = Join-Path $paths.StateRoot 'schedule-answers.json'
    $others = @(Read-ChannelForgeScheduleAnswers -Path $path | Where-Object { -not $_.key.StartsWith("$ChannelId|", [StringComparison]::Ordinal) })
    $new = $others + [pscustomobject][ordered]@{
        key        = "$ChannelId|$State"
        answer     = $Answer
        answeredAt = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    }
    if ($PSCmdlet.ShouldProcess($path, 'Save schedule answer')) {
        $document = [ordered]@{ version = 'schedule-answer/v1'; answers = @($new | Sort-Object { $_.key }) }
        Write-ChannelForgeSourceEnrollmentAtomicJson -Path $path -Value $document -AllowedRoot $paths.StateRoot
    }
}
