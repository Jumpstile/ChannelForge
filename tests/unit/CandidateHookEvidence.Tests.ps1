BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildCandidatePath = Join-Path $script:RepoRoot 'scripts\Build-Candidate.ps1'
    $script:TinyPlaylistPath = Join-Path $script:RepoRoot 'tests\fixtures\tiny.m3u'
    $script:SampleXmltvPath = Join-Path $script:RepoRoot 'tests\fixtures\xmltv\sample.xml'

    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeDomainHash.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\ConvertTo-ChannelForgeCandidateCanonical.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Publish-ChannelForgeCandidateNamespace.ps1')

    function New-HookEvidenceCandidate {
        param(
            [Parameter(Mandatory)][string]$Name
        )

        $output = Join-Path $TestDrive $Name
        $result = & $script:BuildCandidatePath `
            -Root $script:RepoRoot `
            -M3UPath $script:TinyPlaylistPath `
            -XMLTVPath $script:SampleXmltvPath `
            -OutputRoot $output `
            -TransactionId ('source-' + $Name)
        return [pscustomobject]@{
            Output = $output
            Result = $result
            Final = [string]$result.CandidateDirectory
        }
    }

    function Invoke-BuildWithHook {
        param(
            [Parameter(Mandatory)][string]$Output,
            [Parameter(Mandatory)][string]$Hook
        )

        $failure = $null
        try {
            $null = & $script:BuildCandidatePath `
                -Root $script:RepoRoot `
                -M3UPath $script:TinyPlaylistPath `
                -XMLTVPath $script:SampleXmltvPath `
                -OutputRoot $Output `
                -TransactionId ('fault-' + $Hook) `
                -FaultHook $Hook
        }
        catch {
            $failure = $_
        }
        return $failure
    }

    function Invoke-PublishWithHook {
        param(
            [Parameter(Mandatory)][string]$Output,
            [Parameter(Mandatory)][string]$StagingPath,
            [Parameter(Mandatory)][string]$ManifestHash,
            [Parameter(Mandatory)][string]$Hook
        )

        $failure = $null
        try {
            $null = Publish-ChannelForgeCandidateNamespace `
                -OutputRoot $Output `
                -StagingPath $StagingPath `
                -CandidateManifestHash $ManifestHash `
                -FaultHook $Hook
        }
        catch {
            $failure = $_
        }
        return $failure
    }

    function Copy-CandidateToStaging {
        param(
            [Parameter(Mandatory)][string]$Source,
            [Parameter(Mandatory)][string]$Output,
            [Parameter(Mandatory)][string]$Name
        )

        $staging = Join-Path $Output ('candidates\.staging\' + $Name)
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $staging -Recurse -Force
        return $staging
    }
}

Describe 'candidate namespace hook evidence C01-C17' {
    It 'fails closed at every C01-C15 artifact write/flush/reopen hook' {
        foreach ($hook in @('C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08', 'C09', 'C10', 'C11', 'C12', 'C13', 'C14', 'C15')) {
            $output = Join-Path $TestDrive ('artifact-' + $hook)
            $failure = Invoke-BuildWithHook -Output $output -Hook $hook

            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception.Message | Should -Match ([regex]::Escape('ChannelForge.TestFaultInjected:' + $hook))
            Test-Path -LiteralPath (Join-Path $output ('candidates\.staging\fault-' + $hook)) | Should -BeFalse
        }
    }

    It 'exercises C16 (before move) and C17 (after move) with final reopen validation' {
        # C16/C17 are exposed by their frozen directory-move hook names; only
        # C01-C15 have short aliases in Invoke-ChannelForgeCandidateHook.
        $source = New-HookEvidenceCandidate -Name 'move-source'
        $manifestHash = [string]$source.Result.CandidateManifestHash

        $beforeOutput = Join-Path $TestDrive 'move-before'
        $beforeStage = Copy-CandidateToStaging -Source $source.Final -Output $beforeOutput -Name 'before'
        $beforeFailure = Invoke-PublishWithHook `
            -Output $beforeOutput `
            -StagingPath $beforeStage `
            -ManifestHash $manifestHash `
            -Hook 'CandidateDirectoryMove.Before'

        $beforeFailure | Should -Not -BeNullOrEmpty
        $beforeFailure.Exception.Message | Should -Match ([regex]::Escape('ChannelForge.TestFaultInjected:CandidateDirectoryMove.Before'))
        Test-Path -LiteralPath $beforeStage -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $beforeOutput ('candidates\' + $manifestHash)) | Should -BeFalse

        $afterOutput = Join-Path $TestDrive 'move-after'
        $afterStage = Copy-CandidateToStaging -Source $source.Final -Output $afterOutput -Name 'after'
        $afterFailure = Invoke-PublishWithHook `
            -Output $afterOutput `
            -StagingPath $afterStage `
            -ManifestHash $manifestHash `
            -Hook 'CandidateDirectoryMove.After'
        $afterFinal = Join-Path $afterOutput ('candidates\' + $manifestHash)

        $afterFailure | Should -Not -BeNullOrEmpty
        $afterFailure.Exception.Message | Should -Match ([regex]::Escape('ChannelForge.TestFaultInjected:CandidateDirectoryMove.After'))
        Test-Path -LiteralPath $afterStage | Should -BeFalse
        Test-Path -LiteralPath $afterFinal -PathType Container | Should -BeTrue
        Test-ChannelForgeCandidateNamespace -Directory $afterFinal -ManifestHash $manifestHash | Should -BeTrue
    }

    It 'rejects invalid, missing, and extra artifacts before publication' {
        $mutations = @(
            [pscustomobject]@{
                Name = 'invalid'
                Apply = {
                    param([string]$Path)
                    [System.IO.File]::WriteAllBytes($Path, [byte[]](0x00))
                }
            }
            [pscustomobject]@{
                Name = 'missing'
                Apply = {
                    param([string]$Path)
                    Remove-Item -LiteralPath $Path -Force
                }
            }
            [pscustomobject]@{
                Name = 'extra'
                Apply = {
                    param([string]$Path)
                    [System.IO.File]::WriteAllText((Join-Path (Split-Path -Parent $Path) 'unexpected.bin'), 'unexpected')
                }
            }
        )

        foreach ($mutation in $mutations) {
            $candidate = New-HookEvidenceCandidate -Name ('malformed-' + $mutation.Name)
            $manifestHash = [string]$candidate.Result.CandidateManifestHash
            $staging = Copy-CandidateToStaging `
                -Source $candidate.Final `
                -Output $candidate.Output `
                -Name ('mutated-' + $mutation.Name)
            $artifact = Join-Path $staging 'merged.m3u'
            & $mutation.Apply $artifact

            Test-ChannelForgeCandidateNamespace -Directory $staging -ManifestHash $manifestHash | Should -BeFalse
            $failure = $null
            try {
                $null = Publish-ChannelForgeCandidateNamespace `
                    -OutputRoot $candidate.Output `
                    -StagingPath $staging `
                    -CandidateManifestHash $manifestHash
            }
            catch {
                $failure = $_
            }
            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception.Message | Should -Match 'staging validation failed'
            Test-Path -LiteralPath $candidate.Final -PathType Container | Should -BeTrue
        }
    }
}
