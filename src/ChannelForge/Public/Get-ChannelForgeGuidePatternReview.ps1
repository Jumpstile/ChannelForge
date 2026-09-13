function Get-ChannelForgeGuidePatternReview {
    <#
    .SYNOPSIS
    Creates a beginner-readable, read-only review of a Stage B event-pattern result.

    .DESCRIPTION
    Projects the technical Stage B inference result into a bounded review report.
    The default object is machine-readable, while Json and Markdown formats are
    available for automation and a human review surface. The command never writes
    files, publishes a guide, accepts a rule, or changes provider/downstream state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [object]$InferenceResult,

        [ValidateSet('Object', 'Json', 'Markdown')]
        [string]$OutputFormat = 'Object'
    )

    if ($null -eq $InferenceResult) {
        throw 'InferenceResult cannot be null.'
    }

    $report = ConvertTo-ChannelForgeGuidePatternReviewReport -InferenceResult $InferenceResult
    switch ($OutputFormat) {
        'Json' { return ($report | ConvertTo-Json -Depth 20 -Compress) }
        'Markdown' { return (ConvertTo-ChannelForgeGuidePatternReviewMarkdown -Report $report) }
        default { return $report }
    }
}
