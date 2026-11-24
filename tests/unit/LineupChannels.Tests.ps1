BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function Get-LineupResponse {
        param([Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root, [byte[]]$BodyBytes = $null, [string]$ContentType = '', [long]$ContentLength = -1)
        return & (Get-Module ChannelForge) {
            param($Method, $Path, $Root, $BodyBytes, $ContentType, $ContentLength)
            Get-ChannelForgeWebResponse -Method $Method -Path $Path -RepositoryRoot $Root -StaticRoot '' -BodyBytes $BodyBytes -ContentType $ContentType -ContentLength $ContentLength
        } $Method $Path $Root $BodyBytes $ContentType $ContentLength
    }

    function Initialize-LineupRoot {
        param([Parameter(Mandatory)][string]$Root, [string]$GuideText = '')
        $playlist = @(
            '#EXTM3U'
            '#EXTINF:-1 tvg-id="one" tvg-logo="https://logo.example/one.png?token=logo-secret" tvg-chno="5" group-title="News",Alpha News'
            'https://user:pass-secret@stream.example/live/one.m3u8?token=stream-secret'
            '#EXTINF:-1 group-title="Movies",Beta Movies'
            'https://stream.example/live/two.m3u8?token=stream-secret'
            '#EXTINF:-1 tvg-id="three" tvg-logo="https://logo.example/three.png" group-title="News",Gamma Daily'
            'https://stream.example/live/three.m3u8?token=stream-secret'
        ) -join "`n"
        $payload = [ordered]@{ schemaVersion = 1; m3u = [ordered]@{ contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($playlist + "`n")) } }
        if ($GuideText) { $payload.xmltv = [ordered]@{ contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($GuideText)) } }
        $body = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress -Depth 4))
        $proposal = Get-LineupResponse -Method POST -Path '/api/guided-setup/proposal' -Root $Root -BodyBytes $body -ContentType 'application/json' -ContentLength $body.Length
        $proposal.StatusCode | Should -Be 200
        $acceptBody = [Text.Encoding]::UTF8.GetBytes((@{ schemaVersion = 1; proposalId = ($proposal.Body | ConvertFrom-Json).Proposal.ProposalId; acknowledged = $true } | ConvertTo-Json -Compress))
        (Get-LineupResponse -Method POST -Path '/api/guided-setup/accept' -Root $Root -BodyBytes $acceptBody -ContentType 'application/json' -ContentLength $acceptBody.Length).StatusCode | Should -Be 200
    }

    function Get-LineupGuideText {
        $fmt = { param($t) $t.ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture) + ' +0000' }
        $now = [datetimeoffset]::UtcNow
        $p = { param($a, $b, $title) "<programme start=`"$(& $fmt $now.AddMinutes($a))`" stop=`"$(& $fmt $now.AddMinutes($b))`" channel=`"one`"><title>$title</title><desc>password=private-value</desc></programme>" }
        return "<tv><channel id=`"one`"><display-name>One</display-name></channel>$(& $p -10 50 'Live Show')$(& $p 50 110 'Next Show')</tv>"
    }
}

Describe 'Lineup channels route' {
    It 'lists accepted channels with now and next, never leaks secrets, and writes nothing' {
        $root = Join-Path $TestDrive 'lineup-ok'
        Initialize-LineupRoot -Root $root -GuideText (Get-LineupGuideText)
        $before = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object { '{0}|{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash })

        $response = Get-LineupResponse -Method GET -Path '/api/lineup/channels' -Root $root
        $payload = $response.Body | ConvertFrom-Json
        $after = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object { '{0}|{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash })

        $response.StatusCode | Should -Be 200
        $payload.total | Should -Be 3
        $payload.generation | Should -Match '^[a-f0-9]{64}$'
        $alpha = $payload.items | Where-Object name -eq 'Alpha News'
        $alpha.programmeState | Should -Be 'current'
        $alpha.current.title | Should -Be 'Live Show'
        $alpha.next.title | Should -Be 'Next Show'
        $alpha.guideState | Should -Be 'bound'
        $beta = $payload.items | Where-Object name -eq 'Beta Movies'
        $beta.guideState | Should -Be 'none'
        $beta.programmeState | Should -Be 'no-guide'
        $beta.attention | Should -Contain 'no-guide'
        $beta.attention | Should -Contain 'no-logo'
        ($payload.items | Where-Object name -eq 'Gamma Daily').programmeState | Should -Be 'no-programme'
        foreach ($secret in 'secret', 'private-value', 'stream.example', 'logo.example', 'http') { $response.Body | Should -Not -BeLike "*$secret*" }
        $after | Should -Be $before
    }

    It 'says when the lineup was saved, from the accepted state time' {
        $root = Join-Path $TestDrive 'lineup-saved'
        Initialize-LineupRoot -Root $root

        $payload = (Get-LineupResponse -Method GET -Path '/api/lineup/channels' -Root $root).Body | ConvertFrom-Json -DateKind String
        $payload.savedAtUtc | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
        ([datetimeoffset]::Parse($payload.savedAtUtc, [Globalization.CultureInfo]::InvariantCulture) - [datetimeoffset]::UtcNow).Duration() | Should -BeLessThan ([timespan]::FromHours(1))
    }

    It 'gives no saved date when the accepted state has none' {
        $result = & (Get-Module ChannelForge) {
            @(
                (Get-ChannelForgeWebLineupSavedAt -Snapshot ([pscustomobject]@{ State = [pscustomobject]@{ Object = [pscustomobject]@{ AcceptedAtUtc = '' } } })),
                (Get-ChannelForgeWebLineupSavedAt -Snapshot ([pscustomobject]@{ State = [pscustomobject]@{ Object = [pscustomobject]@{} } })),
                (Get-ChannelForgeWebLineupSavedAt -Snapshot ([pscustomobject]@{ State = [pscustomobject]@{ Object = [pscustomobject]@{ AcceptedAtUtc = '2026-11-24T10:00:00Z' } } }))
            )
        }
        $result[0] | Should -BeNullOrEmpty
        $result[1] | Should -BeNullOrEmpty
        $result[2] | Should -Be '2026-11-24T10:00:00Z'
    }

    It 'shows a pinned logo as pinned, leaks no pin link, and ignores a corrupt pin file' {
        $root = Join-Path $TestDrive 'lineup-pinned'
        Initialize-LineupRoot -Root $root
        Set-ChannelForgeLogoPin -TvgId 'one' -Logo 'https://pin.example/one.png' -RepositoryRoot $root | Out-Null

        $response = Get-LineupResponse -Method GET -Path '/api/lineup/channels' -Root $root
        $items = ($response.Body | ConvertFrom-Json).items
        ($items | Where-Object name -eq 'Alpha News').logoStatus | Should -Be 'pinned'
        ($items | Where-Object name -eq 'Beta Movies').logoStatus | Should -Be 'missing'
        ($items | Where-Object name -eq 'Gamma Daily').logoStatus | Should -Be 'present'
        $response.Body | Should -Not -BeLike '*pin.example*'

        $pinFile = Join-Path $root 'state\logo-pins.json'
        Set-Content -LiteralPath $pinFile -Value '{not json' -Encoding utf8
        $items = ((Get-LineupResponse -Method GET -Path '/api/lineup/channels' -Root $root).Body | ConvertFrom-Json).items
        ($items | Where-Object name -eq 'Alpha News').logoStatus | Should -Be 'present'
    }

    It 'filters on the server and pages against one accepted lineup' {
        $root = Join-Path $TestDrive 'lineup-paging'
        Initialize-LineupRoot -Root $root
        $first = (Get-LineupResponse -Method GET -Path '/api/lineup/channels?limit=2' -Root $root).Body | ConvertFrom-Json
        $second = (Get-LineupResponse -Method GET -Path "/api/lineup/channels?limit=2&offset=2&generation=$($first.generation)" -Root $root).Body | ConvertFrom-Json
        $group = (Get-LineupResponse -Method GET -Path '/api/lineup/channels?group=Movies' -Root $root).Body | ConvertFrom-Json
        $review = (Get-LineupResponse -Method GET -Path '/api/lineup/channels?attention=needs-review' -Root $root).Body | ConvertFrom-Json
        $search = (Get-LineupResponse -Method GET -Path '/api/lineup/channels?search=gamma' -Root $root).Body | ConvertFrom-Json
        $stale = Get-LineupResponse -Method GET -Path ('/api/lineup/channels?offset=1&generation=' + ('0' * 64)) -Root $root

        @($first.items).Count | Should -Be 2
        @($second.items).Count | Should -Be 1
        $first.total | Should -Be 3
        $group.items.name | Should -Be 'Beta Movies'
        $review.items.name | Should -Be 'Beta Movies'
        $search.items.name | Should -Be 'Gamma Daily'
        $stale.StatusCode | Should -Be 409
    }

    It 'rejects bad queries, other methods, and a missing accepted lineup' {
        $root = Join-Path $TestDrive 'lineup-errors'
        (Get-LineupResponse -Method GET -Path '/api/lineup/channels' -Root $root).StatusCode | Should -Be 503
        Initialize-LineupRoot -Root $root
        foreach ($bad in 'limit=0', 'limit=101', 'offset=1', 'attention=maybe', 'path=C:%5Cx', 'limit=1&limit=2') {
            (Get-LineupResponse -Method GET -Path "/api/lineup/channels?$bad" -Root $root).StatusCode | Should -Be 400
        }
        (Get-LineupResponse -Method DELETE -Path '/api/lineup/channels' -Root $root).StatusCode | Should -Be 405
    }

    It 'adds programmes for an optional UTC window and leaves the default response alone' {
        $root = Join-Path $TestDrive 'lineup-window'
        Initialize-LineupRoot -Root $root -GuideText (Get-LineupGuideText)
        $fmt = { param($m) [datetimeoffset]::UtcNow.AddMinutes($m).ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
        $all = (Get-LineupResponse -Method GET -Path "/api/lineup/channels?from=$(& $fmt 0)&to=$(& $fmt 180)" -Root $root).Body | ConvertFrom-Json
        $later = (Get-LineupResponse -Method GET -Path "/api/lineup/channels?from=$(& $fmt 70)&to=$(& $fmt 100)" -Root $root).Body | ConvertFrom-Json
        $paged = (Get-LineupResponse -Method GET -Path "/api/lineup/channels?limit=1&offset=1&generation=$($all.generation)&from=$(& $fmt 0)&to=$(& $fmt 180)" -Root $root).Body | ConvertFrom-Json
        $default = (Get-LineupResponse -Method GET -Path '/api/lineup/channels' -Root $root).Body

        ($all.items | Where-Object name -eq 'Alpha News').programmes.title | Should -Be @('Live Show', 'Next Show')
        ($all.items | Where-Object name -eq 'Beta Movies').programmes | Should -HaveCount 0
        ($all.items | Where-Object name -eq 'Gamma Daily').programmes | Should -HaveCount 0
        ($later.items | Where-Object name -eq 'Alpha News').programmes.title | Should -Be 'Next Show'
        $paged.items.name | Should -Be @($all.items)[1].name
        $default | Should -Not -Match '"programmes"'
    }

    It 'rejects a window that is incomplete, backwards, empty, longer than 3 hours, or not UTC' {
        $root = Join-Path $TestDrive 'lineup-window-errors'
        Initialize-LineupRoot -Root $root
        foreach ($bad in 'from=2026-01-01T00:00:00Z', 'to=2026-01-01T00:00:00Z', 'from=2026-01-01T01:00:00Z&to=2026-01-01T00:00:00Z', 'from=2026-01-01T00:00:00Z&to=2026-01-01T00:00:00Z', 'from=2026-01-01T00:00:00Z&to=2026-01-01T03:00:01Z', 'from=2026-01-01T00:00:00%2B01:00&to=2026-01-01T01:00:00Z', 'from=yesterday&to=now') {
            (Get-LineupResponse -Method GET -Path "/api/lineup/channels?$bad" -Root $root).StatusCode | Should -Be 400
        }
        (Get-LineupResponse -Method GET -Path '/api/lineup/channels?from=2026-01-01T00:00:00Z&to=2026-01-01T03:00:00Z' -Root $root).StatusCode | Should -Be 200
    }
}
