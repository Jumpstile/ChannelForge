BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Module = Get-Module ChannelForge
    # Load the one function under test from the lineup script, without running the script.
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot 'scripts\Build-My-Lineup.ps1'), [ref]$tokens, [ref]$errors)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-EventScheduleQuestion' }, $true) | Select-Object -First 1
    function Invoke-ChannelForgePrivate { param([string]$Name, [hashtable]$Arguments) & $script:Module { param($n, $a) & $n @a } $Name $Arguments }
    . ([scriptblock]::Create($fn.Extent.Text))

    $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('cf-answer-' + [guid]::NewGuid().ToString('N'))
    $script:State = Join-Path $script:Root 'state'
    [void](New-Item -ItemType Directory -Path $script:State)
    $script:EvidencePath = Join-Path $script:State 'schedule-evidence.json'
    $script:AnswerPath = Join-Path $script:State 'schedule-answers.json'
    @{ records = @(@{ id = 'r1'; sport = 'Football'; home = 'Dallas Cowboys'; away = 'New York Giants'; date = '2026-11-15'; startUtc = '2026-11-15T12:00:00Z'; source = 'schedule.example.invalid'; seen = '2026-11-10T09:00:00Z' }) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:EvidencePath
    $script:Xmltv = [System.Text.Encoding]::UTF8.GetBytes('<tv><programme start="20261115120000 +0000" stop="20261115150000 +0000" channel="x"><title>t</title></programme></tv>')
    $script:CallAsk = {
        param([string]$Title)
        $block = [pscustomobject]@{ Start = [datetime]::Parse('2026-11-15T12:00:00Z').ToUniversalTime(); Stop = [datetime]::Parse('2026-11-15T15:00:00Z').ToUniversalTime(); Title = $Title }
        $plan = [pscustomobject]@{ Channel = @([pscustomobject]@{ Key = 'key-aaaa'; Name = 'Test Channel'; Blocks = @($block) }); Fallback = @() }
        @(Get-EventScheduleQuestion -Plan $plan -XmltvBytes $script:Xmltv -EvidencePath $script:EvidencePath -AnswerPath $script:AnswerPath 3>&1)
    }
}
AfterAll { Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Saved schedule answers' {
    AfterEach { Remove-Item -LiteralPath $script:AnswerPath -Force -ErrorAction SilentlyContinue }
    It 'asks again with no answer, then stops asking once answered' {
        $ask = @(& $script:CallAsk 'Dodgers vs Tigers')
        @($ask).Count | Should -Be 1
        $ask[0] | Should -BeLike "Event channel 'Test Channel'*Set-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -State NoEvidence*"
        Set-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -State NoEvidence -Answer StillOn -RepositoryRoot $script:Root
        @(& $script:CallAsk 'Dodgers vs Tigers' | Where-Object { $_ -like 'Event channel*' }).Count | Should -Be 0
    }
    It 'shows one summary line for a Cancelled answer' {
        Set-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -State NoEvidence -Answer Cancelled -RepositoryRoot $script:Root
        $out = @(& $script:CallAsk 'Dodgers vs Tigers')
        $out.Count | Should -Be 1
        $out[0] | Should -Be 'Answered earlier: Test Channel is cancelled.'
    }
    It 'asks again when the evidence state changes' {
        Set-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -State NoEvidence -Answer Cancelled -RepositoryRoot $script:Root
        $out = @(& $script:CallAsk 'Giants vs Tigers')
        $out.Count | Should -Be 1
        $out[0] | Should -BeLike "Event channel*-State Review*"
    }
    It 'brings the question back after clear' {
        Set-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -State NoEvidence -Answer StillOn -RepositoryRoot $script:Root
        Clear-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -RepositoryRoot $script:Root
        @(& $script:CallAsk 'Dodgers vs Tigers' | Where-Object { $_ -like 'Event channel*' }).Count | Should -Be 1
    }
    It 'turns a corrupt answers file into one warning and still asks' {
        Set-Content -LiteralPath $script:AnswerPath -Value '{ not json'
        $out = @(& $script:CallAsk 'Dodgers vs Tigers')
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        @($out | Where-Object { $_ -is [string] -and $_ -like 'Event channel*' }).Count | Should -Be 1
    }
    It 'gives the same candidate hash with and without saved answers' {
        $hashes = foreach ($withAnswers in $false, $true) {
            $root = Join-Path $script:Root ('build-' + $withAnswers)
            New-Item -ItemType Directory -Force -Path (Join-Path $root 'data\rules'), (Join-Path $root 'data\lineup'), (Join-Path $root 'state') | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $root 'data\rules\aliases.json')
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $root 'data\lineup\numbering_blocks.json')
            if ($withAnswers) {
                Copy-Item -LiteralPath $script:EvidencePath -Destination (Join-Path $root 'state\schedule-evidence.json')
                Set-ChannelForgeScheduleAnswer -ChannelId 'key-aaaa' -State NoEvidence -Answer Cancelled -RepositoryRoot $root
            }
            $line = @(& (Join-Path $script:RepoRoot 'scripts\Build-My-Lineup.ps1') -Root $root -M3UPath (Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u') -XMLTVPath (Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml') -PlanOnly -MachineResult |
                    Where-Object { $_ -is [string] -and $_.StartsWith('CHANNELFORGE_MACHINE_RESULT:') } | Select-Object -Last 1)
            (($line[0] -replace '^CHANNELFORGE_MACHINE_RESULT:', '') | ConvertFrom-Json).CandidateManifestHash
        }
        $hashes[0] | Should -Match '^[0-9a-f]{64}$'
        $hashes[1] | Should -Be $hashes[0]
    }
}
