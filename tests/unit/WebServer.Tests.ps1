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
    It 'accepts an M3U-only browser proposal and removes its request workspace' {
        $root = Join-Path $TestDrive 'proposal-no-guide'
        $body = New-TestProposalBody
        $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal?source=browser' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 200
        $payload.Version | Should -Be 'guided-setup/proposal/v1'
        $payload.Proposal.GuideStatus | Should -Be 'NO_GUIDE_SELECTED'
        $payload.Safety.PublicationState | Should -Be 'CandidateOnly'
        $payload.Safety.CanPublish | Should -BeFalse
        $payload.Safety.AcceptedStateMutation | Should -Be 'none'
        $payload.Safety.ProviderMutation | Should -Be 'none'
        $payload.Safety.DownstreamMutation | Should -Be 'none'
        $payload.Safety.GuidePublication | Should -Be 'none'
        @(Get-ChildItem -LiteralPath (Join-Path $root 'output\.web-guided-setup') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
        $response.Body | Should -Not -Match '(?i)(https?://|file://|[A-Z]:[\\/]|\\\\|input\\.m3u|guide\\.xml)'
    }

    It 'accepts one XMLTV guide and leaves repository state unchanged' {
        $root = Join-Path $TestDrive 'proposal-with-guide'
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'provider.json') -Value '{"provider":"fixture"}' -NoNewline
        $before = Get-TestTreeSnapshot -Root $root
        $body = New-TestProposalBody -GuideText $guide -WithGuide
        $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $response.Body | ConvertFrom-Json
        $after = Get-TestTreeSnapshot -Root $root

        $response.StatusCode | Should -Be 200
        $payload.Proposal.GuideStatus | Should -Be 'XMLTV_SELECTED'
        $payload.Proposal.ChannelCount | Should -Be 1
        $after | ConvertTo-Json -Depth 5 | Should -Be ($before | ConvertTo-Json -Depth 5)
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
        @(Get-ChildItem -LiteralPath (Join-Path $root 'output\.web-guided-setup') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
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
    }

}
