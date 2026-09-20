function Get-ChannelForgeWebSourceRefreshResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [string]$ContentType = 'application/json'
    )

    if (-not [string]::IsNullOrWhiteSpace($ContentType) -and $ContentType.Split(';', 2)[0].Trim().ToLowerInvariant() -ne 'application/json') {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 415 -ErrorCode 'unsupported-content-type' -Message 'The refresh request must use application/json.' -Headers $Headers
    }

    $status = Get-ChannelForgeSourceEnrollmentStatus -RepositoryRoot $RepositoryRoot
    if (-not [bool]$status.HasSavedSources) {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 409 -ErrorCode 'sources-not-saved' -Message 'Save local sources in Guided Setup before refreshing.' -Headers $Headers
    }
    if (-not [bool]$status.CanRefresh) {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 409 -ErrorCode 'sources-unavailable' -Message 'Saved sources need attention before refresh can continue.' -Headers $Headers
    }

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $scriptPath = Join-Path (Get-ChannelForgeWebRepositoryRoot) 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
    $enrollmentPath = Join-Path $root 'state/source-enrollment.json'
    $outputRoot = Join-Path $root 'output/.web-guided-setup/source-refresh'
    try {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        & $pwsh -NoProfile -File $scriptPath -Root $root -EnrollmentPath $enrollmentPath -OutputRoot $outputRoot -EvaluationTimeUtc ([datetimeoffset]::UtcNow) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'refresh process failed' }
        $jsonPath = Join-Path $outputRoot 'source-refresh-result.json'
        if (-not [IO.File]::Exists($jsonPath)) { throw 'refresh report was not produced' }
        $report = Get-Content -LiteralPath $jsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $rows = @($report.Sources | ForEach-Object {
            [ordered]@{
                Name = [string]$_.Name
                Result = [string]$_.Result
                Classification = [string]$_.Classification
                SafeReason = [string]$_.SafeReason
            }
        })
        $body = [ordered]@{
            Version = 'source-refresh/v1'
            Status = if ([bool]$report.ReviewNeeded) { 'CHANGES_FOUND' } else { 'UP_TO_DATE' }
            ReviewNeeded = [bool]$report.ReviewNeeded
            ReviewNeededCount = [int]$report.ReviewNeededCount
            Sources = $rows
            Safety = [ordered]@{ AcceptedStateMutation = 'none'; ProviderMutation = 'none'; DownstreamMutation = 'none'; CandidatePublication = 'review-only' }
        } | ConvertTo-Json -Depth 6 -Compress
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body $body -Headers $Headers
    }
    catch {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 422 -ErrorCode 'refresh-unavailable' -Message 'Saved sources could not be refreshed safely. The accepted lineup was not changed.' -Headers $Headers
    }
}
