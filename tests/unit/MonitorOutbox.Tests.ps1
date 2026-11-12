BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\scripts\monitoring\MonitorOutbox.psm1'
    Import-Module -Name $modulePath -Force
}

Describe 'ChannelForge durable monitor outbox' {
    It 'uses a stable idempotency key independent of observation time' {
        $first = New-MonitorFinding -MonitorId 'channelforge-test' -Repository 'Jumpstile/ChannelForge' -TargetIssueNumber 48 -FindingType 'test' -Title 'Stable finding' -Body 'Same evidence' -Evidence ([ordered]@{ revision = 'abc' }) -ObservedAtUtc ([DateTime]::Parse('2026-01-01T00:00:00Z'))
        $second = New-MonitorFinding -MonitorId 'channelforge-test' -Repository 'Jumpstile/ChannelForge' -TargetIssueNumber 48 -FindingType 'test' -Title 'Stable finding' -Body 'Same evidence' -Evidence ([ordered]@{ revision = 'abc' }) -ObservedAtUtc ([DateTime]::Parse('2026-02-01T00:00:00Z'))
        (Get-MonitorIdempotencyKey -Finding $first) | Should -Be (Get-MonitorIdempotencyKey -Finding $second)
        (Get-MonitorFindingHash -Finding $first) | Should -Be (Get-MonitorFindingHash -Finding $second)
    }
    It 'rejects non-HTTPS or non-GitHub API monitor endpoints' {
        { Invoke-MonitorGitHubRequest -Method GET -Uri 'http://api.github.com/repos/example/project' } | Should -Throw '*allowlisted*'
        { Invoke-MonitorGitHubRequest -Method GET -Uri 'https://example.invalid/repos/example/project' } | Should -Throw '*allowlisted*'
    }


    It 'flushes an atomic queue file and deduplicates repeated evidence' {
        $spool = Join-Path $TestDrive 'spool'
        $finding = New-MonitorFinding -MonitorId 'channelforge-test' -Repository 'Jumpstile/ChannelForge' -TargetIssueNumber 48 -FindingType 'test' -Title 'Queue finding' -Body 'Persist this' -Evidence ([ordered]@{ revision = 'def' })
        $item = New-MonitorOutboxItem -Finding $finding
        $written = Write-MonitorOutboxItem -SpoolRoot $spool -Item $item
        $written.idempotencyKey | Should -Be $item.idempotencyKey
        @(Get-ChildItem -LiteralPath (Join-Path $spool 'pending') -File -Filter '*.json').Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $spool -File -Filter '*.tmp.*' -Recurse).Count | Should -Be 0
        $duplicate = Write-MonitorOutboxItem -SpoolRoot $spool -Item $item
        $duplicate.idempotencyKey | Should -Be $item.idempotencyKey
        @(Get-MonitorOutboxItems -SpoolRoot $spool).Count | Should -Be 1
    }

    It 'rejects a same-key payload whose evidence was altered' {
        $spool = Join-Path $TestDrive 'collision'
        $finding = New-MonitorFinding -MonitorId 'channelforge-test' -Repository 'Jumpstile/ChannelForge' -TargetIssueNumber 48 -FindingType 'test' -Title 'Collision finding' -Body 'Original' -Evidence ([ordered]@{ revision = 'ghi' })
        $item = New-MonitorOutboxItem -Finding $finding
        [void](Write-MonitorOutboxItem -SpoolRoot $spool -Item $item)
        $conflict = $item | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $conflict.finding.body = 'Altered'
        { Write-MonitorOutboxItem -SpoolRoot $spool -Item $conflict } | Should -Throw '*mismatch*'
    }

    It 'applies bounded exponential retry and preserves the pending item' {
        $spool = Join-Path $TestDrive 'retry'
        $now = [DateTime]::Parse('2026-03-01T00:00:00Z').ToUniversalTime()
        $finding = New-MonitorFinding -MonitorId 'channelforge-test' -Repository 'Jumpstile/ChannelForge' -TargetIssueNumber 48 -FindingType 'test' -Title 'Retry finding' -Body 'Retry this' -Evidence ([ordered]@{ revision = 'jkl' }) -ObservedAtUtc $now
        [void](Write-MonitorOutboxItem -SpoolRoot $spool -Item (New-MonitorOutboxItem -Finding $finding -CreatedAtUtc $now))
        Mock -ModuleName MonitorOutbox Publish-MonitorOutboxItem { throw 'simulated GitHub unavailable' }
        $result = Invoke-MonitorOutboxReplay -SpoolRoot $spool -Token 'token-for-fixture' -NowUtc $now
        $result.Attempted | Should -Be 1
        $result.Deferred | Should -Be 1
        $pending = @(Get-MonitorOutboxItems -SpoolRoot $spool)[0]
        $pending.attemptCount | Should -Be 1
        ([DateTime]$pending.nextAttemptAtUtc).ToUniversalTime() | Should -Be $now.AddSeconds(60)
        $pending.lastError | Should -Match 'simulated GitHub unavailable'
        Get-MonitorBackoffSeconds -AttemptCount 1 | Should -Be 60
        Get-MonitorBackoffSeconds -AttemptCount 8 | Should -Be 3600
    }

    It 'publishes only after the idempotency marker is readable again' {
        $spool = Join-Path $TestDrive 'publish'
        $finding = New-MonitorFinding -MonitorId 'channelforge-test' -Repository 'Jumpstile/ChannelForge' -TargetIssueNumber 48 -FindingType 'test' -Title 'Publish finding' -Body 'Verify this' -Evidence ([ordered]@{ revision = 'mno' })
        $item = New-MonitorOutboxItem -Finding $finding
        [void](Write-MonitorOutboxItem -SpoolRoot $spool -Item $item)
        $posted = [pscustomobject]@{ Body = $null }
        $publishMock = {
            param($Method, $Body)
            if ($Method -eq 'POST') {
                $posted.Body = [string]$Body.body
                return [pscustomobject]@{ id = 123 }
            }
            if ($null -eq $posted.Body) { return @() }
            return @([pscustomobject]@{ id = 123; body = $posted.Body })
        }.GetNewClosure()
        Mock -ModuleName MonitorOutbox Invoke-MonitorGitHubRequest $publishMock
        $recorded = Publish-MonitorOutboxItem -SpoolRoot $spool -Item $item -Token 'token-for-fixture'
        $recorded.status | Should -Be 'recorded'
        $recorded.recordedCommentId | Should -Be '123'
        @(Get-MonitorOutboxItems -SpoolRoot $spool).Count | Should -Be 0
        @(Get-MonitorOutboxItems -SpoolRoot $spool -IncludeRecorded).Count | Should -Be 1
    }

    It 'round-trips source state through the same atomic writer' {
        $spool = Join-Path $TestDrive 'state'
        $state = [pscustomobject][ordered]@{ schemaVersion = 1; monitorId = 'channelforge-test'; sources = [pscustomobject]@{ source = [pscustomobject]@{ commitSha = 'abc'; releaseTag = $null } }; updatedAtUtc = '2026-03-01T00:00:00Z' }
        [void](Write-MonitorSourceState -SpoolRoot $spool -State $state)
        $loaded = Read-MonitorSourceState -SpoolRoot $spool -MonitorId 'channelforge-test'
        $loaded.sources.source.commitSha | Should -Be 'abc'
        (Get-Content -LiteralPath (Join-Path $spool 'source-state.json') -Raw) | Should -Match '"schemaVersion"'
    }

    It 'queues a source change and does not advance state on a fetch failure' {
        $spool = Join-Path $TestDrive 'watch'
        $manifestPath = Join-Path $TestDrive 'watch-manifest.json'
        [IO.File]::WriteAllText($manifestPath, '{"schemaVersion":1,"monitorId":"channelforge-watch","targetRepository":"Jumpstile/ChannelForge","targetIssueNumber":35,"sources":[{"sourceId":"fixture","name":"Fixture","repository":"example/fixture"}]}')
        $now = [DateTime]::Parse('2026-03-02T00:00:00Z').ToUniversalTime()
        $snapshot = [pscustomobject]@{ Value = [pscustomobject]@{ repository = 'example/fixture'; commitSha = ('a' * 40); commitUrl = 'https://github.com/example/fixture/commit/a'; releaseTag = $null; releaseUrl = $null } }
        $snapshotMock = { return $snapshot.Value }.GetNewClosure()
        Mock -ModuleName MonitorOutbox Get-MonitorGitHubSourceSnapshot $snapshotMock
        $baseline = Invoke-MonitorSourceWatch -MonitorId 'channelforge-watch' -ManifestPath $manifestPath -SpoolRoot $spool -NowUtc $now
        $baseline.BaselineSources | Should -Be 1
        @($baseline.Findings).Count | Should -Be 0
        $snapshot.Value = [pscustomobject]@{ repository = 'example/fixture'; commitSha = ('b' * 40); commitUrl = 'https://github.com/example/fixture/commit/b'; releaseTag = 'v2'; releaseUrl = 'https://github.com/example/fixture/releases/tag/v2' }
        $changed = Invoke-MonitorSourceWatch -MonitorId 'channelforge-watch' -ManifestPath $manifestPath -SpoolRoot $spool -NowUtc $now.AddMinutes(1)
        $changed.ChangedSources | Should -Be 1
        @($changed.Findings).Count | Should -Be 1
        @($changed.Findings | Where-Object { $_.finding.findingType -eq 'source-change' }).Count | Should -Be 1
        $queued = @(Get-MonitorOutboxItems -SpoolRoot $spool)
        $queued.Count | Should -Be 1
        Mock -ModuleName MonitorOutbox Get-MonitorGitHubSourceSnapshot { throw 'fixture source unavailable' }
        $failed = Invoke-MonitorSourceWatch -MonitorId 'channelforge-watch' -ManifestPath $manifestPath -SpoolRoot $spool -NowUtc $now.AddMinutes(2)
        $failed.FailedSources | Should -Be 1
        @($failed.Findings | Where-Object { $_.finding.findingType -eq 'source-fetch-failure' }).Count | Should -Be 1
        (Read-MonitorSourceState -SpoolRoot $spool -MonitorId 'channelforge-watch').sources.fixture.commitSha | Should -Be ('b' * 40)
    }
}
