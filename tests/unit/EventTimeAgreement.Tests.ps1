BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-Programme { param([string]$Title, $Start) [pscustomobject]@{ Title = $Title; Start = $Start; Stop = $null } }
    function New-Carrier {
        param([string]$Name, [object[]]$Programmes)
        [pscustomobject]@{ Key = ('{0:x64}' -f $Name.Length); DisplayName = $Name; GroupTitle = 'T'; Category = $null; Programmes = $Programmes }
    }
    function Get-Agreement {
        param([object[]]$Channel)
        $candidate = @($Channel | ForEach-Object { [pscustomobject]@{ Key = $_.Key } })
        InModuleScope ChannelForge -Parameters @{ C = $candidate; Ch = $Channel } {
            $result = Get-ChannelForgeEventTimeAgreement -Candidate $C -Channel $Ch
            [pscustomobject]@{ Result = $result; Lines = @(Get-ChannelForgeEventTimeSummaryLines -Agreement $result) }
        }
    }
}

Describe 'Event time agreement' {
    It 'marks the same event at the same instant on two channels as agreed, even with different offsets' {
        $one = New-Carrier 'PPV 1' @(New-Programme 'Big Fight Night' ([datetimeoffset]'2026-11-15T01:00:00Z'))
        $two = New-Carrier 'PPV 22' @(New-Programme 'big fight night!' ([datetimeoffset]'2026-11-14T20:00:00-05:00'))
        $out = Get-Agreement -Channel @($one, $two)
        $out.Result.Events.Count | Should -Be 1
        $out.Result.Events[0].Status | Should -Be 'agreed'
        $out.Result.Events[0].ChannelKeys.Count | Should -Be 2
    }

    It 'flags a conflict, keeps each channel own start, and reports both in Eastern time' {
        $one = New-Carrier 'PPV 1' @(New-Programme 'Big Fight Night' ([datetimeoffset]'2026-11-15T01:00:00Z'))
        $two = New-Carrier 'PPV 22' @(New-Programme 'Big Fight Night' ([datetimeoffset]'2026-11-15T01:10:00Z'))
        $out = Get-Agreement -Channel @($one, $two)
        $event = $out.Result.Events[0]
        $event.Status | Should -Be 'conflict'
        @($event.Starts | ForEach-Object { $_.Start.UtcDateTime.ToString('HH:mm') }) | Should -Be @('01:00', '01:10')
        $out.Lines | Should -Contain '- Conflict: Big Fight Night: PPV 1 Nov 14 8:00 PM EST; PPV 22 Nov 14 8:10 PM EST'
    }

    It 'marks an event on one channel as single-source' {
        $out = Get-Agreement -Channel @(New-Carrier 'PPV 1' @(New-Programme 'Solo Show' ([datetimeoffset]'2026-11-15T01:00:00Z')))
        $out.Result.Events[0].Status | Should -Be 'single-source'
    }

    It 'skips and counts a programme with no start time and a placeholder title' {
        $one = New-Carrier 'PPV 1' @(
            (New-Programme 'No Time Show' $null),
            (New-Programme 'No Event' ([datetimeoffset]'2026-11-15T01:00:00Z')),
            (New-Programme 'Real Show' ([datetimeoffset]'2026-11-15T03:00:00Z')))
        $out = Get-Agreement -Channel @($one)
        $out.Result.Events.Count | Should -Be 1
        $out.Result.SkippedCount | Should -Be 2
        $out.Lines | Should -Contain '1 events: 0 agreed, 0 conflict, 1 single-source. 2 entries skipped (no usable start time or placeholder title). Nothing was changed.'
    }
}
