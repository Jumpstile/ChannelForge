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

    function New-TestMultiSourceProposalBody {
        param(
            [Parameter(Mandatory)][object[]]$Playlists,
            [object[]]$Guides = @(),
            [object[]]$Bindings = @()
        )
        $playlistItems = [System.Collections.Generic.List[object]]::new()
        foreach ($source in @($Playlists)) {
            $item = [ordered]@{ sourceKey = [string]$source.Key; label = if ($null -eq $source.Label) { [string]$source.Key } else { [string]$source.Label }; priority = if ($null -eq $source.Priority) { 100 } else { [int]$source.Priority } }
            if (-not [string]::IsNullOrWhiteSpace([string]$source.Url)) { $item.url = [string]$source.Url } else { $item.contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$source.Text)) }
            [void]$playlistItems.Add([pscustomobject]$item)
        }
        $guideItems = [System.Collections.Generic.List[object]]::new()
        foreach ($source in @($Guides)) {
            $item = [ordered]@{ sourceKey = [string]$source.Key; label = if ($null -eq $source.Label) { [string]$source.Key } else { [string]$source.Label }; priority = if ($null -eq $source.Priority) { 100 } else { [int]$source.Priority } }
            if (-not [string]::IsNullOrWhiteSpace([string]$source.Url)) { $item.url = [string]$source.Url } else { $item.contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$source.Text)) }
            [void]$guideItems.Add([pscustomobject]$item)
        }
        $bindingItems = [System.Collections.Generic.List[object]]::new()
        foreach ($binding in @($Bindings)) {
            $refs = [System.Collections.Generic.List[string]]::new()
            foreach ($reference in @($binding.Playlists)) { [void]$refs.Add([string]$reference) }
            $item = [ordered]@{ guideRef = [string]$binding.Guide; playlistRefs = $refs; appliesToAll = [bool]$binding.All }
            if ($binding.ExplicitlyUnbound) { $item.explicitlyUnbound = $true }
            [void]$bindingItems.Add([pscustomobject]$item)
        }
        $payload = [ordered]@{ schemaVersion = 2; playlists = $playlistItems; guides = $guideItems; bindings = $bindingItems }
        return [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 10 -Compress))
    }

    function Complete-TestV2Acceptance {
        param(
            [Parameter(Mandatory)][string]$RepositoryRoot,
            [Parameter(Mandatory)]$ProposalPayload,
            [string]$ExpectedGuideStatus
        )
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{
                    schemaVersion = 2
                    proposalId = $ProposalPayload.Proposal.ProposalId
                    acknowledged = $true
                } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse `
            -Method POST `
            -Path '/api/guided-setup/accept' `
            -RepositoryRoot $RepositoryRoot `
            -BodyBytes $acceptBody `
            -ContentType 'application/json' `
            -ContentLength $acceptBody.Length
        $accepted.StatusCode | Should -Be 200
        $acceptedPayload = $accepted.Body | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($ExpectedGuideStatus)) {
            $acceptedPayload.Proposal.GuideStatus | Should -Be $ExpectedGuideStatus
        }

        $sessionPath = Join-Path $RepositoryRoot "output\.web-guided-setup\proposals\$($ProposalPayload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $candidatePath = Join-Path $RepositoryRoot "output\.web-guided-setup\proposals\$($ProposalPayload.Proposal.ProposalId)\$($session.CandidateDirectoryRelative -replace '/', '\')"
        $candidateManifest = Get-Content -LiteralPath (Join-Path $candidatePath 'manifest.json') -Raw | ConvertFrom-Json
        $candidateManifest.Version | Should -Be 'blocker-2-contract/v7'
        $candidateManifest.ContractVersion | Should -Be 'blocker-2-contract/v7'
        @($candidateManifest.SelectedSources).Count | Should -Be (@($session.SourceSet.Playlists).Count + @($session.SourceSet.Guides).Count)
        $expectedLogicalSourceIds = [System.Collections.Generic.List[string]]::new()
        $playlistOrdinal = 0
        foreach ($reviewed in @($session.SourceSet.Playlists | Sort-Object Priority, SourceId)) {
            [void]$expectedLogicalSourceIds.Add((& (Get-Module ChannelForge) {
                        param($Label, $Ordinal)
                        Get-ChannelForgeLogicalSourceId -ProviderName 'candidate' -SourceName $Label -SourceKind 'M3U' -SourceOrdinal $Ordinal
                    } $reviewed.Label $playlistOrdinal))
            $playlistOrdinal++
        }
        $guideOrdinal = 0
        foreach ($reviewed in @($session.SourceSet.Guides | Sort-Object Priority, SourceId)) {
            [void]$expectedLogicalSourceIds.Add((& (Get-Module ChannelForge) {
                        param($Label, $Ordinal)
                        Get-ChannelForgeLogicalSourceId -ProviderName 'candidate' -SourceName $Label -SourceKind 'XMLTV' -SourceOrdinal $Ordinal
                    } $reviewed.Label $guideOrdinal))
            $guideOrdinal++
        }
        (@($candidateManifest.SelectedSources | Sort-Object) -join '|') | Should -Be (@($expectedLogicalSourceIds | Sort-Object) -join '|')

        $enrollment = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'state\source-enrollment.json') -Raw | ConvertFrom-Json
        $assertManagedSource = {
            param($reviewed, $durable)
            if (-not [string]::IsNullOrWhiteSpace([string]$durable.ManagedPath)) {
                $managedPath = Join-Path $RepositoryRoot ([string]$durable.ManagedPath -replace '/', '\')
                $bytes = [IO.File]::ReadAllBytes($managedPath)
                $durable.ByteLength | Should -Be $bytes.Length
                $actualHash = & (Get-Module ChannelForge) {
                    param($Bytes)
                    Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $Bytes
                } $bytes
                $durable.ContentHash | Should -Be $actualHash
            }
        }
        foreach ($reviewed in @($session.SourceSet.Playlists)) {
            $durable = @($enrollment.Playlists | Where-Object SourceId -eq $reviewed.SourceId)
            $durable.Count | Should -Be 1
            $durable[0].Kind | Should -Be 'M3U'
            $durable[0].SourceKind | Should -Be $reviewed.SourceKind
            $durable[0].Label | Should -Be $reviewed.Label
            $durable[0].Priority | Should -Be $reviewed.Priority
            & $assertManagedSource $reviewed $durable[0]
            $durable[0].Url | Should -Be $reviewed.Url
        }
        foreach ($reviewed in @($session.SourceSet.Guides)) {
            $durable = @($enrollment.Guides | Where-Object SourceId -eq $reviewed.SourceId)
            $durable.Count | Should -Be 1
            $durable[0].Kind | Should -Be 'XMLTV'
            $durable[0].SourceKind | Should -Be $reviewed.SourceKind
            $durable[0].Label | Should -Be $reviewed.Label
            $durable[0].Priority | Should -Be $reviewed.Priority
            & $assertManagedSource $reviewed $durable[0]
            $durable[0].Url | Should -Be $reviewed.Url
        }
        @($enrollment.Playlists).Count | Should -Be @($session.SourceSet.Playlists).Count
        @($enrollment.Guides).Count | Should -Be @($session.SourceSet.Guides).Count
        @($enrollment.Bindings).Count | Should -Be @($session.SourceSet.Bindings).Count
        foreach ($reviewed in @($session.SourceSet.Bindings)) {
            $durable = @($enrollment.Bindings | Where-Object GuideId -eq $reviewed.GuideId)
            $durable.Count | Should -Be 1
            $durable[0].AppliesToAll | Should -Be $reviewed.AppliesToAll
            $durable[0].Revision | Should -Be $reviewed.Revision
            (@($durable[0].PlaylistIds | Sort-Object) -join '|') | Should -Be (@($reviewed.PlaylistIds | Sort-Object) -join '|')
        }

        $snapshot = & (Get-Module ChannelForge) {
            param($Root)
            Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $Root
        } $RepositoryRoot
        $snapshot.Pointer.Object.GenerationId | Should -Be $snapshot.Manifest.Object.GenerationId
        $snapshot.Pointer.Object.GenerationId | Should -Be $snapshot.State.Object.GenerationId
        $snapshot.Pointer.Object.GenerationId | Should -Be $snapshot.Output.Object.GenerationId
        $snapshot.Pointer.Object.GenerationManifestHash | Should -Be $snapshot.Manifest.Object.GenerationManifestHash
        $snapshot.Pointer.Object.AcceptedStateHash | Should -Be $snapshot.State.Object.AcceptedStateHash
        $snapshot.Pointer.Object.AcceptedOutputManifestHash | Should -Be $snapshot.Output.Object.OutputManifestHash
        return $acceptedPayload
    }

    function Initialize-TestCandidateData {
        param([Parameter(Mandatory)][string]$Root)
        $rules = Join-Path $Root 'data\rules'
        $lineup = Join-Path $Root 'data\lineup'
        New-Item -ItemType Directory -Force -Path $rules, $lineup | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $rules 'aliases.json')
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $lineup 'numbering_blocks.json')
    }

    function Invoke-TestRawHttpRequest {
        param(
            [Parameter(Mandatory)][int]$Port,
            [Parameter(Mandatory)][string]$Headers,
            [byte[]]$BodyBytes = [byte[]]::new(0),
            [switch]$ShutdownSend,
            [ValidateRange(1, 120000)]
            [int]$ResponseTimeoutMilliseconds = 15000
        )

        $client = [Net.Sockets.TcpClient]::new()
        try {
            $client.ReceiveTimeout = $ResponseTimeoutMilliseconds
            $client.SendTimeout = 3000
            $client.Connect('127.0.0.1', $Port)
            $stream = $client.GetStream()
            $requestBytes = [Text.Encoding]::ASCII.GetBytes("$Headers`r`n`r`n")
            $stream.Write($requestBytes, 0, $requestBytes.Length)
            if ($BodyBytes.Length -gt 0) {
                $stream.Write($BodyBytes, 0, $BodyBytes.Length)
            }
            $stream.Flush()
            if ($ShutdownSend) {
                $client.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
            }

            $headerBuffer = [IO.MemoryStream]::new()
            try {
                while ($true) {
                    $value = $stream.ReadByte()
                    if ($value -lt 0) { throw 'The HTTP response ended before headers were complete.' }
                    $headerBuffer.WriteByte([byte]$value)
                    if ($headerBuffer.Length -ge 4) {
                        $headerBytes = $headerBuffer.ToArray()
                        $count = $headerBytes.Length
                        if ($headerBytes[$count - 4] -eq 13 -and $headerBytes[$count - 3] -eq 10 -and $headerBytes[$count - 2] -eq 13 -and $headerBytes[$count - 1] -eq 10) {
                            break
                        }
                    }
                }
                $headerText = [Text.Encoding]::ASCII.GetString($headerBuffer.ToArray())
            }
            finally {
                $headerBuffer.Dispose()
            }

            $statusMatch = [regex]::Match($headerText, '^HTTP/\d\.\d\s+(?<Status>\d+)', [Text.RegularExpressions.RegexOptions]::Multiline)
            $lengthMatch = [regex]::Match($headerText, '(?im)^Content-Length:\s*(?<Length>\d+)')
            if (-not $statusMatch.Success -or -not $lengthMatch.Success) { throw 'The HTTP response omitted a status or Content-Length.' }
            $contentLength = [int]$lengthMatch.Groups['Length'].Value
            $responseBytes = [byte[]]::new($contentLength)
            $offset = 0
            while ($offset -lt $contentLength) {
                $read = $stream.Read($responseBytes, $offset, $contentLength - $offset)
                if ($read -le 0) { throw 'The HTTP response ended before its declared body length.' }
                $offset += $read
            }
            return [pscustomobject]@{
                StatusCode = [int]$statusMatch.Groups['Status'].Value
                Body       = [Text.Encoding]::UTF8.GetString($responseBytes)
            }
        }
        finally {
            if ($null -ne $client) { $client.Dispose() }
        }
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
        $candidateManifest = Get-Content -LiteralPath (Join-Path $candidateDirectory 'manifest.json') -Raw | ConvertFrom-Json
        $candidateManifest.Version | Should -Be 'blocker-2-contract/v8'
        $candidateManifest.ContractVersion | Should -Be 'blocker-2-contract/v8'
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
        $refresh = Get-TestWebResponse -Method POST -Path '/api/sources/refresh' -RepositoryRoot $root -BodyBytes ([byte[]]::new(0)) -ContentType 'application/json' -ContentLength 0
        $refreshPayload = $refresh.Body | ConvertFrom-Json
        $recovered = Recover-ChannelForgeAcceptedState -RepositoryRoot $root
        $duplicate = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length

        ($accepted.Body | ConvertFrom-Json).EnrollmentStatus | Should -Be 'SAVED'
        $refresh.StatusCode | Should -Be 200
        $refreshPayload.Status | Should -Be 'UP_TO_DATE'
        (Get-ChannelForgeWebStatus -RepositoryRoot $root).SourcesStatus | Should -Be 'up-to-date'
        Test-Path -LiteralPath (Join-Path $root 'state\managed-sources') | Should -BeTrue
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
        $serverLauncher = Join-Path $TestDrive 'acceptance-race-server.ps1'
        @(
            "Import-Module '$script:ModulePath' -Force"
            "Start-ChannelForgeWebServer -Port $port -RepositoryRoot '$root'"
        ) | Set-Content -LiteralPath $serverLauncher
        $server = Start-Process -FilePath ((Get-Command pwsh).Source) -ArgumentList @('-NoProfile', '-File', $serverLauncher) -WorkingDirectory $script:RepoRoot -PassThru
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



    It 'bounds actual HTTP request bodies and keeps the single-threaded listener responsive' {
        $root = Join-Path $TestDrive 'request-body-framing'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $port = 18771
        $serverLauncher = Join-Path $TestDrive 'request-body-framing-server.ps1'
        @(
            "Import-Module '$script:ModulePath' -Force"
            "Start-ChannelForgeWebServer -Port $port -RepositoryRoot '$root'"
        ) | Set-Content -LiteralPath $serverLauncher
        $server = Start-Process -FilePath ((Get-Command pwsh).Source) -ArgumentList @('-NoProfile', '-File', $serverLauncher) -WorkingDirectory $script:RepoRoot -PassThru

        try {
            $malformedResponseTimeoutMilliseconds = 3000

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

            $body = New-TestProposalBody
            $proposalHeaders = "POST /api/guided-setup/proposal HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: keep-alive`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)"
            $proposalResponse = Invoke-TestRawHttpRequest -Port $port -Headers $proposalHeaders -BodyBytes $body
            $proposalResponse.StatusCode | Should -Be 200
            $proposalPayload = $proposalResponse.Body | ConvertFrom-Json
            $proposalPayload.Status | Should -Be 'PROPOSAL_READY'

            $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $proposalPayload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
            $acceptHeaders = "POST /api/guided-setup/accept HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: keep-alive`r`nContent-Type: application/json`r`nContent-Length: $($acceptBody.Length)"
            $acceptResponse = Invoke-TestRawHttpRequest -Port $port -Headers $acceptHeaders -BodyBytes $acceptBody
            $acceptResponse.StatusCode | Should -Be 200
            ($acceptResponse.Body | ConvertFrom-Json).Status | Should -Be 'ACCEPTED'
            Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeTrue

            $shortHeaders = "POST /api/guided-setup/proposal HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`nContent-Type: application/json`r`nContent-Length: 3"
            $shortResponse = Invoke-TestRawHttpRequest -Port $port -Headers $shortHeaders -BodyBytes ([Text.Encoding]::UTF8.GetBytes('{}')) -ShutdownSend -ResponseTimeoutMilliseconds $malformedResponseTimeoutMilliseconds
            $shortResponse.StatusCode | Should -Be 400

            $oversizedHeaders = "POST /api/guided-setup/proposal HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: keep-alive`r`nContent-Type: application/json`r`nContent-Length: $((24MB) + 1)"
            $oversizedResponse = Invoke-TestRawHttpRequest -Port $port -Headers $oversizedHeaders -ResponseTimeoutMilliseconds $malformedResponseTimeoutMilliseconds
            $oversizedResponse.StatusCode | Should -Be 413

            $chunkedHeaders = "POST /api/guided-setup/proposal HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: keep-alive`r`nContent-Type: application/json`r`nTransfer-Encoding: chunked"
            $chunkedResponse = Invoke-TestRawHttpRequest -Port $port -Headers $chunkedHeaders -BodyBytes ([Text.Encoding]::ASCII.GetBytes("0`r`n`r`n")) -ResponseTimeoutMilliseconds $malformedResponseTimeoutMilliseconds
            $chunkedResponse.StatusCode | Should -Be 400

            (Invoke-TestRawHttpRequest -Port $port -Headers "GET /health HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close" -ResponseTimeoutMilliseconds $malformedResponseTimeoutMilliseconds).StatusCode | Should -Be 200
            (Invoke-TestRawHttpRequest -Port $port -Headers "GET /api/status HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close" -ResponseTimeoutMilliseconds $malformedResponseTimeoutMilliseconds).StatusCode | Should -Be 200
        }
        finally {
            if ($null -ne $server -and -not $server.HasExited) {
                $server.Kill()
                $server.WaitForExit()
            }
        }
    }

    It 'fails within a finite timeout when a connected peer never responds' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $serverClient = $null
        try {
            $listener.Start()
            $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
            $acceptTask = $listener.AcceptTcpClientAsync()
            $headers = "GET /health HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close"
            $clock = [Diagnostics.Stopwatch]::StartNew()
            try {
                {
                    Invoke-TestRawHttpRequest -Port $port -Headers $headers -ResponseTimeoutMilliseconds 250
                } | Should -Throw
            }
            finally {
                $clock.Stop()
            }
            $clock.ElapsedMilliseconds | Should -BeLessThan 3000
            if ($acceptTask.IsCompletedSuccessfully) {
                $serverClient = $acceptTask.Result
            }
        }
        finally {
            if ($null -ne $serverClient) { $serverClient.Dispose() }
            $listener.Stop()
        }
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
    It 'returns a bounded package-data error before staging a source set when required files are absent' {
        $root = Join-Path $TestDrive 'v2-missing-runtime-data'
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist })
        $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 503
        $payload.Error | Should -Be 'package-data-unavailable'
        $payload.Message | Should -Match 'Repair or reinstall'
        $response.Body | Should -Not -Match '(?i)([A-Z]:[\\/]|\\\\|stack|exception|example\\.invalid)'
        Test-Path -LiteralPath (Join-Path $root 'output\.web-guided-setup') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'accepts v2 one-source no-guide proposals through durable source enrollment' {
        $root = Join-Path $TestDrive 'v2-one-no-guide'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $proposal.StatusCode | Should -Be 200
        $payload.Version | Should -Be 'guided-setup/proposal/v2'
        $payload.Proposal.PlaylistCount | Should -Be 1
        $payload.Proposal.GuideCount | Should -Be 0
        $payload.Proposal.GuideStatus | Should -Be 'NO_GUIDE_SELECTED'
        $payload.Proposal.CanAccept | Should -BeTrue
        $acceptedPayload = Complete-TestV2Acceptance -RepositoryRoot $root -ProposalPayload $payload -ExpectedGuideStatus 'NO_GUIDE_SELECTED'
        $acceptedPayload.Version | Should -Be 'guided-setup/acceptance/v2'
        $acceptedPayload.EnrollmentStatus | Should -Be 'SAVED'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeTrue
    }

    It 'auto-binds omitted guide decisions to the sole playlist' {
        $root = Join-Path $TestDrive 'v2-one-guide'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=`"one`",One`nhttps://example.invalid/one`n"
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>One</title></programme></tv>'
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = $guide })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.BoundGuideCount | Should -Be 1
        $payload.Proposal.UnboundGuideCount | Should -Be 0
        $payload.Proposal.GuideStatus | Should -Be 'XMLTV_SELECTED'
        $payload.Proposal.ExactGuideMatchCount | Should -Be 1
        $payload.Proposal.UnmatchedPlaylistCount | Should -Be 0
        $payload.Proposal.AmbiguityCount | Should -Be 0
        $sessionPath = Join-Path $root "output\\.web-guided-setup\\proposals\\$($payload.Proposal.ProposalId)\\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $session.SourceSet.Bindings.Count | Should -Be 1
        $session.SourceSet.Bindings[0].PlaylistIds.Count | Should -Be 1
        $session.SourceSet.Bindings[0].ExplicitlyUnbound | Should -BeFalse
    }

    It 'preserves an explicit browser unbind instead of applying the one-playlist default' {
        $root = Join-Path $TestDrive 'v2-one-explicit-unbound'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        $bindings = @([pscustomobject]@{ Guide = 'g1'; Playlists = @(); All = $false; ExplicitlyUnbound = $true })
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = $guide }) -Bindings $bindings
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.BoundGuideCount | Should -Be 0
        $payload.Proposal.UnboundGuideCount | Should -Be 1
        $payload.Proposal.ExactGuideMatchCount | Should -Be 0
        $payload.Proposal.AmbiguityCount | Should -Be 0
        $payload.Proposal.GuideStatus | Should -Be 'XMLTV_UNBOUND_ACTIONABLE'
        $payload.Warnings.Code | Should -Contain 'guide-unbound-actionable'
        $payload.Proposal.CanAccept | Should -BeTrue
        $sessionPath = Join-Path $root "output\\.web-guided-setup\\proposals\\$($payload.Proposal.ProposalId)\\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $session.SourceSet.Bindings[0].ExplicitlyUnbound | Should -BeTrue
        @($session.SourceSet.Bindings[0].PlaylistIds).Count | Should -Be 0
        $session.SourceSet.Bindings[0].AppliesToAll | Should -BeFalse
    }

    It 'accepts multiple playlists and retains omitted guide bindings as actionable' {
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $playlists = @([pscustomobject]@{ Key = 'p1'; Text = $playlist }, [pscustomobject]@{ Key = 'p2'; Text = $playlist })
        $noGuideRoot = Join-Path $TestDrive 'v2-many-no-guide'
        Initialize-TestCandidateData -Root $noGuideRoot
        $noGuideBody = New-TestMultiSourceProposalBody -Playlists $playlists
        $noGuideProposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $noGuideRoot -BodyBytes $noGuideBody -ContentType 'application/json' -ContentLength $noGuideBody.Length
        $noGuidePayload = $noGuideProposal.Body | ConvertFrom-Json
        $noGuidePayload.Proposal.PlaylistCount | Should -Be 2
        $noGuidePayload.Proposal.CanAccept | Should -BeTrue
        Complete-TestV2Acceptance -RepositoryRoot $noGuideRoot -ProposalPayload $noGuidePayload -ExpectedGuideStatus 'NO_GUIDE_SELECTED' | Out-Null

        $unboundRoot = Join-Path $TestDrive 'v2-many-unbound-guides'
        Initialize-TestCandidateData -Root $unboundRoot
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        $unboundBody = New-TestMultiSourceProposalBody -Playlists $playlists -Guides @([pscustomobject]@{ Key = 'g1'; Text = $guide })
        $unboundProposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $unboundRoot -BodyBytes $unboundBody -ContentType 'application/json' -ContentLength $unboundBody.Length
        $unboundPayload = $unboundProposal.Body | ConvertFrom-Json
        $unboundPayload.Proposal.BoundGuideCount | Should -Be 0
        $unboundPayload.Proposal.UnboundGuideCount | Should -Be 1
        $unboundPayload.Proposal.ExactGuideMatchCount | Should -Be 0
        $unboundPayload.Proposal.UnmatchedPlaylistCount | Should -Be 2
        $unboundPayload.Proposal.GuideOnlyCount | Should -Be 1
        $unboundPayload.Proposal.AmbiguityCount | Should -Be 0
        $unboundPayload.Proposal.GuideStatus | Should -Be 'XMLTV_UNBOUND_ACTIONABLE'
        $unboundPayload.Proposal.CanAccept | Should -BeTrue
        @($unboundPayload.Proposal.BlockingReasons).Count | Should -Be 0
        $unboundPayload.Warnings.Code | Should -Contain 'guide-unbound-actionable'
        Complete-TestV2Acceptance -RepositoryRoot $unboundRoot -ProposalPayload $unboundPayload -ExpectedGuideStatus 'XMLTV_ACCEPTED_WITH_UNBOUND' | Out-Null
        $snapshot = & (Get-Module ChannelForge) {
            param($Root)
            Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $Root
        } $unboundRoot
        $snapshot.Output.Object.ActiveXMLTVStatus | Should -Be 'NotGenerated'
    }


    It 'scopes an explicit ALL guide to every playlist' {
        $root = Join-Path $TestDrive 'v2-explicit-all-scope'
        Initialize-TestCandidateData -Root $root
        $playlists = @(
            [pscustomobject]@{ Key = 'news'; Text = "#EXTM3U`n#EXTINF:-1 tvg-id=`"news`",News`nhttps://example.invalid/news`n" }
            [pscustomobject]@{ Key = 'sports'; Text = "#EXTM3U`n#EXTINF:-1 tvg-id=`"sports`",Sports`nhttps://example.invalid/sports`n" }
        )
        $guide = '<?xml version="1.0"?><tv><channel id="news"><display-name>News</display-name></channel><channel id="sports"><display-name>Sports</display-name></channel><programme channel="news" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme><programme channel="sports" start="20260101000000 +0000" stop="20260101010000 +0000"><title>Sports</title></programme></tv>'
        $body = New-TestMultiSourceProposalBody `
            -Playlists $playlists `
            -Guides @([pscustomobject]@{ Key = 'all-guide'; Text = $guide }) `
            -Bindings @([pscustomobject]@{ Guide = 'all-guide'; Playlists = @(); All = $true })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json

        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.BoundGuideCount | Should -Be 1
        $payload.Proposal.ExactGuideMatchCount | Should -Be 2
        $payload.Proposal.UnmatchedPlaylistCount | Should -Be 0
        $payload.Proposal.UnboundGuideCount | Should -Be 0
        $payload.Proposal.AmbiguityCount | Should -Be 0
        $payload.Proposal.CanAccept | Should -BeTrue
    }
    It 'scopes each explicit guide to its playlist lineage and retains one unbound guide' {
        $root = Join-Path $TestDrive 'v2-playlist-lineage'
        Initialize-TestCandidateData -Root $root
        $newsPlaylist = "#EXTM3U`n#EXTINF:-1 tvg-id=`"news`",News`nhttps://example.invalid/news`n"
        $sportsPlaylist = "#EXTM3U`n#EXTINF:-1 tvg-id=`"sports`",Sports`nhttps://example.invalid/sports`n"
        $newsGuide = '<?xml version="1.0"?><tv><channel id="news"><display-name>News</display-name></channel><programme channel="news" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News bulletin</title></programme></tv>'
        $sportsGuide = '<?xml version="1.0"?><tv><channel id="sports"><display-name>Sports</display-name></channel><programme channel="sports" start="20260101000000 +0000" stop="20260101010000 +0000"><title>Sports bulletin</title></programme></tv>'
        $unboundGuide = '<?xml version="1.0"?><tv><channel id="unbound-only"><display-name>Unbound only</display-name></channel><programme channel="unbound-only" start="20260101000000 +0000" stop="20260101010000 +0000"><title>Unbound bulletin</title></programme></tv>'
        $playlists = @(
            [pscustomobject]@{ Key = 'news'; Text = $newsPlaylist }
            [pscustomobject]@{ Key = 'sports'; Text = $sportsPlaylist }
        )
        $guides = @(
            [pscustomobject]@{ Key = 'news-guide'; Text = $newsGuide }
            [pscustomobject]@{ Key = 'sports-guide'; Text = $sportsGuide }
            [pscustomobject]@{ Key = 'unbound-guide'; Text = $unboundGuide }
        )
        $bindings = @(
            [pscustomobject]@{ Guide = 'news-guide'; Playlists = @('news'); All = $false }
            [pscustomobject]@{ Guide = 'sports-guide'; Playlists = @('sports'); All = $false }
            [pscustomobject]@{ Guide = 'unbound-guide'; Playlists = @(); All = $false; ExplicitlyUnbound = $true }
        )
        $body = New-TestMultiSourceProposalBody -Playlists $playlists -Guides $guides -Bindings $bindings
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json

        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.BoundGuideCount | Should -Be 2
        $payload.Proposal.ExactGuideMatchCount | Should -Be 2
        $payload.Proposal.UnmatchedPlaylistCount | Should -Be 0
        $payload.Proposal.UnboundGuideCount | Should -Be 1
        $payload.Proposal.GuideOnlyCount | Should -Be 1
        $payload.Proposal.AmbiguityCount | Should -Be 0
        $payload.Proposal.GuideStatus | Should -Be 'XMLTV_UNBOUND_ACTIONABLE'
        $payload.Warnings.Code | Should -Contain 'guide-unbound-actionable'

        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        @($session.SourceSet.Bindings | Where-Object ExplicitlyUnbound).Count | Should -Be 1
        $candidatePath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\$($session.CandidateDirectoryRelative -replace '/', '\')"
        $manifest = Get-Content -LiteralPath (Join-Path $candidatePath 'manifest.json') -Raw | ConvertFrom-Json
        $exactPairs = @($manifest.BindingRecords | Where-Object { $_.BindingKind -eq 'M3U' -and $_.Status -eq 'ExactBound' } | ForEach-Object { "$($_.M3URawId)->$($_.XMLTVId)" } | Sort-Object)
        ($exactPairs -join '|') | Should -Be 'news->news|sports->sports'

        Complete-TestV2Acceptance -RepositoryRoot $root -ProposalPayload $payload -ExpectedGuideStatus 'XMLTV_ACCEPTED_WITH_UNBOUND' | Out-Null
        $enrollment = Get-Content -LiteralPath (Join-Path $root 'state\source-enrollment.json') -Raw | ConvertFrom-Json
        @($enrollment.Guides | Where-Object Label -eq 'unbound-guide').Count | Should -Be 1
        $snapshot = & (Get-Module ChannelForge) {
            param($Root)
            Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $Root
        } $root
        $acceptedXMLTV = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $snapshot.GenerationPath 'merged.xml')))
        $acceptedXMLTV | Should -Not -Match 'unbound-only'
    }

    It 'retains review for a duplicate tvg-id collision scoped to one playlist' {
        $root = Join-Path $TestDrive 'v2-scoped-duplicate-tvg-id'
        Initialize-TestCandidateData -Root $root
        $guide = '<?xml version="1.0"?><tv><channel id="shared"><display-name>Shared</display-name></channel><programme channel="shared" start="20260101000000 +0000" stop="20260101010000 +0000"><title>Shared</title></programme></tv>'
        $playlists = @(
            [pscustomobject]@{ Key = 'selected'; Text = "#EXTM3U`n#EXTINF:-1 tvg-id=`"shared`",Selected`nhttps://example.invalid/selected`n" }
            [pscustomobject]@{ Key = 'other'; Text = "#EXTM3U`n#EXTINF:-1 tvg-id=`"shared`",Other`nhttps://example.invalid/other`n" }
        )
        $body = New-TestMultiSourceProposalBody `
            -Playlists $playlists `
            -Guides @([pscustomobject]@{ Key = 'g1'; Text = $guide }) `
            -Bindings @([pscustomobject]@{ Guide = 'g1'; Playlists = @('selected'); All = $false })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $candidatePath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\$($session.CandidateDirectoryRelative -replace '/', '\')"
        $manifest = Get-Content -LiteralPath (Join-Path $candidatePath 'manifest.json') -Raw | ConvertFrom-Json

        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.ExactGuideMatchCount | Should -Be 0
        $payload.Proposal.AmbiguityCount | Should -Be 1
        $payload.Proposal.UnmatchedPlaylistCount | Should -Be 1
        $payload.Proposal.CanAccept | Should -BeFalse
        @($manifest.BindingRecords | Where-Object { $_.BindingKind -eq 'M3U' -and $_.Status -eq 'ReviewNeeded' }).Count | Should -Be 1
        @($manifest.BindingRecords | Where-Object { $_.BindingKind -eq 'M3U' -and $_.Status -eq 'Unbound' }).Count | Should -Be 1
    }

    It 'preserves an exact explicit binding with one playlist and one guide' {
        $root = Join-Path $TestDrive 'v2-single-source-exact-binding'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=`"one`",One`nhttps://example.invalid/one`n"
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>One</title></programme></tv>'
        $body = New-TestMultiSourceProposalBody `
            -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) `
            -Guides @([pscustomobject]@{ Key = 'g1'; Text = $guide }) `
            -Bindings @([pscustomobject]@{ Guide = 'g1'; Playlists = @('p1'); All = $false })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json

        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.ExactGuideMatchCount | Should -Be 1
        $payload.Proposal.UnmatchedPlaylistCount | Should -Be 0
        $payload.Proposal.UnboundGuideCount | Should -Be 0
        $payload.Proposal.AmbiguityCount | Should -Be 0
        $payload.Proposal.CanAccept | Should -BeTrue
    }

    It 'uses source priority before stable source identity for duplicate playlist entries' {
        $root = Join-Path $TestDrive 'v2-priority-order'
        Initialize-TestCandidateData -Root $root
        $highPriority = "#EXTM3U`n#EXTINF:-1,Same Channel`nhttps://example.invalid/high`n"
        $lowPriority = "#EXTM3U`n#EXTINF:-1,Same Channel`nhttps://example.invalid/low`n"
        $body = New-TestMultiSourceProposalBody -Playlists @(
            [pscustomobject]@{ Key = 'low'; Text = $lowPriority; Priority = 200 }
            [pscustomobject]@{ Key = 'high'; Text = $highPriority; Priority = 10 }
        )
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $proposal.StatusCode | Should -Be 200
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $candidatePath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\$($session.CandidateDirectoryRelative -replace '/', '\')\merged.m3u"
        $merged = Get-Content -LiteralPath $candidatePath -Raw
        $merged | Should -Match 'https://example.invalid/high'
        $merged | Should -Not -Match 'https://example.invalid/low'
    }

    It 'accepts explicit selected and all guide bindings and reports mixed unbound guides' {
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        $playlists = @([pscustomobject]@{ Key = 'p1'; Text = $playlist }, [pscustomobject]@{ Key = 'p2'; Text = $playlist })
        $guides = @([pscustomobject]@{ Key = 'g1'; Text = $guide }, [pscustomobject]@{ Key = 'g2'; Text = $guide })
        $bindings = @([pscustomobject]@{ Guide = 'g1'; Playlists = @('p1'); All = $false }, [pscustomobject]@{ Guide = 'g2'; Playlists = @(); All = $true })
        $root = Join-Path $TestDrive 'v2-explicit-bindings'
        Initialize-TestCandidateData -Root $root
        $body = New-TestMultiSourceProposalBody -Playlists $playlists -Guides $guides -Bindings $bindings
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.BoundGuideCount | Should -Be 2
        $payload.Proposal.CanAccept | Should -BeTrue
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        @($session.SourceSet.Bindings).Count | Should -Be 2
        @($session.SourceSet.Playlists | Where-Object { $_.SourceId -match '^[0-9a-f]{64}$' }).Count | Should -Be 2
        $acceptedPayload = Complete-TestV2Acceptance -RepositoryRoot $root -ProposalPayload $payload -ExpectedGuideStatus 'XMLTV_ACCEPTED'
        $acceptedPayload.EnrollmentStatus | Should -Be 'SAVED'

        $mixedRoot = Join-Path $TestDrive 'v2-mixed-unbound'
        Initialize-TestCandidateData -Root $mixedRoot
        $mixedGuides = @($guides) + @([pscustomobject]@{ Key = 'g3'; Text = $guide })
        $mixedBody = New-TestMultiSourceProposalBody -Playlists $playlists -Guides $mixedGuides -Bindings $bindings
        $mixed = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $mixedRoot -BodyBytes $mixedBody -ContentType 'application/json' -ContentLength $mixedBody.Length
        $mixedPayload = $mixed.Body | ConvertFrom-Json
        $mixedPayload.Proposal.UnboundGuideCount | Should -Be 1
        $mixedPayload.Proposal.CanAccept | Should -BeTrue
        $mixedPayload.Warnings.Code | Should -Contain 'guide-unbound-actionable'
        Complete-TestV2Acceptance -RepositoryRoot $mixedRoot -ProposalPayload $mixedPayload -ExpectedGuideStatus 'XMLTV_ACCEPTED_WITH_UNBOUND' | Out-Null
    }

    It 'stages a supported public HTTPS playlist with local sources without exposing the URL' {
        $root = Join-Path $TestDrive 'v2-mixed-public'
        Initialize-TestCandidateData -Root $root
        Mock Open-ChannelForgeRemoteM3USourceStream -ModuleName ChannelForge -MockWith {
            [pscustomobject]@{
                Stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=remote,Remote`nhttps://example.invalid/remote`n"))
                Resources = @()
            }
        }
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $body = New-TestMultiSourceProposalBody -Playlists @(
            [pscustomobject]@{ Key = 'local'; Text = $playlist }
            [pscustomobject]@{ Key = 'remote'; Url = 'https://example.invalid/remote.m3u' }
        )
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $proposal.StatusCode | Should -Be 200
        $payload.Proposal.PlaylistCount | Should -Be 2
        $proposal.Body | Should -Not -Match 'example.invalid'
        $acceptedPayload = Complete-TestV2Acceptance -RepositoryRoot $root -ProposalPayload $payload -ExpectedGuideStatus 'NO_GUIDE_SELECTED'
        $acceptedPayload.EnrollmentStatus | Should -Be 'SAVED'
        $enrollment = Get-Content -LiteralPath (Join-Path $root 'state\source-enrollment.json') -Raw | ConvertFrom-Json
        @($enrollment.Playlists | Where-Object SourceKind -eq 'managed-file').Count | Should -Be 1
        @($enrollment.Playlists | Where-Object SourceKind -eq 'public-https').Count | Should -Be 1
        $enrollment.Playlists | Where-Object SourceKind -eq 'public-https' | Select-Object -ExpandProperty Url | Should -Be 'https://example.invalid/remote.m3u'
    }
    It 'returns a typed redacted transient-source error' {
        $root = Join-Path $TestDrive 'v2-public-source-unavailable'
        Initialize-TestCandidateData -Root $root
        Mock Open-ChannelForgeRemoteM3USourceStream -ModuleName ChannelForge -MockWith {
            throw [System.IO.IOException]::new('https://account:password@private.example.invalid/file?token=secret at C:\\private')
        }
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'remote'; Url = 'https://example.invalid/playlist.m3u' })
        $response = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $response.Body | ConvertFrom-Json

        $response.StatusCode | Should -Be 503
        $payload.Error | Should -Be 'source-unavailable'
        $payload.Message | Should -Match 'Check its URL and connection'
        $response.Body | Should -Not -Match '(?i)(example\\.invalid|password|token=|C:\\\\private|stack|exception)'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'rejects v2 duplicate references, dangling bindings, unsafe URLs, malformed content, and bounds' {
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $root = Join-Path $TestDrive 'v2-invalid'
        Initialize-TestCandidateData -Root $root
        $duplicate = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }, [pscustomobject]@{ Key = 'p1'; Text = $playlist })
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $duplicate -ContentType 'application/json').StatusCode | Should -Be 400
        $dangling = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = '<tv></tv>' }) -Bindings @([pscustomobject]@{ Guide = 'missing'; Playlists = @('p1'); All = $false })
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $dangling -ContentType 'application/json').StatusCode | Should -Be 400
        $duplicateBinding = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = '<tv></tv>' }) -Bindings @([pscustomobject]@{ Guide = 'g1'; Playlists = @('p1'); All = $false }, [pscustomobject]@{ Guide = 'g1'; Playlists = @('p1'); All = $false })
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $duplicateBinding -ContentType 'application/json').StatusCode | Should -Be 400
        $allWithRefs = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = '<tv></tv>' }) -Bindings @([pscustomobject]@{ Guide = 'g1'; Playlists = @('p1'); All = $true })
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $allWithRefs -ContentType 'application/json').StatusCode | Should -Be 400
        $emptySelected = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = '<tv></tv>' }) -Bindings @([pscustomobject]@{ Guide = 'g1'; Playlists = @(); All = $false })
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $emptySelected -ContentType 'application/json').StatusCode | Should -Be 400
        $unsafeUrl = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Url = 'https://user:password@example.invalid/a.m3u' })
        $unsafeResponse = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $unsafeUrl -ContentType 'application/json'
        $unsafeResponse.StatusCode | Should -Be 400
        ($unsafeResponse.Body | ConvertFrom-Json).Error | Should -Be 'unsupported-source'
        $queryUrl = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Url = 'https://example.invalid/a.m3u?token=secret' })
        $queryResponse = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $queryUrl -ContentType 'application/json'
        $queryResponse.StatusCode | Should -Be 400
        ($queryResponse.Body | ConvertFrom-Json).Error | Should -Be 'unsupported-source'
        $malformed = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = '#EXTM3U`nnot a playlist' })
        $malformedResponse = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $malformed -ContentType 'application/json'
        $malformedResponse.StatusCode | Should -Be 422
        ($malformedResponse.Body | ConvertFrom-Json).Error | Should -Be 'invalid-playlist'
        $invalidGuide = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) -Guides @([pscustomobject]@{ Key = 'g1'; Text = '<tv>' })
        $invalidGuideResponse = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $invalidGuide -ContentType 'application/json'
        $invalidGuideResponse.StatusCode | Should -Be 422
        ($invalidGuideResponse.Body | ConvertFrom-Json).Error | Should -Be 'invalid-guide'
        $tooMany = [System.Collections.Generic.List[object]]::new()
        1..9 | ForEach-Object { [void]$tooMany.Add([pscustomobject]@{ Key = "p$_"; Text = $playlist }) }
        $tooManyBody = New-TestMultiSourceProposalBody -Playlists $tooMany
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $tooManyBody -ContentType 'application/json').StatusCode | Should -Be 400
        $large = 'x' * (4MB + 1)
        $largeBody = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $large })
        (Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $largeBody -ContentType 'application/json').StatusCode | Should -Be 413
        @(Get-ChildItem -LiteralPath (Join-Path $root 'output\.web-guided-setup\proposals') -Directory -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'fails closed when a staged v2 playlist changes after proposal creation' {
        $root = Join-Path $TestDrive 'v2-playlist-tamper'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $proposalDirectory = Split-Path -Parent $sessionPath
        [IO.File]::AppendAllText((Join-Path $proposalDirectory ($session.SourceSet.Playlists[0].RelativePath -replace '/', '\')), "`ntampered")
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $payload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length
        $accepted.StatusCode | Should -Be 422
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\source-enrollment.json') | Should -BeFalse
    }

    It 'fails closed when a staged v2 guide changes after proposal creation' {
        $root = Join-Path $TestDrive 'v2-guide-tamper'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $guide = '<?xml version="1.0"?><tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20260101000000 +0000" stop="20260101010000 +0000"><title>News</title></programme></tv>'
        $body = New-TestMultiSourceProposalBody `
            -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist }) `
            -Guides @([pscustomobject]@{ Key = 'g1'; Text = $guide })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $proposalDirectory = Split-Path -Parent $sessionPath
        [IO.File]::AppendAllText((Join-Path $proposalDirectory ($session.SourceSet.Guides[0].RelativePath -replace '/', '\')), "`ntampered")
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $payload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length
        $accepted.StatusCode | Should -Be 422
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\source-enrollment.json') | Should -BeFalse
    }

    It 'fails closed when one source in a staged v2 multi-source proposal changes' {
        $root = Join-Path $TestDrive 'v2-multi-source-tamper'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $body = New-TestMultiSourceProposalBody -Playlists @(
            [pscustomobject]@{ Key = 'p1'; Text = $playlist }
            [pscustomobject]@{ Key = 'p2'; Text = $playlist }
        )
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $proposalDirectory = Split-Path -Parent $sessionPath
        [IO.File]::AppendAllText((Join-Path $proposalDirectory ($session.SourceSet.Playlists[1].RelativePath -replace '/', '\')), "`ntampered")
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $payload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length
        $accepted.StatusCode | Should -Be 422
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\source-enrollment.json') | Should -BeFalse
    }

    It 'fails closed when a v2 review session is tampered after proposal creation' {
        $root = Join-Path $TestDrive 'v2-session-tamper'
        Initialize-TestCandidateData -Root $root
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n"
        $body = New-TestMultiSourceProposalBody -Playlists @([pscustomobject]@{ Key = 'p1'; Text = $playlist })
        $proposal = Get-TestWebResponse -Method POST -Path '/api/guided-setup/proposal' -RepositoryRoot $root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $payload = $proposal.Body | ConvertFrom-Json
        $sessionPath = Join-Path $root "output\.web-guided-setup\proposals\$($payload.Proposal.ProposalId)\session.json"
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
        $session.SessionHash = '0' * 64
        $session | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sessionPath -NoNewline
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = $payload.Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        $accepted = Get-TestWebResponse -Method POST -Path '/api/guided-setup/accept' -RepositoryRoot $root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length
        $accepted.StatusCode | Should -Be 422
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }
}
