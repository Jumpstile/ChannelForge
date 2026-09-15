BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:ServerScriptPath = Join-Path $script:RepoRoot 'scripts\Start-ChannelForgeWebServer.ps1'
    Import-Module $script:ModulePath -Force

    function Get-TestWebResponse {
        param(
            [Parameter(Mandatory)][string]$Method,
            [Parameter(Mandatory)][string]$Path
        )

        $module = Get-Module -Name ChannelForge
        return & $module {
            param($RequestMethod, $RequestPath)
            Get-ChannelForgeWebResponse -Method $RequestMethod -Path $RequestPath
        } $Method $Path
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

    It 'rejects non-loopback bindings' {
        { New-ChannelForgeWebServer -BindAddress '0.0.0.0' } | Should -Throw
    }

    It 'returns safe beginner-facing status data' {
        $status = Get-ChannelForgeWebStatus

        $status.Service | Should -Be 'ChannelForge'
        $status.Version | Should -Be '0.1.0'
        $status.Status | Should -Be 'ok'
        $status.Message | Should -Be 'ChannelForge is running'
        $status.Guidance | Should -Be 'No lineup has been accepted yet'
        $status.NextAction | Should -Be 'Open Guided Setup to begin'
        $status.ReadOnly | Should -BeTrue
        $status.ProviderMutation | Should -Be 'none'
        $status.DownstreamMutation | Should -Be 'none'
        $status.GuidePublication | Should -Be 'none'
        $status.AcceptedStateMutation | Should -Be 'none'
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
