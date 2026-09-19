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
            [string]$RepositoryRoot = $script:StatusRoot,
            [string]$StaticRoot = '',
            [byte[]]$BodyBytes = $null,
            [string]$ContentType = '',
            [long]$ContentLength = -1
        )

        $module = Get-Module -Name ChannelForge
        return & $module {
            param($RequestMethod, $RequestPath, $RequestRoot, $RequestStaticRoot, $RequestBody, $RequestContentType, $RequestContentLength)
            Get-ChannelForgeWebResponse -Method $RequestMethod -Path $RequestPath -RepositoryRoot $RequestRoot -StaticRoot $RequestStaticRoot -BodyBytes $RequestBody -ContentType $RequestContentType -ContentLength $RequestContentLength
        } $Method $Path $RepositoryRoot $StaticRoot $BodyBytes $ContentType $ContentLength
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
    function New-TestProposalBody {
        param(
            [string]$PlaylistText = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n",
            [string]$GuideText = '',
            [switch]$WithGuide
        )

        $payload = [ordered]@{
            schemaVersion = 1
            m3u = [ordered]@{ contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PlaylistText)) }
        }
        if ($WithGuide) {
            $payload.xmltv = [ordered]@{ contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($GuideText)) }
        }
        return [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
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
            $server.StaticRoot | Should -Be (Join-Path $script:RepoRoot 'gui\dist')
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

    It 'serves the built index when the static root exists' {
        $root = Join-Path $TestDrive 'built-index'
        $staticRoot = Join-Path $root 'gui\dist'
        New-Item -ItemType Directory -Force -Path $staticRoot | Out-Null
        [IO.File]::WriteAllText((Join-Path $staticRoot 'index.html'), '<!doctype html><title>Built UI</title>')

        $response = Get-TestWebResponse -Method GET -Path '/' -RepositoryRoot $root -StaticRoot $staticRoot

        $response.StatusCode | Should -Be 200
        $response.ContentType | Should -Be 'text/html; charset=utf-8'
        $response.Body | Should -Match 'Built UI'
        $response.Body | Should -Not -Match 'No lineup has been accepted yet'
    }

    It 'serves known JavaScript and CSS assets with safe MIME types' {
        $root = Join-Path $TestDrive 'built-assets'
        $staticRoot = Join-Path $root 'gui\dist'
        $assets = Join-Path $staticRoot 'assets'
        New-Item -ItemType Directory -Force -Path $assets | Out-Null
        [IO.File]::WriteAllText((Join-Path $assets 'app.js'), 'window.__CHANNELFORGE_TEST__ = true;')
        [IO.File]::WriteAllText((Join-Path $assets 'app.css'), 'body { color: green; }')
        [IO.File]::WriteAllBytes((Join-Path $assets 'app.png'), [byte[]](0, 255, 128, 10))

        $js = Get-TestWebResponse -Method GET -Path '/assets/app.js' -RepositoryRoot $root -StaticRoot $staticRoot
        $jsHead = Get-TestWebResponse -Method HEAD -Path '/assets/app.js' -RepositoryRoot $root -StaticRoot $staticRoot
        $css = Get-TestWebResponse -Method GET -Path '/assets/app.css' -RepositoryRoot $root -StaticRoot $staticRoot
        $png = Get-TestWebResponse -Method GET -Path '/assets/app.png' -RepositoryRoot $root -StaticRoot $staticRoot
        $post = Get-TestWebResponse -Method POST -Path '/assets/app.js' -RepositoryRoot $root -StaticRoot $staticRoot

        $js.StatusCode | Should -Be 200
        $js.ContentType | Should -Be 'text/javascript; charset=utf-8'
        $js.Body | Should -Match '__CHANNELFORGE_TEST__'
        $jsHead.StatusCode | Should -Be $js.StatusCode
        $jsHead.ContentType | Should -Be $js.ContentType
        $jsHead.Body | Should -Be $js.Body
        $css.StatusCode | Should -Be 200
        $css.ContentType | Should -Be 'text/css; charset=utf-8'
        $css.Body | Should -Match 'color: green'
        $post.StatusCode | Should -Be 405
        $post.Headers.Allow | Should -Be 'GET, HEAD'
        $png.StatusCode | Should -Be 200
        $png.ContentType | Should -Be 'image/png'
        $png.Body | Should -Be ''
        [Convert]::ToBase64String($png.Bytes) | Should -Be 'AP+A Cg=='.Replace(' ', '')
    }

    It 'rejects traversal, directory listing, unsupported assets, and unsafe roots' {
        $root = Join-Path $TestDrive 'static-boundary'
        $staticRoot = Join-Path $root 'gui\dist'
        $outsideRoot = Join-Path $TestDrive 'outside-static'
        New-Item -ItemType Directory -Force -Path $staticRoot, $outsideRoot | Out-Null
        [IO.File]::WriteAllText((Join-Path $staticRoot 'index.html'), 'safe index')
        [IO.File]::WriteAllText((Join-Path $outsideRoot 'index.html'), 'private outside file')
        [IO.File]::WriteAllText((Join-Path $staticRoot 'notes.txt'), 'not a web asset')

        foreach ($path in @('/%2e%2e/index.html', '/assets/%2e%2e/index.html', '/index.html%00.js', '/')) {
            $response = Get-TestWebResponse -Method GET -Path $path -RepositoryRoot $root -StaticRoot $staticRoot
            if ($path -eq '/') {
                $response.Body | Should -Match 'safe index'
            } else {
                $response.StatusCode | Should -Be 404
            }
        }

        (Get-TestWebResponse -Method GET -Path '/notes.txt' -RepositoryRoot $root -StaticRoot $staticRoot).StatusCode | Should -Be 404
        (Get-TestWebResponse -Method GET -Path '/' -RepositoryRoot $root -StaticRoot $outsideRoot).Body | Should -Not -Match 'private outside file'
        (Get-TestWebResponse -Method GET -Path '/gui/' -RepositoryRoot $root -StaticRoot $staticRoot).StatusCode | Should -Be 404
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
    It 'accepts an M3U-only browser proposal and persists an opaque review session' {
        $root = Join-Path $TestDrive 'proposal-no-guide'
        $body = New-TestProposalBody
        $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal?source=browser' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 200
        $payload.Version | Should -Be 'guided-setup/proposal/v1'
        $payload.Proposal.ProposalId | Should -Match '^[0-9a-f]{32}$'
        $payload.Proposal.GuideStatus | Should -Be 'NO_GUIDE_SELECTED'
        $payload.Proposal.CanAccept | Should -BeTrue
        $payload.Safety.PublicationState | Should -Be 'CandidateOnly'
        $payload.Safety.CanPublish | Should -BeFalse
        $payload.Safety.AcceptedStateMutation | Should -Be 'none'
        $payload.Safety.ProviderMutation | Should -Be 'none'
        $payload.Safety.DownstreamMutation | Should -Be 'none'
        $payload.Safety.GuidePublication | Should -Be 'none'
        $response.Body | Should -Not -Match '(?i)(https?://|file://|[A-Z]:[\\/]|\\\\|input\\.m3u|guide\\.xml|CandidateManifestHash|BuildIdentity)'
        $proposalRoot = Join-Path $root 'output\.web-guided-setup\proposals'
        @(Get-ChildItem -LiteralPath $proposalRoot -Directory -Force).Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $proposalRoot "$($payload.Proposal.ProposalId)\session.json") -PathType Leaf | Should -BeTrue
    }

    It 'accepts one XMLTV guide and persists only the server-owned review package' {
        $root = Join-Path $TestDrive 'proposal-with-guide'
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'provider.json') -Value '{"provider":"fixture"}' -NoNewline
        $body = New-TestProposalBody -GuideText $guide -WithGuide
        $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 200
        $payload.Proposal.GuideStatus | Should -Be 'XMLTV_SELECTED'
        $payload.Proposal.ChannelCount | Should -Be 1
        $payload.Proposal.ProposalId | Should -Match '^[0-9a-f]{32}$'
        Test-Path -LiteralPath (Join-Path $root 'provider.json') -PathType Leaf | Should -BeTrue
        $response.Body | Should -Not -Match '(?i)(https?://|file://|[A-Z]:[\\/]|\\\\|input\\.m3u|guide\\.xml)'
        $proposalDirectory = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)"
        Test-Path -LiteralPath (Join-Path $proposalDirectory 'candidate-output') -PathType Container | Should -BeTrue
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $payload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length
        $accepted.StatusCode | Should -Be 200
        ($accepted.Body | ConvertFrom-Json).Proposal.GuideStatus | Should -Be 'XMLTV_ACCEPTED'
        $session = Get-Content -LiteralPath (Join-Path $proposalDirectory 'session.json') -Raw | ConvertFrom-Json
        $candidateDirectory = Join-Path $proposalDirectory ($session.CandidateDirectoryRelative -replace '/', '\')
        $pointer = Get-Content -LiteralPath (Join-Path $root 'state\accepted-lineup.json') -Raw | ConvertFrom-Json
        $acceptedGeneration = Join-Path $root "state\generations\$($pointer.GenerationId)"
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $candidateDirectory 'merged.m3u'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $acceptedGeneration 'merged.m3u'))))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $candidateDirectory 'merged.xml'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $acceptedGeneration 'merged.xml'))))
    }

    It 'fails closed for unsupported content, duplicate or unknown properties, and malformed uploads' {
        $root = Join-Path $TestDrive 'proposal-invalid'
        $valid = New-TestProposalBody
        $duplicate = [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"m3u":{"contentBase64":"QQ=="},"m3u":{"contentBase64":"QQ=="}}')
        $unknown = [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"root":"C:\\private","m3u":{"contentBase64":"QQ=="}}')
        foreach ($body in @([Text.Encoding]::UTF8.GetBytes('{'), $duplicate, $unknown)) {
            $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json'
            $response.StatusCode | Should -Be 400
            $response.Body | Should -Not -Match '(?i)(C:\\\\private|[A-Z]:[\\\\/]|stack|exception)'
        }
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $valid -ContentType 'text/plain').StatusCode | Should -Be 415
        $malformed = New-TestProposalBody -PlaylistText '#EXTM3U`nnot a playlist'
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $malformed -ContentType 'application/json').StatusCode | Should -Be 422
        $empty = New-TestProposalBody -PlaylistText "#EXTM3U`n"
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $empty -ContentType 'application/json').StatusCode | Should -Be 422
        @(Get-ChildItem -LiteralPath (Join-Path $root 'output\.web-guided-setup\proposals') -Directory -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
    It 'accepts an acknowledged browser proposal through the immutable generation path and rejects duplicate submission' {
        $root = Join-Path $TestDrive 'acceptance-end-to-end'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'provider.json') -Value '{"provider":"fixture"}' -NoNewline
        $body = New-TestProposalBody
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $proposalPayload = $proposal.Body | ConvertFrom-Json
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $proposalPayload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length
        $acceptedPointer = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'state\accepted-lineup.json')))
        $recovered = Recover-ChannelForgeAcceptedState -RepositoryRoot $root
        $duplicate = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length

        $accepted.StatusCode | Should -Be 200
        ($accepted.Body | ConvertFrom-Json).Status | Should -Be 'ACCEPTED'
        $recovered.Outcome | Should -Be 'NEW'
        (Get-ChannelForgeWebStatus -RepositoryRoot $root).LineupStatus | Should -Be 'accepted'
        Test-Path -LiteralPath (Join-Path $root 'output\guided-setup') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'provider.json') | Should -BeTrue
        $duplicate.StatusCode | Should -Be 409
        ($duplicate.Body | ConvertFrom-Json).Error | Should -Be 'already-accepted'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'state\accepted-lineup.json'))) | Should -Be $acceptedPointer
    }
    It 'serializes truly concurrent acceptance requests into one coherent generation' {
        $root = Join-Path $TestDrive 'acceptance-concurrent-race'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $providerBytes = [Text.Encoding]::UTF8.GetBytes('{"provider":"race-fixture"}')
        [IO.File]::WriteAllBytes((Join-Path $root 'provider.json'), $providerBytes)
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        $proposalBody = New-TestProposalBody -GuideText $guide -WithGuide
        $port = 18769
        $serverStdout = Join-Path $TestDrive 'acceptance-race-server.out'
        $serverStderr = Join-Path $TestDrive 'acceptance-race-server.err'
        $serverLauncher = Join-Path $TestDrive 'acceptance-race-server.ps1'
        @(
            "Import-Module '$script:ModulePath' -Force"
            "Start-ChannelForgeWebServer -Port $port -RepositoryRoot '$root'"
        ) | Set-Content -LiteralPath $serverLauncher
        $server = Start-Process -FilePath ((Get-Command pwsh).Source) -ArgumentList @('-NoProfile', '-File', $serverLauncher) -WorkingDirectory $script:RepoRoot -RedirectStandardOutput $serverStdout -RedirectStandardError $serverStderr -PassThru
        try {
            $ready = $false
            for ($attempt = 0; $attempt -lt 100 -and -not $ready; $attempt++) {
                if ($server.HasExited) { break }
                $tcp = $null
                try {
                    $tcp = [Net.Sockets.TcpClient]::new()
                    $tcp.Connect('127.0.0.1', $port)
                    $ready = $true
                }
                catch {}
                finally {
                    if ($null -ne $tcp) { $tcp.Dispose() }
                }
                if (-not $ready) { Start-Sleep -Milliseconds 100 }
            }
            $ready | Should -BeTrue

            $baseUri = "http://127.0.0.1:$port"
            $proposalResponse = Invoke-WebRequest -Uri "$baseUri/api/guided-setup/proposal" -Method POST -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetString($proposalBody)) -SkipHttpErrorCheck
            $proposalResponse.StatusCode | Should -Be 200
            $proposalPayload = $proposalResponse.Content | ConvertFrom-Json
            $proposalId = [string]$proposalPayload.Proposal.ProposalId
            $proposalId | Should -Match '^[0-9a-f]{32}$'
            $acceptBody = (@{ schemaVersion = 1; proposalId = $proposalId; acknowledged = $true } | ConvertTo-Json -Compress)
            $acceptUri = "$baseUri/api/guided-setup/accept"
            $acceptScript = {
                param($Uri, $Body)
                $response = Invoke-WebRequest -Uri $Uri -Method POST -ContentType 'application/json' -Body $Body -SkipHttpErrorCheck
                [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = [string]$response.Content }
            }
            $jobs = @(
                Start-Job -ScriptBlock $acceptScript -ArgumentList $acceptUri, $acceptBody
                Start-Job -ScriptBlock $acceptScript -ArgumentList $acceptUri, $acceptBody
            )
            try {
                Wait-Job -Job $jobs -Timeout 60 | Should -Not -BeNullOrEmpty
                $results = @(Receive-Job -Job $jobs)
            }
            finally {
                Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
            }

            $results.Count | Should -Be 2
            @($results | Where-Object StatusCode -eq 200).Count | Should -Be 1
            $conflicts = @($results | Where-Object StatusCode -ne 200)
            $conflicts.Count | Should -Be 1
            @(409, 422) | Should -Contain $conflicts[0].StatusCode
            $conflictPayload = $conflicts[0].Body | ConvertFrom-Json
            @('already-accepted', 'stale-proposal', 'acceptance-unavailable') | Should -Contain $conflictPayload.Error

            $generationDirectories = @(Get-ChildItem -LiteralPath (Join-Path $root 'state\generations') -Directory)
            $generationDirectories.Count | Should -Be 1
            $pointer = Get-Content -LiteralPath (Join-Path $root 'state\accepted-lineup.json') -Raw | ConvertFrom-Json
            $generationDirectory = $generationDirectories[0].FullName
            $generation = Get-Content -LiteralPath (Join-Path $generationDirectory 'generation.manifest.json') -Raw | ConvertFrom-Json
            $state = Get-Content -LiteralPath (Join-Path $generationDirectory 'accepted-state.json') -Raw | ConvertFrom-Json
            $output = Get-Content -LiteralPath (Join-Path $generationDirectory 'accepted-output.manifest.json') -Raw | ConvertFrom-Json
            $pointer.GenerationId | Should -Be $generation.GenerationId
            $pointer.GenerationManifestHash | Should -Be $generation.GenerationManifestHash
            $pointer.AcceptedStateHash | Should -Be $state.AcceptedStateHash
            $pointer.AcceptedOutputManifestHash | Should -Be $output.OutputManifestHash
            $generation.AcceptedStateHash | Should -Be $state.AcceptedStateHash
            $generation.AcceptedOutputManifestHash | Should -Be $output.OutputManifestHash
            $journal = Get-Content -LiteralPath (Join-Path $root 'state\accepted-lineup.journal.json') -Raw | ConvertFrom-Json
            $journal.JournalStage | Should -Be 'Committed'
            $recovery = Recover-ChannelForgeAcceptedState -RepositoryRoot $root
            $recovery.Outcome | Should -Be 'NEW'
            $recovery.JournalStage | Should -Be 'Committed'

            $proposalDirectory = Join-Path $root "output\.web-guided-setup\proposals\$proposalId"
            $session = Get-Content -LiteralPath (Join-Path $proposalDirectory 'session.json') -Raw | ConvertFrom-Json
            $candidateDirectory = Join-Path $proposalDirectory ($session.CandidateDirectoryRelative -replace '/', '\')
            [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $candidateDirectory 'merged.m3u'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $generationDirectory 'merged.m3u'))))
            [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $candidateDirectory 'merged.xml'))) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $generationDirectory 'merged.xml'))))
            [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'provider.json'))) | Should -Be ([Convert]::ToBase64String($providerBytes))
            Test-Path -LiteralPath (Join-Path $root 'output\merged.m3u') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'output\merged.xml') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'config\scheduled-refresh.json') | Should -BeFalse
        }
        finally {
            if ($null -ne $server -and -not $server.HasExited) {
                $server.Kill()
                $server.WaitForExit()
            }
        }
    }


    It 'fails closed when a reviewed parent becomes stale' {
        $root = Join-Path $TestDrive 'acceptance-stale-parent'
        $body = New-TestProposalBody
        $first = (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length).Body | ConvertFrom-Json
        $second = (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length).Body | ConvertFrom-Json
        $firstBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $first.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $secondBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $second.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $firstBody -ContentType 'application/json' -ContentLength $firstBody.Length).StatusCode | Should -Be 200
        $stale = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $secondBody -ContentType 'application/json' -ContentLength $secondBody.Length

        $stale.StatusCode | Should -Be 409
        ($stale.Body | ConvertFrom-Json).Error | Should -Be 'stale-proposal'
        (Get-ChannelForgeWebStatus -RepositoryRoot $root).LineupStatus | Should -Be 'accepted'
    }

    It 'blocks ambiguous browser reviews at the server acceptance boundary' {
        $root = Join-Path $TestDrive 'acceptance-ambiguous'
        $playlist = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u') -Raw
        $guide = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml') -Raw
        $body = New-TestProposalBody -PlaylistText $playlist -GuideText $guide -WithGuide
        $proposal = (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length).Body | ConvertFrom-Json
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $proposal.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length

        $proposal.Proposal.AmbiguityCount | Should -BeGreaterThan 0
        $proposal.Proposal.CanAccept | Should -BeFalse
        $accepted.StatusCode | Should -Be 409
        ($accepted.Body | ConvertFrom-Json).Error | Should -Be 'proposal-blocked'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'fails closed when reviewed candidate bytes change or disappear' {
        $tamperedRoot = Join-Path $TestDrive 'acceptance-tampered-candidate'
        $tamperedBody = New-TestProposalBody
        $tamperedProposal = (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $tamperedRoot -BodyBytes $tamperedBody -ContentType 'application/json' -ContentLength $tamperedBody.Length).Body | ConvertFrom-Json
        $tamperedProposalDirectory = Join-Path $tamperedRoot "output\.web-guided-setup\proposals\$($tamperedProposal.Proposal.ProposalId)"
        $tamperedSession = Get-Content -LiteralPath (Join-Path $tamperedProposalDirectory 'session.json') -Raw | ConvertFrom-Json
        $tamperedDirectory = Join-Path $tamperedProposalDirectory ($tamperedSession.CandidateDirectoryRelative -replace '/', '\')
        [IO.File]::WriteAllText((Join-Path $tamperedDirectory 'merged.m3u'), '#tampered', [Text.UTF8Encoding]::new($false))
        $tamperedAcceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $tamperedProposal.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $tamperedAccepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $tamperedRoot -BodyBytes $tamperedAcceptBody -ContentType 'application/json' -ContentLength $tamperedAcceptBody.Length

        $missingRoot = Join-Path $TestDrive 'acceptance-missing-candidate'
        $missingBody = New-TestProposalBody
        $missingProposal = (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $missingRoot -BodyBytes $missingBody -ContentType 'application/json' -ContentLength $missingBody.Length).Body | ConvertFrom-Json
        $missingProposalDirectory = Join-Path $missingRoot "output\.web-guided-setup\proposals\$($missingProposal.Proposal.ProposalId)"
        $missingSession = Get-Content -LiteralPath (Join-Path $missingProposalDirectory 'session.json') -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath (Join-Path $missingProposalDirectory ($missingSession.CandidateDirectoryRelative -replace '/', '\')) -Recurse -Force
        $missingAcceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $missingProposal.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $missingAccepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $missingRoot -BodyBytes $missingAcceptBody -ContentType 'application/json' -ContentLength $missingAcceptBody.Length

        $tamperedAccepted.StatusCode | Should -Be 422
        ($tamperedAccepted.Body | ConvertFrom-Json).Error | Should -Be 'acceptance-unavailable'
        $missingAccepted.StatusCode | Should -Be 422
        ($missingAccepted.Body | ConvertFrom-Json).Error | Should -Be 'acceptance-unavailable'
        Test-Path -LiteralPath (Join-Path $tamperedRoot 'state\accepted-lineup.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $missingRoot 'state\accepted-lineup.json') | Should -BeFalse
    }



    It 'enforces exact POST allowlisting, declared length, and request size limits' {
        $root = Join-Path $TestDrive 'proposal-bounds'
        $body = New-TestProposalBody
        $get = Get-TestWebResponse -Method GET -Path '/api/guided-setup/proposal' -RepositoryRoot $root
        $head = Get-TestWebResponse -Method HEAD -Path '/api/guided-setup/proposal' -RepositoryRoot $root
        $get.StatusCode | Should -Be 405
        $get.Headers.Allow | Should -Be 'POST'
        $head.StatusCode | Should -Be 405
        (Get-TestWebResponse -Method POST -Path '/health' -RepositoryRoot $root -BodyBytes $body).StatusCode | Should -Be 405
        (Get-TestWebResponse -Method POST -Path '/api/status' -RepositoryRoot $root -BodyBytes $body).StatusCode | Should -Be 405
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength ($body.Length + 1)).StatusCode | Should -Be 400
        $oversized = [byte[]]::new((24MB) + 1)
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $oversized -ContentType 'application/json' -ContentLength $oversized.Length).StatusCode | Should -Be 413
        $acceptGet = Get-TestWebResponse -Method GET -Path '/api/guided-setup/accept' -RepositoryRoot $root
        $acceptGet.StatusCode | Should -Be 405
        $acceptGet.Headers.Allow | Should -Be 'POST'
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength ($body.Length + 1)).StatusCode | Should -Be 400
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $body -ContentType 'text/plain' -ContentLength $body.Length).StatusCode | Should -Be 415
        $oversizedAccept = [byte[]]::new(8193)
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $oversizedAccept -ContentType 'application/json' -ContentLength $oversizedAccept.Length).StatusCode | Should -Be 413
        $unknownAccept = [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"proposalId":"00000000000000000000000000000000","acknowledged":true,"force":true}')
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $unknownAccept -ContentType 'application/json' -ContentLength $unknownAccept.Length).StatusCode | Should -Be 400
        $unacknowledged = [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"proposalId":"00000000000000000000000000000000","acknowledged":false}')
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $unacknowledged -ContentType 'application/json' -ContentLength $unacknowledged.Length).StatusCode | Should -Be 400
    }

}
