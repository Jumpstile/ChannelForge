[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha256.ComputeHash($Bytes)).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-RevisionContentId {
    param(
        [Parameter(Mandatory)]
        [string[]]$ManifestLines
    )

    $prefix = [System.Text.Encoding]::UTF8.GetBytes('contract-revision-content/v1')
    $manifest = [System.Text.Encoding]::UTF8.GetBytes(($ManifestLines -join "`n") + "`n")
    $stream = [System.IO.MemoryStream]::new()
    try {
        $stream.Write($prefix, 0, $prefix.Length)
        $stream.WriteByte(0)
        $stream.Write($manifest, 0, $manifest.Length)
        return Get-Sha256Hex -Bytes $stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$contracts = @(
    [ordered]@{
        Name = 'blocker-2-contract/v9 candidate'
        Root = Join-Path $repoRoot 'docs\adr\blocker-2-contract-v9-proposal'
        FreezeRecord = 'FREEZE-RECORD.md'
        ExpectedRevisionContentId = '874b96b871069ef67b505dce4eaa0c64f0be050b158db90492482bad16f625f7'
        Files = [ordered]@{
            'PART-A-canonical-foundation.md' = 'a96d9a5a35e7aab4c8c9293ad262fc0c71c0ba100ce7b147c5e0ad9027190670'
            'PART-B-entry-output-slice.md' = '6e94795a80fe686e338380622358308304d935e86b7a7c0160f2c2b952c1382d'
            'README.md' = '735b966e04a45360bd03117600576698a8233563319250e87f1e1cde998fe427'
            'VERSION-OWNERSHIP-MAP.md' = 'e907a2fcedbf2870043faf6d3609cee3a1f7943a117e13b50135d8fdcde5ba4d'
        }
    }
    [ordered]@{
        Name = 'blocker-2-contract/v8 acceptance'
        Root = Join-Path $repoRoot 'docs\adr\blocker-2-contract-v8-proposal'
        FreezeRecord = 'FREEZE-RECORD.md'
        ExpectedRevisionContentId = 'd80feb5b24a4c335badb288fe0d82339f84a0d6b417d3a0a5fc3f38f2b07c69d'
        Files = [ordered]@{
            'PART-A-canonical-foundation.md' = 'ceb91e3260d2d534ad61e7a3bd5569a7b142baa386b4805ba67ae4d86e7ed01a'
            'PART-B-semantic-schemas.md' = '97ff3a649be47e77ddbf6f73d90ae8e2b2d4fdc256a22971ed91d1d172b59afd'
            'PART-C-promotion-recovery.md' = '0b25eadf831123a6ee3e92076e1898fc96378d998cd234d4fc382d4b6bb3dd7b'
            'README.md' = '094c6a1ac9179a8846f48fb7ba26312b79cae7833ce03d5a93d206c6fb393e1c'
            'SYMBOL-CLOSURE.md' = 'de9c547aae701d1d2e70ff1877b10a8546070f3b7d1dac599e507d29a7963a79'
        }
    }
)

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($contract in $contracts) {
    $manifestLines = [System.Collections.Generic.List[string]]::new()

    foreach ($fileName in $contract.Files.Keys) {
        $path = Join-Path $contract.Root $fileName
        if (-not [System.IO.File]::Exists($path)) {
            $failures.Add("$($contract.Name): missing normative file '$fileName'")
            continue
        }

        $actualHash = Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes($path))
        $expectedHash = [string]$contract.Files[$fileName]
        if ($actualHash -cne $expectedHash) {
            $failures.Add("$($contract.Name): byte hash mismatch for '$fileName' (expected $expectedHash, got $actualHash)")
        }

        $manifestLines.Add("$actualHash  $fileName")
    }

    if ($manifestLines.Count -eq $contract.Files.Count) {
        $actualRevisionContentId = Get-RevisionContentId -ManifestLines @($manifestLines)
        if ($actualRevisionContentId -cne $contract.ExpectedRevisionContentId) {
            $failures.Add("$($contract.Name): RevisionContentId mismatch (expected $($contract.ExpectedRevisionContentId), got $actualRevisionContentId)")
        }
    }

    $freezePath = Join-Path $contract.Root $contract.FreezeRecord
    if (-not [System.IO.File]::Exists($freezePath)) {
        $failures.Add("$($contract.Name): missing freeze record")
        continue
    }

    $freezeText = [System.IO.File]::ReadAllText(
        $freezePath,
        [System.Text.UTF8Encoding]::new($false, $true))
    if ($freezeText -notmatch '(?m)^- Status: FROZEN\.$') {
        $failures.Add("$($contract.Name): freeze record is not marked FROZEN")
    }
    if ($freezeText -notmatch [regex]::Escape($contract.ExpectedRevisionContentId)) {
        $failures.Add("$($contract.Name): freeze record does not attest the expected RevisionContentId")
    }
}

if ($failures.Count -gt 0) {
    throw "FROZEN_CONTRACT_INTEGRITY_FAILED:`n - $($failures -join "`n - ")"
}

Write-Output 'FROZEN_CONTRACT_INTEGRITY=PASS'
Write-Output 'Verified blocker-2-contract/v9 candidate bytes and blocker-2-contract/v8 acceptance bytes.'
