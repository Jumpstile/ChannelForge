BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:AcceptanceContractPath = Join-Path $script:RepoRoot 'docs\adr\blocker-2-contract-v8-proposal\PART-C-promotion-recovery.md'
    $script:AcceptanceContract = [System.IO.File]::ReadAllText(
        $script:AcceptanceContractPath,
        [System.Text.UTF8Encoding]::new($false, $true))

    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function Test-PrivateSourceUrl {
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

        & (Get-Module -Name ChannelForge) {
            param($Url)
            Test-ChannelForgeSourceUrl -Url $Url
        } $Value
    }

    function Test-PrivateWritePath {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
            [Parameter(Mandatory)][AllowEmptyString()][string]$AllowedRoot
        )

        & (Get-Module -Name ChannelForge) {
            param($Candidate, $Root)
            Test-ChannelForgeWritePath -Path $Candidate -AllowedRoot $Root
        } $Path $AllowedRoot
    }

    function Get-ContractSection {
        param(
            [Parameter(Mandatory)][string]$Document,
            [Parameter(Mandatory)][string]$StartHeading,
            [Parameter(Mandatory)][string]$EndHeading
        )

        $start = $Document.IndexOf($StartHeading, [System.StringComparison]::Ordinal)
        if ($start -lt 0) {
            throw "Contract section is missing: $StartHeading"
        }

        $end = $Document.IndexOf($EndHeading, $start + $StartHeading.Length, [System.StringComparison]::Ordinal)
        if ($end -lt 0) {
            return $Document.Substring($start)
        }

        return $Document.Substring($start, $end - $start)
    }
}

Describe 'Path containment mutation properties' {
    It 'accepts only the approved root and deterministic descendants' {
        $root = Join-Path $TestDrive 'approved'
        $accepted = @(
            $root,
            (Join-Path $root 'reports\build-summary.json'),
            (Join-Path $root 'nested\space name\artifact.json'),
            (Join-Path $root 'literal-dot\.\file.txt')
        )

        foreach ($candidate in $accepted) {
            (Test-PrivateWritePath -Path $candidate -AllowedRoot $root) | Should -BeTrue -Because "approved descendant: $candidate"
        }
    }

    It 'rejects traversal, sibling-prefix, UNC, and empty mutations' {
        $root = Join-Path $TestDrive 'approved'
        $cases = @(
            '',
            (Join-Path $root '..\outside\file.json'),
            (Join-Path (Split-Path -Parent $root) 'approved-other\file.json'),
            ($root + '-other\file.json'),
            '\\server\share\file.json',
            'C:\Windows\System32\drivers\etc\hosts'
        )

        foreach ($candidate in $cases) {
            (Test-PrivateWritePath -Path $candidate -AllowedRoot $root) | Should -BeFalse -Because "unsafe path mutation: $candidate"
        }

        (Test-PrivateWritePath -Path (Join-Path $root 'file.json') -AllowedRoot '') | Should -BeFalse
    }
}

Describe 'Source URL trust-boundary mutations' {
    It 'accepts only the intended public HTTPS mutation' {
        foreach ($url in @(
                'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports',
                'https://172.32.0.1/iptv',
                'https://[2606:4700:4700::1111]/iptv')) {
            (Test-PrivateSourceUrl -Value $url) | Should -BeTrue -Because "allowed source URL: $url"
        }
    }

    It 'rejects every unsafe scheme, credential, local-address, and malformed mutation' {
        $unsafe = @(
            'http://example.invalid/iptv',
            'ftp://example.invalid/iptv',
            'file:///C:/secrets.json',
            'https://user:pass@example.invalid/iptv',
            'https://localhost/iptv',
            'https://127.0.0.1/iptv',
            'https://[::1]/iptv',
            'https://10.1.2.3/iptv',
            'https://192.168.1.1/iptv',
            'https://[fd12:3456:789a::1]/iptv',
            'https://[2001:db8::1]/iptv',
            '',
            'not-a-valid-url'
        )

        foreach ($url in $unsafe) {
            (Test-PrivateSourceUrl -Value $url) | Should -BeFalse -Because "unsafe source URL mutation: $url"
        }
    }
}

Describe 'C# transport fail-closed source invariants' {
    It 'does not contain an accept-any-certificate escape hatch' {
        $sourcePath = Join-Path $script:RepoRoot 'src\ChannelForge\Private\Transport\ChannelForgePinnedHttpTransport.cs'
        $source = [System.IO.File]::ReadAllText(
            $sourcePath,
            [System.Text.UTF8Encoding]::new($false, $true))

        $source | Should -Not -Match '(?i)DangerousAcceptAnyServerCertificateValidator'
        $source | Should -Not -Match '(?i)RemoteCertificateValidationCallback\s*=\s*[^;]*(?:=>\s*true|return\s+true)'
    }
}

Describe 'Acceptance journal and recovery contract oracle' {
    It 'keeps the journal phase enum closed and ordered' {
        $script:AcceptanceContract.Contains('Closed enum `None`, `Prepared`, `GenerationPublished`, `PointerSwapped`, or `Committed`; ranks are 0, 1, 2, 3, and 4.') | Should -BeTrue

        $phasePositions = @(
            $script:AcceptanceContract.IndexOf('`None`', [System.StringComparison]::Ordinal),
            $script:AcceptanceContract.IndexOf('`Prepared`', [System.StringComparison]::Ordinal),
            $script:AcceptanceContract.IndexOf('`GenerationPublished`', [System.StringComparison]::Ordinal),
            $script:AcceptanceContract.IndexOf('`PointerSwapped`', [System.StringComparison]::Ordinal),
            $script:AcceptanceContract.IndexOf('`Committed`', [System.StringComparison]::Ordinal)
        )
        ($phasePositions | Where-Object { $_ -lt 0 }).Count | Should -Be 0
        for ($index = 1; $index -lt $phasePositions.Count; $index++) {
            $phasePositions[$index] | Should -BeGreaterThan $phasePositions[$index - 1]
        }
    }

    It 'keeps every publication and verification boundary in the fault matrix' {
        $boundaries = @(
            'Child/generation stage write',
            'Prepared journal replace',
            'Generation directory move',
            'GenerationPublished journal replace',
            'Pointer compare-and-swap',
            'PointerSwapped journal replace',
            'Full graph reopen',
            'Committed journal replace',
            'Cleanup'
        )

        foreach ($boundary in $boundaries) {
            $script:AcceptanceContract.Contains($boundary) | Should -BeTrue -Because "durability boundary: $boundary"
        }

        $faultSection = Get-ContractSection `
            -Document $script:AcceptanceContract `
            -StartHeading '## 10. Fault matrix' `
            -EndHeading '## 11. Current/previous lineage'

        foreach ($fault in @(
                'Journal stage write/flush/reopen for Prepared',
                'Journal replace for Prepared',
                'Directory move before/after',
                'Journal replace for GenerationPublished',
                'Pointer replacement before',
                'Pointer replacement after',
                'Journal stage/replace for PointerSwapped',
                'Reopen/hash verification of any NEW child',
                'Journal stage/replace for Committed',
                'Any cleanup delete before/after')) {
            $faultSection.Contains($fault) | Should -BeTrue -Because "fault checkpoint: $fault"
        }
    }

    It 'requires first-match recovery predicates to fail closed on ambiguity' {
        $predicateSection = Get-ContractSection `
            -Document $script:AcceptanceContract `
            -StartHeading '### 9.1 Recovery predicates' `
            -EndHeading '## 9. Recovery matrix'

        foreach ($predicate in @('R_lock :=', 'R_bad :=', 'R_journal :=', 'R_old :=', 'R_new :=', 'R_empty :=', 'R_other :=')) {
            $predicateSection.Contains($predicate) | Should -BeTrue -Because "recovery predicate: $predicate"
        }

        $predicateSection.Contains('R_lock := L -> FAIL_CLOSED_RECOVERY_REQUIRED') | Should -BeTrue
        $predicateSection.Contains('R_bad := not L and U -> FAIL_CLOSED_RECOVERY_REQUIRED') | Should -BeTrue
        $predicateSection.Contains('R_journal := not L and not U and Jbad -> FAIL_CLOSED_RECOVERY_REQUIRED') | Should -BeTrue
        $predicateSection.Contains('R_empty := not L and not U and not Jbad and not J and not S and E -> INITIAL_BASELINE_REQUIRED') | Should -BeTrue
        $predicateSection.Contains('R_other := none of R_lock, R_bad, R_journal, R_old, R_new, or R_empty') | Should -BeTrue
    }

    It 'requires all mixed-generation A-J mutations to have the same fail-closed result' {
        $matrix = Get-ContractSection `
            -Document $script:AcceptanceContract `
            -StartHeading '## 12. Mixed-generation rejection cases' `
            -EndHeading '## 13. Acyclic transaction ordering'

        $rows = @([regex]::Matches($matrix, '(?m)^\|\s*([A-J])\s*\|([^\r\n]*)$') | ForEach-Object { $_ })
        @($rows).Count | Should -Be 10
        @($rows | ForEach-Object { $_.Groups[1].Value }) | Should -Be @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J')

        foreach ($row in $rows) {
            $row.Groups[2].Value | Should -Match 'FAIL_CLOSED_RECOVERY_REQUIRED'
        }

        $matrix.Contains('mutate no pointer, generation, accepted artifact, or journal') | Should -BeTrue
        $matrix.Contains('FileIdentity') | Should -BeTrue
        $matrix.Contains('byte length') | Should -BeTrue
        $matrix.Contains('reparse') | Should -BeTrue
        $script:AcceptanceContract.Contains('TOCTOU') | Should -BeTrue
    }
}
