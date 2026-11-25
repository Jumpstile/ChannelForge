function Write-ChannelForgeMatchEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Evidence,
        [AllowEmptyCollection()][string[]]$KeepGenerationId = @()
    )

    # Writes state\accepted-evidence\<GenerationId>.json (temp file, then swap), then removes
    # evidence files of older generations. Only files named like a generation id are touched.
    $idPattern = '^[0-9a-f]{64}$'
    $generationId = [string]$Evidence.generationId
    if ($generationId -cnotmatch $idPattern) { throw 'FAIL_CLOSED: match evidence generation id is invalid.' }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Evidence -Depth 5))
    if ($bytes.Length -gt 32MB) { throw 'FAIL_CLOSED: match evidence is too large.' }
    $directory = Join-Path (Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot).StateRoot 'accepted-evidence'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $path = Join-Path $directory "$generationId.json"
    $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllBytes($temp, $bytes)
        Move-Item -LiteralPath $temp -Destination $path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    $keep = @($generationId) + @($KeepGenerationId | Where-Object { $_ })
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json')) {
        if ($file.BaseName -cmatch $idPattern -and $file.BaseName -cnotin $keep) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
    }
}
