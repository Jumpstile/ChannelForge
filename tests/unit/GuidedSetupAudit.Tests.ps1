BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Schema = Join-Path $script:RepoRoot 'schemas\guided-setup-audit.schema.json'

    function Invoke-InModule {
        param([scriptblock]$Script, [object[]]$Arguments = @())
        & (Get-Module ChannelForge) $Script @Arguments
    }

    function New-AcceptedSetup {
        param([string]$Root)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'data\rules'), (Join-Path $Root 'data\lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $Root 'data\rules\aliases.json')
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $Root 'data\lineup\numbering_blocks.json')
        $encode = { param($t) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t)) }
        $news = "#EXTM3U`n#EXTINF:-1 tvg-id=`"news`",Secret News Text`nhttps://fixture-host.invalid/secret-news-path`n"
        $sports = "#EXTM3U`n#EXTINF:-1 tvg-id=`"sports`",Secret Sports Text`nhttps://fixture-host.invalid/secret-sports-path`n"
        $guide = '<?xml version="1.0"?><tv><channel id="news"><display-name>Secret News Text</display-name></channel><channel id="sports"><display-name>Secret Sports Text</display-name></channel></tv>'
        $proposalBody = [Text.Encoding]::UTF8.GetBytes((@{
                    schemaVersion = 2
                    playlists = @(
                        @{ sourceKey = 'news'; label = 'Private Label News'; priority = 100; contentBase64 = (& $encode $news) },
                        @{ sourceKey = 'sports'; label = 'Private Label Sports'; priority = 100; contentBase64 = (& $encode $sports) })
                    guides = @(@{ sourceKey = 'guide'; label = 'Private Label Guide'; priority = 100; contentBase64 = (& $encode $guide) })
                    bindings = @(@{ guideRef = 'guide'; playlistRefs = @(); appliesToAll = $true })
                } | ConvertTo-Json -Depth 8 -Compress))
        $proposal = Invoke-InModule {
            param($Root, $Body)
            Get-ChannelForgeWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $Root -StaticRoot '' -BodyBytes $Body -ContentType 'application/json' -ContentLength $Body.Length
        } @($Root, $proposalBody)
        if ($proposal.StatusCode -ne 200) { throw "fixture proposal failed: $($proposal.StatusCode) $($proposal.Body)" }
        $proposalId = ($proposal.Body | ConvertFrom-Json).Proposal.ProposalId
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 2; proposalId = $proposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Invoke-InModule {
            param($Root, $Body)
            Get-ChannelForgeWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $Root -StaticRoot '' -BodyBytes $Body -ContentType 'application/json' -ContentLength $Body.Length
        } @($Root, $acceptBody)
        if ($accepted.StatusCode -ne 200) { throw "fixture acceptance failed: $($accepted.StatusCode)" }
        # Build the record from the same sealed session, the current generation, and the saved enrollment.
        $record = Invoke-InModule {
            param($Root, $ProposalId)
            $session = Read-ChannelForgeWebProposalSession -RepositoryRoot $Root -ProposalId $ProposalId
            $snapshot = Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $Root
            $publish = [pscustomobject]@{ GenerationManifest = $snapshot.Manifest.Object; AcceptedState = $snapshot.State.Object; AcceptedOutputManifest = $snapshot.Output.Object; DecisionManifest = $snapshot.Decision.Object }
            New-ChannelForgeGuidedSetupAuditRecord -Session $session -Accepted $publish -Enrollment (Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $Root) -RequestSchemaVersion 2
        } @($Root, $proposalId)
        # Acceptance already wrote a record; clear it so each test starts from a known state.
        Remove-Item -LiteralPath (Join-Path $Root 'state\guided-setup-audit') -Recurse -Force
        return $record
    }

    function Get-AuditFile { param([string]$Root, $Record) Join-Path $Root "state\guided-setup-audit\acceptance-$($Record.Result.GenerationManifestHash).json" }
    function Read-Audit {
        param([string]$Root, $Record, [switch]$WithSnapshot)
        Invoke-InModule {
            param($Root, $Hash, $WithSnapshot)
            if ($WithSnapshot) { Read-ChannelForgeGuidedSetupAuditRecord -RepositoryRoot $Root -GenerationManifestHash $Hash -Snapshot (Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $Root -Paths (Get-ChannelForgeGenerationPaths -RepositoryRoot $Root)) }
            else { Read-ChannelForgeGuidedSetupAuditRecord -RepositoryRoot $Root -GenerationManifestHash $Hash }
        } @($Root, [string]$Record.Result.GenerationManifestHash, [bool]$WithSnapshot)
    }
    function Write-Audit {
        param([string]$Root, $Record)
        Invoke-InModule { param($Root, $Record) Write-ChannelForgeGuidedSetupAuditRecord -RepositoryRoot $Root -Record $Record } @($Root, $Record)
    }
}

Describe 'Guided Setup audit record' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Record = New-AcceptedSetup -Root $script:Root
    }

    It 'holds only hashes and numbers: no URLs, labels, text, or temp path' {
        $json = $script:Record | ConvertTo-Json -Depth 10
        foreach ($forbidden in @('fixture-host', 'secret-', 'Secret', 'Private Label', 'https://', $TestDrive, 'news', 'sports')) {
            $json.Contains($forbidden) | Should -BeFalse
        }
        @($script:Record.Playlists).Count | Should -Be 2
        @($script:Record.Guides).Count | Should -Be 1
        @($script:Record.Bindings).Count | Should -Be 1
    }

    It 'writes, reads back, verifies, and matches the schema' {
        Write-Audit -Root $script:Root -Record $script:Record
        (Read-Audit -Root $script:Root -Record $script:Record -WithSnapshot).Status | Should -Be 'AUDIT_OK'
        Test-Json -Path (Get-AuditFile $script:Root $script:Record) -SchemaFile $script:Schema | Should -BeTrue
    }

    It 'reports one flipped byte as AUDIT_INVALID' {
        Write-Audit -Root $script:Root -Record $script:Record
        $file = Get-AuditFile $script:Root $script:Record
        $bytes = [IO.File]::ReadAllBytes($file)
        $bytes[$bytes.Length - 10] = $bytes[$bytes.Length - 10] -bxor 1
        [IO.File]::WriteAllBytes($file, $bytes)
        (Read-Audit -Root $script:Root -Record $script:Record).Status | Should -Be 'AUDIT_INVALID'
    }

    It 'reports a deleted file as AUDIT_MISSING' {
        Write-Audit -Root $script:Root -Record $script:Record
        Remove-Item -LiteralPath (Get-AuditFile $script:Root $script:Record)
        (Read-Audit -Root $script:Root -Record $script:Record).Status | Should -Be 'AUDIT_MISSING'
    }

    It 'never replaces an existing record' {
        Write-Audit -Root $script:Root -Record $script:Record
        $file = Get-AuditFile $script:Root $script:Record
        $before = (Get-FileHash -LiteralPath $file).Hash
        $other = $script:Record.PSObject.Copy(); $other.ProposalId = ('f' * 32)
        { Write-Audit -Root $script:Root -Record $other } | Should -Throw
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $before
        @(Get-ChildItem -LiteralPath (Split-Path $file) -Force).Count | Should -Be 1
    }

    It 'reports a record that disagrees with the accepted generation as AUDIT_MISMATCH' {
        $wrong = $script:Record.PSObject.Copy()
        $wrong.Result = [pscustomobject]@{ GenerationManifestHash = $script:Record.Result.GenerationManifestHash; AcceptedStateHash = ('a' * 64); OutputManifestHash = $script:Record.Result.OutputManifestHash; DecisionManifestHash = $script:Record.Result.DecisionManifestHash }
        $wrong.RecordHash = Invoke-InModule { param($r) Get-ChannelForgeGuidedSetupAuditHash -Record $r } @($wrong)
        Write-Audit -Root $script:Root -Record $wrong
        (Read-Audit -Root $script:Root -Record $wrong -WithSnapshot).Status | Should -Be 'AUDIT_MISMATCH'
    }

    It 'is left unchanged by accepted-state recovery' {
        Write-Audit -Root $script:Root -Record $script:Record
        $file = Get-AuditFile $script:Root $script:Record
        $before = (Get-FileHash -LiteralPath $file).Hash
        Invoke-InModule { param($Root) Recover-ChannelForgeAcceptedStateCore -RepositoryRoot $Root | Out-Null } @($script:Root)
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $before
        (Read-Audit -Root $script:Root -Record $script:Record -WithSnapshot).Status | Should -Be 'AUDIT_OK'
    }
}
