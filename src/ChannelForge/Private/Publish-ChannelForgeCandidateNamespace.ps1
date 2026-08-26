function Publish-ChannelForgeCandidateNamespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputRoot,

        [Parameter(Mandatory)]
        [string]$StagingPath,
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{64}$')]
        [string]$CandidateManifestHash,

        [string]$FaultHook = ''
    )
    $candidateRoot = Join-Path $OutputRoot 'candidates'
    $finalPath = Join-Path $candidateRoot $CandidateManifestHash
    Assert-ChannelForgeWritePath -Path $candidateRoot -AllowedRoot $OutputRoot
    Assert-ChannelForgeWritePath -Path $StagingPath -AllowedRoot $OutputRoot
    Assert-ChannelForgeWritePath -Path $finalPath -AllowedRoot $OutputRoot
    New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
    if (-not (Test-ChannelForgeCandidateNamespace -Directory $StagingPath -ManifestHash $CandidateManifestHash -AllowStagingName)) {
        throw 'Candidate namespace staging validation failed.'
    }

    if (Test-Path -LiteralPath $finalPath) {
        if (-not (Test-ChannelForgeCandidateNamespace -Directory $finalPath -ManifestHash $CandidateManifestHash)) {
            throw "Candidate namespace collision failed final validation: $finalPath"
        }
        if (-not (Test-Path -LiteralPath $finalPath -PathType Container)) {
            throw "Candidate namespace collision is not a directory: $finalPath"
        }

        $existingFiles = @(Get-ChildItem -LiteralPath $finalPath -File -Recurse | ForEach-Object {
                $_.FullName.Substring($finalPath.Length).TrimStart([char[]]@('\', '/'))
            } | Sort-Object)
        $stagedFiles = @(Get-ChildItem -LiteralPath $StagingPath -File -Recurse | ForEach-Object {
                $_.FullName.Substring($StagingPath.Length).TrimStart([char[]]@('\', '/'))
            } | Sort-Object)
        if ($existingFiles.Count -ne $stagedFiles.Count) {
            throw "Candidate namespace collision contains a different file set: $finalPath"
        }
        for ($index = 0; $index -lt $existingFiles.Count; $index++) {
            if (-not [string]::Equals([string]$existingFiles[$index], [string]$stagedFiles[$index], [System.StringComparison]::Ordinal)) {
                throw "Candidate namespace collision contains a different file set: $finalPath"
            }
        }
        foreach ($relative in $existingFiles) {
            $left = [System.IO.File]::ReadAllBytes((Join-Path $finalPath $relative))
            $right = [System.IO.File]::ReadAllBytes((Join-Path $StagingPath $relative))
            if (-not [System.Linq.Enumerable]::SequenceEqual($left, $right)) {
                throw "Candidate namespace collision contains different bytes: $relative"
            }
        }
        Remove-Item -LiteralPath $StagingPath -Recurse -Force
        return $finalPath
    }

    Invoke-ChannelForgeCandidateHook -HookName 'CandidateDirectoryMove.Before' -FaultHook $FaultHook
    [System.IO.Directory]::Move($StagingPath, $finalPath)
    Invoke-ChannelForgeCandidateHook -HookName 'CandidateDirectoryMove.After' -FaultHook $FaultHook
    return $finalPath
}
