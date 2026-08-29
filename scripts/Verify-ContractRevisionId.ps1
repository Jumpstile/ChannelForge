[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [Parameter(Mandatory)][string]$AttestationPath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedRevisionContentId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$canonicalFiles = @(
    'PART-A-canonical-foundation.md',
    'PART-B-entry-output-slice.md',
    'README.md',
    'VERSION-OWNERSHIP-MAP.md'
)
$canonicalRoot = 'docs/adr/blocker-2-contract-v9-proposal'

function Invoke-GitBytes {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.WorkingDirectory = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'FAIL_CLOSED: could not start Git.' }
    $output = [System.IO.MemoryStream]::new()
    try {
        $process.StandardOutput.BaseStream.CopyTo($output)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "FAIL_CLOSED: Git command failed: $errorText" }
        return $output.ToArray()
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function ConvertTo-Sha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash($Bytes)).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-DeclaredManifest {
    param([Parameter(Mandatory)][string]$Path)

    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [System.Text.UTF8Encoding]::new($false))
    $begin = '<!-- RCID-GIT-MANIFEST-BEGIN -->'
    $end = '<!-- RCID-GIT-MANIFEST-END -->'
    $start = $text.IndexOf($begin, [System.StringComparison]::Ordinal)
    $finish = $text.IndexOf($end, [System.StringComparison]::Ordinal)
    if ($start -lt 0 -or $finish -le $start) { throw 'FAIL_CLOSED: canonical Git manifest markers are missing or unordered.' }

    $bodyStart = $start + $begin.Length
    $body = $text.Substring($bodyStart, $finish - $bodyStart).Trim("`r", "`n", ' ')
    $lines = @($body -split "`r?`n" | Where-Object { $_ -ne '' })
    if ($lines.Count -ne $canonicalFiles.Count) { throw 'FAIL_CLOSED: canonical Git manifest must contain exactly four entries.' }

    $declared = [ordered]@{}
    for ($index = 0; $index -lt $canonicalFiles.Count; $index++) {
        if ($lines[$index] -notmatch '^([0-9a-f]{64})  (.+)$') { throw 'FAIL_CLOSED: malformed canonical Git manifest entry.' }
        $digest = $Matches[1]
        $name = $Matches[2]
        if ($name -cne $canonicalFiles[$index]) { throw 'FAIL_CLOSED: canonical Git manifest path order is invalid.' }
        if ($declared.Contains($name)) { throw 'FAIL_CLOSED: duplicate canonical Git manifest path.' }
        $declared[$name] = $digest
    }
    return $declared
}

$resolvedAttestation = (Resolve-Path -LiteralPath $AttestationPath).Path
$commitBytes = Invoke-GitBytes @('rev-parse', '--verify', "$Commit^{commit}")

$resolvedCommit = ([System.Text.UTF8Encoding]::new($false).GetString($commitBytes)).Trim()
if ($resolvedCommit -cne $Commit) { throw 'FAIL_CLOSED: commit did not resolve to the supplied immutable commit.' }

$attestation = [System.IO.File]::ReadAllText($resolvedAttestation, [System.Text.UTF8Encoding]::new($false))
$declaredAuthority = [regex]::Match($attestation, '(?m)^- Corrected RevisionContentId: `([0-9a-f]{64})`\.?\r?$')
$declaredCommit = [regex]::Match($attestation, '(?m)^- Canonical Git content commit: `([0-9a-f]{40})`\.?\r?$')
if (-not $declaredCommit.Success -or $declaredCommit.Groups[1].Value -cne $Commit) { throw 'FAIL_CLOSED: attestation canonical commit does not match the supplied commit.' }
$declared = Get-DeclaredManifest $resolvedAttestation
$manifestLines = [System.Collections.Generic.List[string]]::new()

foreach ($name in $canonicalFiles) {
    $relativePath = "$canonicalRoot/$name"
    $spec = "$Commit`:$relativePath"
    $blobObject = ([System.Text.UTF8Encoding]::new($false).GetString((Invoke-GitBytes @('rev-parse', '--verify', $spec)))).Trim()
    if ($blobObject -notmatch '^[0-9a-f]{40}$') { throw "FAIL_CLOSED: $relativePath did not resolve to a Git blob." }
    $payload = [byte[]](Invoke-GitBytes @('cat-file', 'blob', $spec))
    $payloadHash = ConvertTo-Sha256Hex $payload
    if ($declared[$name] -cne $payloadHash) { throw "FAIL_CLOSED: declared manifest hash does not match Git blob bytes for $name." }
    $manifestLines.Add("$payloadHash  $name")
}

$manifest = ((($manifestLines -join "`n") + "`n"))
$utf8 = [System.Text.UTF8Encoding]::new($false)
$revisionContentId = ConvertTo-Sha256Hex ($utf8.GetBytes("contract-revision-content/v1`0$manifest"))
if ($revisionContentId -cne $ExpectedRevisionContentId) { throw 'FAIL_CLOSED: computed RevisionContentId does not match the expected authority.' }

[pscustomobject][ordered]@{
    ContractRevisionId = 'blocker-2-contract/v9'
    Commit = $Commit
    RevisionContentId = $revisionContentId
    Files = @($canonicalFiles | ForEach-Object {
            [pscustomobject][ordered]@{ Name = $_; GitBlobPayloadSha256 = $declared[$_] }
        })
}
