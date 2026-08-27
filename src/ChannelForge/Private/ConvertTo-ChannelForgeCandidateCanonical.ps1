function ConvertTo-ChannelForgeCandidateJson {
    param([Parameter(Mandatory)][object]$InputObject)
    return ConvertTo-ChannelForgeCanonicalJson -InputObject $InputObject
}

function Get-ChannelForgeCandidateDomainHash {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][byte[]]$Bytes)
    $prefix = [System.Text.Encoding]::ASCII.GetBytes($Domain + [char]0)
    $payload = [byte[]]::new($prefix.Length + $Bytes.Length)
    [System.Buffer]::BlockCopy($prefix, 0, $payload, 0, $prefix.Length)
    [System.Buffer]::BlockCopy($Bytes, 0, $payload, $prefix.Length, $Bytes.Length)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-ChannelForgeCandidateCanonicalHash {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][object]$InputObject)
    $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes((ConvertTo-ChannelForgeCandidateJson -InputObject $InputObject))
    return Get-ChannelForgeCandidateDomainHash -Domain $Domain -Bytes $bytes
}

function Invoke-ChannelForgeCandidateHook {
    param([Parameter(Mandatory)][string]$HookName, [string]$FaultHook = '')
    $frozenHookNames = [ordered]@{
        C01 = 'CandidateStageWrite.Manifest'
        C02 = 'CandidateStageFlush.Manifest'
        C03 = 'CandidateStageReopenHash.Manifest'
        C04 = 'CandidateStageWrite.M3U'
        C05 = 'CandidateStageFlush.M3U'
        C06 = 'CandidateStageReopenHash.M3U'
        C07 = 'CandidateStageWrite.XMLTV'
        C08 = 'CandidateStageFlush.XMLTV'
        C09 = 'CandidateStageReopenHash.XMLTV'
        C10 = 'CandidateStageWrite.ReviewJSON'
        C11 = 'CandidateStageFlush.ReviewJSON'
        C12 = 'CandidateStageReopenHash.ReviewJSON'
        C13 = 'CandidateStageWrite.ReviewMarkdown'
        C14 = 'CandidateStageFlush.ReviewMarkdown'
        C15 = 'CandidateStageReopenHash.ReviewMarkdown'
    }
    $triggerName = $FaultHook
    foreach ($entry in $frozenHookNames.GetEnumerator()) {
        if ([string]::Equals($FaultHook, $entry.Key, [System.StringComparison]::Ordinal)) {
            $triggerName = $entry.Value
            break
        }
    }
    if ([string]::Equals($HookName, $triggerName, [System.StringComparison]::Ordinal)) {
        throw "ChannelForge.TestFaultInjected:$FaultHook"
    }
}

function Write-ChannelForgeCandidateArtifact {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][string]$HookPrefix, [string]$FaultHook = '')
    $artifactName = $HookPrefix -replace '^CandidateStageWrite\.', ''
    Invoke-ChannelForgeCandidateHook -HookName "CandidateStageWrite.$artifactName" -FaultHook $FaultHook
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        Invoke-ChannelForgeCandidateHook -HookName "CandidateStageFlush.$artifactName" -FaultHook $FaultHook
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    Invoke-ChannelForgeCandidateHook -HookName "CandidateStageReopenHash.$artifactName" -FaultHook $FaultHook
    $actual = [System.IO.File]::ReadAllBytes($Path)
    if ($actual.Length -ne $Bytes.Length -or -not [System.Linq.Enumerable]::SequenceEqual($actual, $Bytes)) { throw "Candidate artifact verification failed: $Path" }
    return $actual.Length
}

function Test-ChannelForgeCandidateNamespace {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$ManifestHash,
        [switch]$AllowStagingName
    )
    try {
        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $false }
        if ($ManifestHash -notmatch '^[0-9a-f]{64}$') { return $false }
        $manifestPath = Join-Path $Directory 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $raw = [System.IO.File]::ReadAllBytes($manifestPath)
        $manifestText = $utf8.GetString([byte[]]$raw)
        $manifest = $manifestText | ConvertFrom-Json
        if ($null -eq $manifest -or
            [string]$manifest.CandidateManifestHash -cne $ManifestHash -or
            [string]$manifest.CandidateManifestHash -notmatch '^[0-9a-f]{64}$' -or
            [string]$manifest.BuildIdentity -notmatch '^[0-9a-f]{64}$') { return $false }

        # The self-hash is over the exact ordered manifest projection with its
        # self field omitted. Re-encoding must also be byte-for-byte stable.
        $withoutSelf = [ordered]@{}
        foreach ($property in @($manifest.PSObject.Properties)) {
            if ($property.Name -ne 'CandidateManifestHash') {
                $withoutSelf[$property.Name] = $property.Value
            }
        }
        if ((Get-ChannelForgeDomainHash -Domain 'candidate-manifest/v2' -InputObject $withoutSelf) -cne $ManifestHash) { return $false }
        if ($utf8.GetString($utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson $manifest))) -cne $manifestText) { return $false }

        $records = @($manifest.ArtifactRecords)
        $expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($record in $records) {
            foreach ($name in @('Role', 'RelativePath', 'Status', 'ByteLength', 'ContentDomain', 'ContentHash')) {
                if ($null -eq $record.PSObject.Properties[$name]) { return $false }
            }
            $relative = [string]$record.RelativePath
            if ($relative -notin @('merged.m3u', 'merged.xml', 'lineup-change-review.json', 'lineup-change-review.md') -or
                [System.IO.Path]::IsPathRooted($relative) -or
                $relative.Contains('..') -or
                -not $expected.Add($relative)) { return $false }
            $domain = [string]$record.ContentDomain
            $role = [string]$record.Role
            $mappingValid =
                ($role -eq 'CandidateM3U' -and $relative -eq 'merged.m3u' -and $domain -eq 'candidate-m3u/v2') -or
                ($role -eq 'CandidateXMLTV' -and $relative -eq 'merged.xml' -and $domain -eq 'candidate-xmltv/v2') -or
                ($role -eq 'CandidateReviewJSON' -and $relative -eq 'lineup-change-review.json' -and $domain -eq 'candidate-review-json/v2') -or
                ($role -eq 'CandidateReviewMarkdown' -and $relative -eq 'lineup-change-review.md' -and $domain -eq 'candidate-review-markdown/v2')
            if (-not $mappingValid -or $record.Status -cne 'Generated' -or
                [string]$record.ContentHash -notmatch '^[0-9a-f]{64}$' -or
                [int64]$record.ByteLength -lt 0) { return $false }
            $artifactPath = Join-Path $Directory $relative
            if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { return $false }
            $bytes = [System.IO.File]::ReadAllBytes($artifactPath)
            if ($bytes.Length -ne [int64]$record.ByteLength -or
                (Get-ChannelForgeDomainHash -Domain $domain -Bytes $bytes) -cne [string]$record.ContentHash) { return $false }
        }
        foreach ($required in @('merged.m3u', 'lineup-change-review.json', 'lineup-change-review.md')) {
            if (-not $expected.Contains($required)) { return $false }
        }
        $files = @(Get-ChildItem -LiteralPath $Directory -File | ForEach-Object { $_.Name } | Sort-Object)
        $allowed = @('manifest.json') + @($expected | Sort-Object)
        if ((Compare-Object -ReferenceObject $allowed -DifferenceObject $files) -or
            (-not $AllowStagingName -and [System.IO.Path]::GetFileName($Directory) -cne $ManifestHash)) { return $false }
        return $true
    }
    catch {
        return $false
    }
}
