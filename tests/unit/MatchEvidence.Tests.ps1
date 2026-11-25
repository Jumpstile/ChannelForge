BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function Invoke-InModule {
        param([scriptblock]$Script, [object[]]$Arguments = @())
        & (Get-Module ChannelForge) $Script @Arguments
    }

    function Send-Json {
        param([string]$Root, [string]$Path, $Payload)
        $body = [Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 4))
        Invoke-InModule { param($Root, $Path, $Body) Get-ChannelForgeWebResponse -Method POST -Path $Path -RepositoryRoot $Root -StaticRoot '' -BodyBytes $Body -ContentType 'application/json' -ContentLength $Body.Length } @($Root, $Path, $body)
    }

    # Four channels: an exact guide match, a duplicate display name, no tvg-id, and an id the guide lacks.
    function Invoke-Acceptance {
        param([string]$Root)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'data\rules'), (Join-Path $Root 'data\lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $Root 'data\rules')
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $Root 'data\lineup')
        $playlist = @(
            '#EXTM3U'
            '#EXTINF:-1 tvg-id="one" tvg-logo="https://logo.example/a.png" group-title="News",Alpha News'
            'https://stream.example/live/one.m3u8'
            '#EXTINF:-1 tvg-logo="https://logo.example/d.png" group-title="Movies",Beta Movies'
            'https://stream.example/live/two.m3u8'
            '#EXTINF:-1 tvg-id="three" tvg-logo="https://logo.example/b.png" group-title="News",Alpha News'
            'https://stream.example/live/three.m3u8'
            '#EXTINF:-1 tvg-id="gone" tvg-logo="https://logo.example/c.png" group-title="News",Delta'
            'https://stream.example/live/four.m3u8'
        ) -join "`n"
        $stamp = { param($m) ([datetimeoffset]::UtcNow.AddMinutes($m)).ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture) + ' +0000' }
        $show = { param($id) "<programme start=`"$(& $stamp -10)`" stop=`"$(& $stamp 50)`" channel=`"$id`"><title>Show</title></programme>" }
        $guide = "<tv><channel id=`"one`"><display-name>One</display-name></channel><channel id=`"three`"><display-name>Three</display-name></channel>$(& $show 'one')$(& $show 'three')</tv>"
        $proposal = Send-Json $Root '/api/guided-setup/proposal' ([ordered]@{
                schemaVersion = 1
                m3u = [ordered]@{ contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($playlist + "`n")) }
                xmltv = [ordered]@{ contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($guide)) }
            })
        $proposal.StatusCode | Should -Be 200
        return Send-Json $Root '/api/guided-setup/accept' @{ schemaVersion = 1; proposalId = ($proposal.Body | ConvertFrom-Json).Proposal.ProposalId; acknowledged = $true }
    }

    function Get-Accepted {
        param([string]$Root)
        Invoke-InModule { param($Root) Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $Root } @($Root)
    }

    function Read-Evidence {
        param([string]$Root, $Snapshot)
        Invoke-InModule { param($Root, $S) Read-ChannelForgeMatchEvidence -RepositoryRoot $Root -GenerationId ([string]$S.Manifest.Object.GenerationId) -AcceptedStateHash ([string]$S.State.Object.AcceptedStateHash) -AcceptedOutputManifestHash ([string]$S.Output.Object.OutputManifestHash) } @($Root, $Snapshot)
    }
}

Describe 'match evidence recorded at acceptance' {
    It 'writes the file outside the generation folder and its rows follow the lineup route order' {
        $root = Join-Path $TestDrive 'accepted'
        (Invoke-Acceptance $root).StatusCode | Should -Be 200
        $snapshot = Get-Accepted $root
        $id = [string]$snapshot.Manifest.Object.GenerationId
        $file = Join-Path $root "state\accepted-evidence\$id.json"
        Test-Path -LiteralPath $file | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root "state\generations\$id\$id.json") | Should -BeFalse
        (Get-ChildItem -LiteralPath (Join-Path $root "state\generations\$id") -File).Name | Should -Not -Contain "$id.json"

        $read = Read-Evidence $root $snapshot
        $read.Status | Should -Be 'Ok'
        $rows = @(Invoke-InModule { param($S) Get-ChannelForgeWebLineupRows -Snapshot $S } @($snapshot))
        $read.Entries.Count | Should -Be 4
        for ($i = 0; $i -lt 4; $i++) {
            $read.Entries[$i].outputOrdinal | Should -Be ($i + 1)
            $read.Entries[$i].channelName | Should -BeExactly $rows[$i].Name
        }
        @($read.Entries | Where-Object channelName -eq 'Alpha News').Count | Should -Be 2
        ($read.Entries | Where-Object channelName -eq 'Beta Movies').reasonCode | Should -Be 'MissingM3UId'
        ($read.Entries | Where-Object channelName -eq 'Delta').reasonCode | Should -Be 'NoXMLTVMatch'
        $exact = $read.Entries | Where-Object { $_.guideId -eq 'one' }
        $exact.reasonCode | Should -Be 'ExactOrdinalMatch'
        $exact.status | Should -Be 'ExactBound'
        $text = [IO.File]::ReadAllText($file)
        foreach ($leak in 'stream.example', 'logo.example', 'http', $TestDrive) { $text | Should -Not -BeLike "*$leak*" }
    }

    It 'keeps only the current and previous generation files' {
        $root = Join-Path $TestDrive 'retention'
        $ids = foreach ($n in 1..3) {
            (Invoke-Acceptance $root).StatusCode | Should -Be 200
            [string](Get-Accepted $root).Manifest.Object.GenerationId
        }
        $names = @(Get-ChildItem -LiteralPath (Join-Path $root 'state\accepted-evidence') -File).BaseName
        $names | Should -HaveCount 2
        $names | Should -Contain $ids[2]
        $names | Should -Contain $ids[1]
    }

    It 'still accepts the lineup with a warning when the file cannot be written' {
        $root = Join-Path $TestDrive 'blocked'
        New-Item -ItemType File -Force -Path (Join-Path $root 'state\accepted-evidence') | Out-Null
        $response = Invoke-Acceptance $root
        $response.StatusCode | Should -Be 200
        ($response.Body | ConvertFrom-Json).Status | Should -Be 'ACCEPTED'
        ($response.Body | ConvertFrom-Json).Message | Should -BeLike '*match details could not be saved*'
        (Get-Accepted $root).Manifest.Object.GenerationId | Should -Match '^[0-9a-f]{64}$'
    }
}

Describe 'match evidence on the source-set path' {
    It 'records rows in route order when the candidate has no byte offsets' {
        $root = Join-Path $TestDrive 'sourceset'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data\rules'), (Join-Path $root 'data\lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $root 'data\rules')
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $root 'data\lineup')
        $b64 = { param($t) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t)) }
        $playlist = "#EXTM3U`n#EXTINF:-1 tvg-id=`"one`" tvg-logo=`"https://logo.example/a.png`" group-title=`"News`",Alpha News`nhttps://stream.example/live/one.m3u8`n#EXTINF:-1 tvg-logo=`"https://logo.example/b.png`" group-title=`"News`",Alpha News`nhttps://stream.example/live/two.m3u8`n#EXTINF:-1 tvg-id=`"gone`" tvg-logo=`"https://logo.example/c.png`" group-title=`"News`",Delta`nhttps://stream.example/live/three.m3u8`n"
        $stamp = { param($m) ([datetimeoffset]::UtcNow.AddMinutes($m)).ToString('yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture) + ' +0000' }
        $guide = "<tv><channel id=`"one`"><display-name>One</display-name></channel><programme start=`"$(& $stamp -10)`" stop=`"$(& $stamp 50)`" channel=`"one`"><title>Show</title></programme></tv>"
        $proposal = Send-Json $root '/api/guided-setup/proposal' ([ordered]@{
                schemaVersion = 2
                playlists = @([pscustomobject][ordered]@{ sourceKey = 'p1'; label = 'p1'; priority = 100; contentBase64 = (& $b64 $playlist) })
                guides = @([pscustomobject][ordered]@{ sourceKey = 'g1'; label = 'g1'; priority = 100; contentBase64 = (& $b64 $guide) })
                bindings = @([pscustomobject][ordered]@{ guideRef = 'g1'; playlistRefs = @(); appliesToAll = $true })
            })
        $proposal.StatusCode | Should -Be 200
        $accept = Send-Json $root '/api/guided-setup/accept' @{ schemaVersion = 2; proposalId = ($proposal.Body | ConvertFrom-Json).Proposal.ProposalId; acknowledged = $true }
        $accept.StatusCode | Should -Be 200
        $snapshot = Get-Accepted $root
        $read = Read-Evidence $root $snapshot
        $read.Status | Should -Be 'Ok'
        $rows = @(Invoke-InModule { param($S) Get-ChannelForgeWebLineupRows -Snapshot $S } @($snapshot))
        $read.Entries.Count | Should -Be 3
        for ($i = 0; $i -lt 3; $i++) { $read.Entries[$i].channelName | Should -BeExactly $rows[$i].Name }
        $read.Entries[1].reasonCode | Should -Be 'MissingM3UId'
        ($read.Entries | Where-Object guideId -eq 'one').reasonCode | Should -Be 'ExactOrdinalMatch'
        ($read.Entries | Where-Object guideId -eq 'one').guideSourceId | Should -Not -BeNullOrEmpty
    }
}

Describe 'match evidence reader' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'reader'
        (Invoke-Acceptance $script:Root).StatusCode | Should -Be 200
        $script:Snapshot = Get-Accepted $script:Root
        $script:File = Join-Path $script:Root "state\accepted-evidence\$($script:Snapshot.Manifest.Object.GenerationId).json"
        $script:Good = [IO.File]::ReadAllText($script:File)
    }
    AfterEach { [IO.File]::WriteAllText($script:File, $script:Good) }

    It 'says Missing when there is no file' {
        Remove-Item -LiteralPath $script:File
        (Read-Evidence $script:Root $script:Snapshot).Status | Should -Be 'Missing'
    }
    It 'says Corrupt for a changed reason, a wrong entry count, a wrong lineup, or an oversize file' {
        [IO.File]::WriteAllText($script:File, $script:Good.Replace('ExactOrdinalMatch', 'NoXMLTVMatch'))
        (Read-Evidence $script:Root $script:Snapshot).Status | Should -Be 'Corrupt'
        [IO.File]::WriteAllText($script:File, ($script:Good -replace '"entryCount":\s*4', '"entryCount": 3'))
        (Read-Evidence $script:Root $script:Snapshot).Status | Should -Be 'Corrupt'
        [IO.File]::WriteAllText($script:File, $script:Good)
        $other = Invoke-InModule { param($Root, $S) Read-ChannelForgeMatchEvidence -RepositoryRoot $Root -GenerationId ([string]$S.Manifest.Object.GenerationId) -AcceptedStateHash ('0' * 64) -AcceptedOutputManifestHash ([string]$S.Output.Object.OutputManifestHash) } @($script:Root, $script:Snapshot)
        $other.Status | Should -Be 'Corrupt'
        $stream = [IO.File]::Open($script:File, 'Open', 'Write'); $stream.SetLength(33MB); $stream.Dispose()
        (Read-Evidence $script:Root $script:Snapshot).Status | Should -Be 'Corrupt'
    }
}

Describe 'match evidence producer' {
    BeforeAll {
        function New-Fixture {
            $slice = { param($o) [pscustomobject]@{ ByteOffset = $o } }
            $manifest = [pscustomobject]@{
                Entries = @(
                    [pscustomobject]@{ EntryId = 'b'; DisplayName = 'Second'; EntryOutputSlice = (& $slice 200) }
                    [pscustomobject]@{ EntryId = 'a'; DisplayName = 'First'; EntryOutputSlice = (& $slice 100) }
                    [pscustomobject]@{ EntryId = 'c'; DisplayName = 'Third'; EntryOutputSlice = (& $slice 300) }
                )
                GuideOccurrences = @(
                    [pscustomobject]@{ RawIdentityPresence = 'Present'; RawIdentityValue = 'x.1'; OccurrenceOrdinal = 0; LogicalSourceId = 'guide-a' }
                    [pscustomobject]@{ RawIdentityPresence = 'Present'; RawIdentityValue = 'n.1'; OccurrenceOrdinal = 0; LogicalSourceId = 'guide-a' }
                    [pscustomobject]@{ RawIdentityPresence = 'Present'; RawIdentityValue = 'n.1'; OccurrenceOrdinal = 1; LogicalSourceId = 'guide-a' }
                )
                BindingRecords = @(
                    [pscustomobject]@{ BindingKind = 'M3U'; EntryId = 'a'; BindingId = 'ba'; M3URawIdPresence = 'Present'; M3URawId = 'x.1'; XMLTVIdPresence = 'Present'; XMLTVId = 'x.1'; CandidateChannelOccurrenceOrdinals = @(0); Status = 'ExactBound'; ReasonCode = 'ExactOrdinalMatch'; CollisionEvidence = @() }
                    [pscustomobject]@{ BindingKind = 'M3U'; EntryId = 'b'; BindingId = 'bb'; M3URawIdPresence = 'Present'; M3URawId = 'n.1'; XMLTVIdPresence = 'Present'; XMLTVId = 'n.1'; CandidateChannelOccurrenceOrdinals = @(0, 1); Status = 'ReviewNeeded'; ReasonCode = 'DuplicateXMLTVId'; CollisionEvidence = @('d1', 'd2') }
                    [pscustomobject]@{ BindingKind = 'M3U'; EntryId = 'c'; BindingId = 'bc'; M3URawIdPresence = 'Missing'; M3URawId = $null; XMLTVIdPresence = 'Missing'; XMLTVId = $null; CandidateChannelOccurrenceOrdinals = @(); Status = 'Unbound'; ReasonCode = 'MissingM3UId'; CollisionEvidence = @() }
                )
            }
            $accepted = [pscustomobject]@{
                GenerationId = ('1' * 64); GenerationManifest = [pscustomobject]@{ CandidateManifestHash = ('2' * 64) }
                AcceptedState = [pscustomobject]@{ AcceptedStateHash = ('3' * 64) }; AcceptedOutputManifest = [pscustomobject]@{ OutputManifestHash = ('4' * 64) }
            }
            Invoke-InModule { param($M, $A) New-ChannelForgeMatchEvidence -CandidateManifest $M -Accepted $A -M3UBytes ([byte[]]@(35)) } @($manifest, $accepted)
        }
    }

    It 'records exact, ambiguous and unmatched rows in output order' {
        $doc = New-Fixture
        @($doc.entries.channelName) | Should -Be @('First', 'Second', 'Third')
        @($doc.entries.outputOrdinal) | Should -Be @(1, 2, 3)
        $doc.entries[0].reasonCode | Should -Be 'ExactOrdinalMatch'
        $doc.entries[0].guideSourceId | Should -Be 'guide-a'
        $doc.entries[1].reasonCode | Should -Be 'DuplicateXMLTVId'
        $doc.entries[1].collisionCount | Should -Be 2
        $doc.entries[2].guideId | Should -BeNullOrEmpty
        $doc.entries[2].guideSourceId | Should -BeNullOrEmpty
    }
    It 'changes the evidence hash when a field changes' {
        $one = New-Fixture
        $two = New-Fixture
        $two.entries[0].reasonCode = 'NoXMLTVMatch'
        $changed = [ordered]@{}; foreach ($k in $two.Keys) { if ($k -ne "evidenceHash") { $changed[$k] = $two[$k] } }
        $one.evidenceHash | Should -Match '^[0-9a-f]{64}$'
        (Invoke-InModule { param($D) Get-ChannelForgeDomainHash -Domain 'match-evidence/v1' -InputObject $D } @($changed)) | Should -Not -Be $one.evidenceHash
    }
}

Describe 'match evidence order when channels share one stream URL' {
    BeforeAll {
        function Get-SharedUrlOrder {
            param([string[]]$RowNames)
            $order = { param($Names)
                $fp = Get-ChannelForgeDomainHash -Domain 'stream-fingerprint/v2' -InputObject ([ordered]@{ Version = 'stream-fingerprint-v2'; StreamUrl = 'https://s.example/x' })
                $entries = foreach ($n in 'One', 'Two') { [pscustomobject]@{ EntryId = "id-$n"; DisplayName = $n; StreamFingerprint = $fp; EntryOutputSlice = [pscustomobject]@{ ByteOffset = $null } } }
                $m3u = "#EXTM3U`n" + (($Names | ForEach-Object { "#EXTINF:-1,$_`nhttps://s.example/x" }) -join "`n") + "`n"
                @(Get-ChannelForgeMatchEvidenceOrder -CandidateManifest ([pscustomobject]@{ Entries = @($entries) }) -M3UBytes ([Text.Encoding]::UTF8.GetBytes($m3u))).DisplayName
            }
            Invoke-InModule $order @(, $RowNames)
        }
    }
    It 'pairs each row by name' { Get-SharedUrlOrder @('Two', 'One') | Should -Be @('Two', 'One') }
    It 'throws instead of guessing when names do not decide' { { Get-SharedUrlOrder @('Other', 'One') } | Should -Throw '*ambiguous*' }
}
