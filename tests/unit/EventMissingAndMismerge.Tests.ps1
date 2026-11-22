BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-mismerge-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    function Get-Blocks {
        # Rows: @(title, 'yyyy-MM-ddTHH:mm', 'yyyy-MM-ddTHH:mm' or $null). Window: From to To (UTC days).
        param([object[]]$Row, [string]$Name = 'Fixture 1', [string]$From = '2026-11-15', [string]$To = '2026-11-17')
        $programme = @($Row | ForEach-Object {
                [pscustomobject]@{ Title = $_[0]; Description = ''; Valid = $true
                    Start = [datetimeoffset]::Parse("$($_[1]):00Z"); Stop = $(if ($_[2]) { [datetimeoffset]::Parse("$($_[2]):00Z") } else { $null }) }
            })
        InModuleScope ChannelForge -Parameters @{ P = [object[]]$programme; N = $Name; F = $From; T = $To } {
            Get-ChannelForgeEventProgrammeBlocks -Programme $P -ChannelName $N -WindowStart ([datetime]::Parse("${F}T00:00:00Z").ToUniversalTime()) -WindowEnd ([datetime]::Parse("${T}T00:00:00Z").ToUniversalTime())
        }
    }
    function Write-Evidence {
        param([string]$FileName, [object[]]$Record)
        $path = Join-Path $script:Dir $FileName
        @{ records = $Record } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
        $path
    }
    function Read-Evidence {
        param([string]$Path)
        @(InModuleScope ChannelForge -Parameters @{ P = $Path } { Read-ChannelForgeScheduleEvidence -Path $P })
    }
    function Get-Check {
        param([string]$Title, [string]$Day, [object[]]$Record)
        $path = Write-Evidence -FileName ([guid]::NewGuid().ToString('N') + '.json') -Record $Record
        $block = [pscustomobject]@{ Start = [datetime]::Parse("${Day}T12:00:00Z").ToUniversalTime(); Stop = [datetime]::Parse("${Day}T15:00:00Z").ToUniversalTime(); Title = $Title }
        InModuleScope ChannelForge -Parameters @{ B = $block; P = $path } {
            Compare-ChannelForgeScheduleEvidence -Channel ([pscustomobject]@{ Name = 'NFL 1'; Blocks = @($B) }) -Evidence @(Read-ChannelForgeScheduleEvidence -Path $P)
        }
    }
    function Get-EventTitle { param($Result) @($Result.Blocks | Where-Object { $_.Title -ne 'Fixture 1' } | ForEach-Object Title) }
    $script:Game = @{ id = 'a'; date = '2026-11-15'; sport = 'Football'; home = 'Dallas Cowboys'; away = 'New York Giants' }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Missing schedule facts mean unknown' {
    It 'keeps missing time, venue and city empty and never fills a default time' {
        $row = Read-Evidence (Write-Evidence 'bare.json' @($script:Game))
        $row.Count | Should -Be 1
        $row[0].StartUtc | Should -BeNullOrEmpty
        $row[0].Time | Should -BeNullOrEmpty
        $row[0].Venue | Should -BeNullOrEmpty
        $row[0].City | Should -BeNullOrEmpty
    }
    It 'skips a record with no date or a missing team instead of inventing one' {
        $path = Write-Evidence 'partial.json' @(
            @{ id = 'a'; sport = 'Football'; home = 'Dallas Cowboys'; away = 'New York Giants' }
            @{ id = 'b'; sport = 'Football'; home = 'Dallas Cowboys'; date = '2026-11-15' }
            @{ id = 'c'; kind = 'special'; date = '2026-11-15' })
        (Read-Evidence $path).Count | Should -Be 0
    }
    It 'does not match a channel when the schedule has no row for that day' {
        Get-Check -Title 'Giants vs Cowboys' -Day '2026-11-16' -Record @($script:Game) | Should -BeNullOrEmpty
    }
    It 'does not match a team it cannot place, even when a game exists that day' {
        (Get-Check -Title 'Giants vs Tigers' -Day '2026-11-15' -Record @($script:Game)).Status | Should -Not -Be 'Confirmed'
    }
    It 'shows only the channel name when the provider has no real event title' {
        $r = Get-Blocks -Row @(, @('No Event', '2026-11-15T00:00', '2026-11-16T00:00'))
        @($r.Blocks).Count | Should -Be 1
        $r.Blocks[0].Title | Should -Be 'Fixture 1'
    }
    It 'keeps the channel on its normal guide when a program time cannot be read' {
        $bad = [pscustomobject]@{ Title = 'Giants vs Cowboys'; Description = ''; Valid = $false; Start = $null; Stop = $null }
        $r = InModuleScope ChannelForge -Parameters @{ P = [object[]]@($bad) } {
            Get-ChannelForgeEventProgrammeBlocks -Programme $P -ChannelName 'Fixture 1' -WindowStart ([datetime]::Parse('2026-11-15T00:00:00Z').ToUniversalTime()) -WindowEnd ([datetime]::Parse('2026-11-16T00:00:00Z').ToUniversalTime())
        }
        @($r.Blocks).Count | Should -Be 0
        $r.Reason | Should -BeLike '*could not be read*'
    }
    It 'writes no programme for a channel with no blocks' {
        $bytes = InModuleScope ChannelForge { ConvertTo-ChannelForgeEventGuideXmltv -Channel @([pscustomobject]@{ Id = 'ChannelForge-' + ('a' * 32); Name = 'Fixture 1'; Blocks = @() }) }
        $doc = [xml][Text.Encoding]::UTF8.GetString([byte[]]$bytes)
        @($doc.tv.channel).Count | Should -Be 1
        $doc.SelectNodes("//programme").Count | Should -Be 0
    }
}

Describe 'Different events are never merged' {
    It 'keeps a doubleheader as two labeled blocks' {
        $r = Get-Blocks -Row @(@('Giants vs Cowboys', '2026-11-15T12:00', '2026-11-15T15:00'), @('Giants vs Cowboys', '2026-11-15T18:00', '2026-11-15T21:00'))
        Get-EventTitle $r | Should -Be @('Game 1: Giants vs Cowboys', 'Game 2: Giants vs Cowboys')
    }
    It 'does not label the same event name in different years as a doubleheader' {
        $r = Get-Blocks -From '2025-11-15' -To '2026-11-16' -Row @(@('Fixture Showdown', '2025-11-15T12:00', '2025-11-15T15:00'), @('Fixture Showdown', '2026-11-15T12:00', '2026-11-15T15:00'))
        Get-EventTitle $r | Should -Be @('Fixture Showdown', 'Fixture Showdown')
        @($r.Review).Count | Should -Be 0
    }
    It 'keeps a main card and its prelims as two different events' {
        $r = Get-Blocks -Row @(@('Fixture Fight Night Prelims', '2026-11-15T12:00', '2026-11-15T15:00'), @('Fixture Fight Night Main Card', '2026-11-15T15:00', '2026-11-15T19:00'))
        Get-EventTitle $r | Should -Be @('Fixture Fight Night Prelims', 'Fixture Fight Night Main Card')
    }
    It 'keeps a replay and the live game as two different events' {
        $r = Get-Blocks -Row @(@('Giants vs Cowboys', '2026-11-15T12:00', '2026-11-15T15:00'), @('Giants vs Cowboys (Replay)', '2026-11-15T18:00', '2026-11-15T21:00'))
        $titles = Get-EventTitle $r
        $titles.Count | Should -Be 2
        $titles[1] | Should -BeLike '*Replay*'
    }
    It 'does not confirm a game from the same teams on a different date' {
        Get-Check -Title 'Giants vs Cowboys' -Day '2026-11-22' -Record @($script:Game) | Should -BeNullOrEmpty
    }
    It 'keeps two sources with the same name on different dates apart' {
        $path = Write-Evidence 'same.json' @(
            @{ id = 'a'; kind = 'special'; name = 'Fixture Showdown'; date = '2026-11-15'; source = 'one.example.invalid' }
            @{ id = 'b'; kind = 'special'; name = 'Fixture Showdown'; date = '2026-11-22'; source = 'two.example.invalid' })
        $rows = Read-Evidence $path
        $rows.Count | Should -Be 2
        ($rows.Date | Sort-Object) | Should -Be @('2026-11-15', '2026-11-22')
    }
}
