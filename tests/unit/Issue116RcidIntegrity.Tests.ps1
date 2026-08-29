BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:VerifierPath = Join-Path $script:RepoRoot 'scripts\Verify-ContractRevisionId.ps1'
    $script:NormativeNames = @(
        'PART-A-canonical-foundation.md',
        'PART-B-entry-output-slice.md',
        'README.md',
        'VERSION-OWNERSHIP-MAP.md'
    )

    function Get-Sha256Hex {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return [Convert]::ToHexString($sha.ComputeHash($Bytes)).ToLowerInvariant() }
        finally { $sha.Dispose() }
    }

    function Invoke-TestGit {
        param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string[]]$Arguments)
        $result = & git -C $Root @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Git failed: $result" }
        return [string]::Join("`n", @($result))
    }

    function New-RcidFixture {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('channelforge-issue116-' + [guid]::NewGuid().ToString('N'))
        $proposal = Join-Path $root 'docs\adr\blocker-2-contract-v9-proposal'
        New-Item -ItemType Directory -Path $proposal -Force | Out-Null
        foreach ($name in $script:NormativeNames) {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes("fixture:$name`n")
            [System.IO.File]::WriteAllBytes((Join-Path $proposal $name), $bytes)
        }
        Invoke-TestGit $root @('init', '--quiet') | Out-Null
        Invoke-TestGit $root @('config', 'user.email', 'issue116@example.invalid') | Out-Null
        Invoke-TestGit $root @('config', 'user.name', 'Issue 116 Test') | Out-Null
        Invoke-TestGit $root @('add', '.') | Out-Null
        Invoke-TestGit $root @('commit', '--quiet', '-m', 'fixture') | Out-Null
        $commit = (Invoke-TestGit $root @('rev-parse', 'HEAD')).Trim()

        $hashes = [ordered]@{}
        foreach ($name in $script:NormativeNames) {
            $hashes[$name] = Get-Sha256Hex ([System.IO.File]::ReadAllBytes((Join-Path $proposal $name)))
        }
        $manifest = (($script:NormativeNames | ForEach-Object { "$($hashes[$_])  $_" }) -join "`n") + "`n"
        $rcid = Get-Sha256Hex ([System.Text.UTF8Encoding]::new($false).GetBytes("contract-revision-content/v1`0$manifest"))
        $attestation = @"
# Test attestation
- Canonical Git content commit: ``COMMIT_PLACEHOLDER``.
- Corrected RevisionContentId: ``RCID_PLACEHOLDER``.
<!-- RCID-GIT-MANIFEST-BEGIN -->
$manifest<!-- RCID-GIT-MANIFEST-END -->
"@
        $attestation = $attestation.Replace('COMMIT_PLACEHOLDER', $commit).Replace('RCID_PLACEHOLDER', $rcid)
        $attestationPath = Join-Path $root 'attestation.md'
        [System.IO.File]::WriteAllText($attestationPath, $attestation.TrimStart(), [System.Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ Root = $root; Proposal = $proposal; Commit = $commit; Rcid = $rcid; Attestation = $attestationPath; Hashes = $hashes }
    }

    function Invoke-Verifier {
        param([Parameter(Mandatory)]$Fixture)
        return & $script:VerifierPath -RepositoryRoot $Fixture.Root -Commit $Fixture.Commit -AttestationPath $Fixture.Attestation -ExpectedRevisionContentId $Fixture.Rcid
    }
}

Describe 'Verify-ContractRevisionId.ps1' {
    It 'reproduces the corrected v9 authority from immutable Git bytes' {
        $result = & $script:VerifierPath -RepositoryRoot $script:RepoRoot -Commit 'eef60709888a37689c551efc9df5b66715b7e7b7' -AttestationPath (Join-Path $script:RepoRoot 'docs\adr\blocker-2-contract-v9-proposal\FREEZE-RECORD.md') -ExpectedRevisionContentId '1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192'
        $result.RevisionContentId | Should -Be '1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192'
        @($result.Files).Count | Should -Be 4
    }

    It 'returns the same authority when the checkout files are rewritten as CRLF' {
        $fixture = New-RcidFixture
        try {
            $before = Invoke-Verifier $fixture
            foreach ($name in $script:NormativeNames) {
                $path = Join-Path $fixture.Proposal $name
                $text = [System.Text.UTF8Encoding]::new($false).GetString([System.IO.File]::ReadAllBytes($path))
                [System.IO.File]::WriteAllBytes($path, [System.Text.UTF8Encoding]::new($false).GetBytes($text.Replace("`n", "`r`n")))
            }
            $after = Invoke-Verifier $fixture
            $after.RevisionContentId | Should -Be $before.RevisionContentId
            @($after.Files | ForEach-Object GitBlobPayloadSha256) | Should -Be @($before.Files | ForEach-Object GitBlobPayloadSha256)
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails closed when one declared manifest entry uses a CRLF checkout hash' {
        $fixture = New-RcidFixture
        try {
            $path = Join-Path $fixture.Proposal $script:NormativeNames[1]
            $crlfBytes = [System.Text.UTF8Encoding]::new($false).GetBytes("fixture:$($script:NormativeNames[1])`r`n")
            $crlfHash = Get-Sha256Hex $crlfBytes
            $text = [System.IO.File]::ReadAllText($fixture.Attestation, [System.Text.UTF8Encoding]::new($false))
            $text = $text.Replace($fixture.Hashes[$script:NormativeNames[1]], $crlfHash)
            [System.IO.File]::WriteAllText($fixture.Attestation, $text, [System.Text.UTF8Encoding]::new($false))
            { Invoke-Verifier $fixture } | Should -Throw 'FAIL_CLOSED:*'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
