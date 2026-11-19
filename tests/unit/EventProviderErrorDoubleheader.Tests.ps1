BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-Xmltv {
        param([object[]]$Rows)
        $body = foreach ($row in $Rows) { "<programme start=`"$($row[0])`" stop=`"$($row[1])`" channel=`"ppv1`"><title>$($row[2])</title>$(if ($row.Count -gt 3) { "<desc>$($row[3])</desc>" })</programme>" }
        [Text.Encoding]::UTF8.GetBytes("<?xml version=`"1.0`"?><tv>$($body -join '')</tv>")
    }
    function Invoke-Plan {
        param([byte[]]$Xmltv)
        $entry = @([pscustomobject]@{ EntryId = 'e1'; Key = ('{0:x64}' -f 1); Name = 'PPV 1'; GuideId = 'ppv1' })
        InModuleScope ChannelForge -Parameters @{ X = $Xmltv; E = $entry } {
            $plan = Get-ChannelForgeEventGuidePlan -XmltvBytes $X -Entry $E
            [pscustomobject]@{ Plan = $plan; Titles = @($plan.Channel | ForEach-Object { $_.Blocks } | ForEach-Object { $_.Title }) }
        }
    }
    $script:Day = '20261115'
    function T([string]$Hhmm) { "$($script:Day)${Hhmm}00 +0000" }
}

Describe 'Provider error text' {
    It 'is not an event: the channel keeps its normal guide and the report says why' {
        $out = Invoke-Plan (New-Xmltv @(, @((T '0000'), (T '2359'), 'No data')))
        $out.Plan.Channel.Count | Should -Be 0
        $out.Plan.Fallback.Count | Should -Be 1
        $out.Plan.Fallback[0].Reason | Should -BeLike '*provider guide reports an error*'
    }
    It 'is found in the description too, in any case' {
        $out = Invoke-Plan (New-Xmltv @(, @((T '1800'), (T '2100'), 'Big Fight', 'GUIDE UNAVAILABLE right now')))
        $out.Plan.Channel.Count | Should -Be 0
        $out.Plan.Fallback[0].Reason | Should -BeLike '*reports an error*'
    }
    It 'does not match inside a longer word' {
        $out = Invoke-Plan (New-Xmltv @(, @((T '1800'), (T '2100'), 'Big Fight', 'Piano data is unavailable? no. Nodata here')))
        $out.Plan.Channel.Count | Should -Be 1
    }
}

Describe 'Doubleheaders' {
    It 'gives the same two teams Game 1 and Game 2 in time order, even with the sides swapped' {
        $out = Invoke-Plan (New-Xmltv @(@((T '2000'), (T '2300'), 'Dodgers at Giants'), @((T '1600'), (T '1900'), 'Giants vs LA Dodgers')))
        @($out.Titles | Where-Object { $_ -ne 'PPV 1' }) | Should -Be @('Game 1: Giants vs LA Dodgers', 'Game 2: Dodgers at Giants')
    }
    It 'labels the same event name twice on one day Part 1 and Part 2 in order' {
        $out = Invoke-Plan (New-Xmltv @(@((T '2000'), (T '2300'), 'Fight Night'), @((T '1400'), (T '1700'), 'Fight Night')))
        @($out.Titles | Where-Object { $_ -ne 'PPV 1' }) | Should -Be @('Part 1: Fight Night', 'Part 2: Fight Night')
    }
    It 'makes nothing new and asks one question when the times overlap' {
        $out = Invoke-Plan (New-Xmltv @(@((T '1400'), (T '1800'), 'Fight Night'), @((T '1700'), (T '2100'), 'Fight Night')))
        $out.Plan.Channel.Count | Should -Be 1
        @($out.Titles | Where-Object { $_ -like 'Part *' }).Count | Should -Be 0
        $out.Plan.Review.Count | Should -Be 1
        $out.Plan.Review[0].Reason | Should -BeLike 'review:*'
    }
    It 'leaves two different events alone' {
        $out = Invoke-Plan (New-Xmltv @(@((T '1400'), (T '1700'), 'Fight Night'), @((T '2000'), (T '2300'), 'Title Bout')))
        @($out.Titles | Where-Object { $_ -ne 'PPV 1' }) | Should -Be @('Fight Night', 'Title Bout')
        $out.Plan.Review.Count | Should -Be 0
    }
}
