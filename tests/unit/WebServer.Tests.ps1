BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:ServerScriptPath = Join-Path $script:RepoRoot 'scripts\Start-ChannelForgeWebServer.ps1'
    $script:StatusRoot = Join-Path $TestDrive 'status-root'
    New-Item -ItemType Directory -Force -Path $script:StatusRoot | Out-Null
    Import-Module $script:ModulePath -Force

    function Get-TestWebResponse {
        param(
            [Parameter(Mandatory)][string]$Method,
            [Parameter(Mandatory)][string]$Path,
            [string]$RepositoryRoot = $script:StatusRoot
        )

        $module = Get-Module -Name ChannelForge
        return & $module {
            param($RequestMethod, $RequestPath, $RequestRoot)
            Get-ChannelForgeWebResponse -Method $RequestMethod -Path $RequestPath -RepositoryRoot $RequestRoot
        } $Method $Path $RepositoryRoot
    }

    function New-TestAcceptedState {
        param([Parameter(Mandatory)][string]$RepositoryRoot)

        $generationId = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        $fixture = & (Get-Module ChannelForge) {
            param($GenerationId)
            $a = 'a' * 64
            $b = 'b' * 64
            $c = 'c' * 64
            $m3uDecision = New-ChannelForgeDecisionM3U -CandidateManifestHash $a -BuildIdentity $b -AcceptedParentGenerationManifestHash $null -IncludedCandidateEntryIds @($a) -ExcludedCandidateEntryIds @($b) -DecisionIds @($c)
            $decision = New-ChannelForgeDecisionManifest -CandidateManifestHash $a -BuildIdentity $b -M3UDecision $m3uDecision -XMLTVDecision $null -XMLTVDecisionStatus NotGenerated
            $m3u = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Status fixture`nhttps://example.invalid/$GenerationId`n")
            $m3uHash = Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $m3u
            $output = [ordered]@{ Version = 'blocker-2-contract/v8-acceptance'; GenerationId = $GenerationId; ActiveM3UHash = $m3uHash; ActiveXMLTVStatus = 'NotGenerated'; ActiveXMLTVHash = $null; AcceptedStateHash = $b; OutputManifestHash = $null }
            $output.OutputManifestHash = Get-ChannelForgeAcceptanceHash -Domain 'previous-output-manifest/v2' -Projection $output -HashProperty OutputManifestHash -Omit @('GenerationId', 'AcceptedStateHash')
            $state = [ordered]@{ Version = 'blocker-2-contract/v8-acceptance'; GenerationId = $GenerationId; BuildIdentity = $b; CandidateManifestHash = $a; DecisionManifestHash = $decision.DecisionManifestHash; AcceptedOutputManifestHash = $output.OutputManifestHash; PreviousStateHash = $null; IncludedCandidateEntryIds = @($a); ExcludedCandidateEntryIds = @($b); AcceptedBindingIds = @($c); AcceptedXMLTVStatus = 'NotGenerated'; AcceptedAtUtc = '2026-08-29T00:00:00Z'; AcceptedStateHash = $null }
            $state.AcceptedStateHash = Get-ChannelForgeAcceptanceHash -Domain 'accepted-state/v2' -Projection $state -HashProperty AcceptedStateHash -Omit @('GenerationId', 'AcceptedAtUtc')
            $output.AcceptedStateHash = $state.AcceptedStateHash
            $manifest = [ordered]@{ Version = 'blocker-2-contract/v8-acceptance'; GenerationId = $GenerationId; BuildIdentity = $b; CandidateManifestHash = $a; DecisionManifestHash = $decision.DecisionManifestHash; AcceptedStateHash = $state.AcceptedStateHash; AcceptedOutputManifestHash = $output.OutputManifestHash; ActiveM3UHash = $output.ActiveM3UHash; ActiveXMLTVHash = $output.ActiveXMLTVHash; PreviousOutputManifestHash = $null; GenerationManifestHash = $null }
            $manifest.GenerationManifestHash = Get-ChannelForgeAcceptanceHash -Domain 'generation-manifest/v2' -Projection $manifest -HashProperty GenerationManifestHash -Omit @('GenerationId')
            [pscustomobject]@{ GenerationManifest = [pscustomobject]$manifest; AcceptedState = [pscustomobject]$state; AcceptedOutputManifest = [pscustomobject]$output; DecisionManifest = $decision; M3UBytes = $m3u }
        } $generationId

        Publish-ChannelForgeAcceptedGeneration -RepositoryRoot $RepositoryRoot -GenerationManifest $fixture.GenerationManifest -AcceptedState $fixture.AcceptedState -AcceptedOutputManifest $fixture.AcceptedOutputManifest -DecisionManifest $fixture.DecisionManifest -M3UBytes $fixture.M3UBytes | Out-Null
    }

    function Get-TestTreeSnapshot {
        param([Parameter(Mandatory)][string]$Root)

        return @(
            Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
                Sort-Object FullName |
                ForEach-Object {
                    [pscustomobject]@{
                        RelativePath = $_.FullName.Substring($Root.Length).TrimStart([char]92, [char]47)
                        Bytes        = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
                    }
                }
        )
    }
}

Describe 'ChannelForge web server foundation' {
    It 'imports the public status and server construction entry points' {
        Get-Command Get-ChannelForgeWebStatus, New-ChannelForgeWebServer, Start-ChannelForgeWebServer |
            Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:ServerScriptPath -PathType Leaf | Should -BeTrue
    }

    It 'constructs a loopback listener without starting it' {
        $server = New-ChannelForgeWebServer -Port 18765
        try {
            $server.Prefix | Should -Be 'http://127.0.0.1:18765/'
            $server.BindAddress | Should -Be '127.0.0.1'
            $server.Started | Should -BeFalse
            $server.Listener.IsListening | Should -BeFalse
        }
        finally {
            $server.Listener.Close()
        }
    }

    It 'uses the module repository root when invoked outside the working directory' {
        $moduleRoot = (Get-Module -Name ChannelForge | Select-Object -First 1).ModuleBase
        $expectedRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
        $server = $null

        Push-Location $TestDrive
        try {
            $server = New-ChannelForgeWebServer -Port 18766
        }
        finally {
            Pop-Location
            if ($null -ne $server) { $server.Listener.Close() }
        }

        $server.RepositoryRoot | Should -Be $expectedRoot
    }

    It 'rejects non-loopback bindings' {
        { New-ChannelForgeWebServer -BindAddress '0.0.0.0' } | Should -Throw
    }

    It 'returns safe beginner-facing status data when no lineup is accepted' {
        $status = Get-ChannelForgeWebStatus -RepositoryRoot $script:StatusRoot

        $status.Service | Should -Be 'ChannelForge'
        $status.Version | Should -Be '0.1.0'
        $status.Status | Should -Be 'ok'
        $status.Message | Should -Be 'ChannelForge is running'
        $status.LineupStatus | Should -Be 'not-accepted'
        $status.Guidance | Should -Be 'No lineup has been accepted yet'
        $status.NextAction | Should -Be 'Open Guided Setup to begin'
        $status.ReadOnly | Should -BeTrue
        $status.ProviderMutation | Should -Be 'none'
        $status.DownstreamMutation | Should -Be 'none'
        $status.GuidePublication | Should -Be 'none'
        $status.AcceptedStateMutation | Should -Be 'none'
    }

    It 'reflects accepted state without mutating the generation store' {
        $root = Join-Path $TestDrive 'accepted-status'
        New-TestAcceptedState -RepositoryRoot $root
        $before = Get-TestTreeSnapshot -Root $root

        $status = Get-ChannelForgeWebStatus -RepositoryRoot $root

        $status.LineupStatus | Should -Be 'accepted'
        $status.Guidance | Should -Be 'An accepted lineup is available'
        $status.NextAction | Should -Be 'Open Guided Setup to review'
        $status.ReadOnly | Should -BeTrue
        $status.AcceptedStateMutation | Should -Be 'none'
        $response = Get-TestWebResponse -Method GET -Path '/api/status' -RepositoryRoot $root
        ($response.Body | ConvertFrom-Json).LineupStatus | Should -Be 'accepted'
        $after = Get-TestTreeSnapshot -Root $root
        $after | ConvertTo-Json -Depth 5 | Should -Be ($before | ConvertTo-Json -Depth 5)
    }

    It 'returns safe service-unavailable responses for corrupt accepted state' {
        $root = Join-Path $TestDrive 'corrupt-status'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'state') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'state\accepted-lineup.json') -Value '{}' -NoNewline

        foreach ($path in @('/', '/health', '/api/status')) {
            $response = Get-TestWebResponse -Method GET -Path $path -RepositoryRoot $root
            $payload = $response.Body | ConvertFrom-Json

            $response.StatusCode | Should -Be 503
            $payload.Error | Should -Be 'status-unavailable'
            $payload.Message | Should -Be 'ChannelForge status is temporarily unavailable.'
        }
    }

    It 'serves the health endpoint as read-only JSON' {
        $response = Get-TestWebResponse -Method GET -Path '/health?probe=1'
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 200
        $response.ContentType | Should -Be 'application/json; charset=utf-8'
        $payload.Status | Should -Be 'ok'
        $payload.Message | Should -Be 'ChannelForge is running'
        $payload.ReadOnly | Should -BeTrue
    }

    It 'serves the status endpoint with the same safe contract' {
        $response = Get-TestWebResponse -Method HEAD -Path '/api/status'
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 200
        $payload.Service | Should -Be 'ChannelForge'
        $payload.Version | Should -Be '0.1.0'
        $payload.NextAction | Should -Be 'Open Guided Setup to begin'
    }

    It 'serves the beginner placeholder shell without exposing private data' {
        $response = Get-TestWebResponse -Method GET -Path '/'

        $response.StatusCode | Should -Be 200
        $response.ContentType | Should -Be 'text/html; charset=utf-8'
        $response.Body | Should -Match 'ChannelForge is running'
        $response.Body | Should -Match 'No lineup has been accepted yet'
        $response.Body | Should -Match 'Open Guided Setup to begin'
        $response.Body | Should -Not -Match '(?i)(https?://|ftp://|file://|ACCOUNT_ID|API_TOKEN|PASSWORD|TOKEN|SECRET|[A-Z]:[\\/]|\\\\)'
    }

    It 'rejects state-changing methods and unknown paths' {
        $methodResponse = Get-TestWebResponse -Method POST -Path '/api/status'
        $notFoundResponse = Get-TestWebResponse -Method GET -Path '/api/unknown'

        $methodResponse.StatusCode | Should -Be 405
        $methodResponse.Headers.Allow | Should -Be 'GET, HEAD'
        $notFoundResponse.StatusCode | Should -Be 404
    }
    # Status may read validated accepted metadata; it must not write any state.
    It 'does not mutate provider, downstream, guide, or accepted state' {
        $root = Join-Path $TestDrive 'state-boundary'
        $providerPath = Join-Path $root 'data\providers\provider.local.json'
        $downstreamPath = Join-Path $root 'downstream\settings.json'
        $guidePath = Join-Path $root 'data\epg\guide.xml'
        $acceptedPath = Join-Path $root 'state\accepted-lineup.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $providerPath), (Split-Path -Parent $downstreamPath), (Split-Path -Parent $guidePath), (Split-Path -Parent $acceptedPath) | Out-Null
        Set-Content -LiteralPath $providerPath -Value '{"url":"https://example.invalid/ACCOUNT_ID/API_TOKEN"}' -NoNewline
        Set-Content -LiteralPath $downstreamPath -Value '{"target":"fixture"}' -NoNewline
        Set-Content -LiteralPath $guidePath -Value '<tv></tv>' -NoNewline
        Set-Content -LiteralPath $acceptedPath -Value '{"generation":"fixture"}' -NoNewline

        $before = Get-TestTreeSnapshot -Root $root
        $null = Get-TestWebResponse -Method GET -Path '/health'
        $null = Get-TestWebResponse -Method GET -Path '/api/status'
        $null = Get-TestWebResponse -Method POST -Path '/api/status'
        $after = Get-TestTreeSnapshot -Root $root

        $after | ConvertTo-Json -Depth 5 | Should -Be ($before | ConvertTo-Json -Depth 5)
    }

    It 'does not expose secrets or private paths in status responses' {
        $statusJson = (Get-ChannelForgeWebStatus | ConvertTo-Json -Depth 5 -Compress)
        $responseJson = (Get-TestWebResponse -Method GET -Path '/api/status').Body
        $combined = "$statusJson`n$responseJson"

        $combined | Should -Not -Match '(?i)(https?://|ftp://|file://|ACCOUNT_ID|API_TOKEN|PASSWORD|TOKEN|SECRET|[A-Z]:[\\/]|\\\\)'
    }
}
