BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-Xmltv {
        param([hashtable]$Programmes)
        $body = foreach ($id in $Programmes.Keys) {
            foreach ($row in $Programmes[$id]) { "<programme start=`"$($row[0])`" stop=`"$($row[1])`" channel=`"$id`"><title>$($row[2])</title></programme>" }
        }
        [Text.Encoding]::UTF8.GetBytes("<?xml version=`"1.0`"?><tv>$($body -join '')</tv>")
    }
    function New-Entry {
        param([string]$Name, [int]$Number, [string]$GuideId)
        [pscustomobject]@{ EntryId = "e$Number"; Key = ('{0:x64}' -f $Number); Name = $Name; GuideId = $GuideId }
    }
    # Runs the plan, then writes the guide the way the build does. Returns the plan and the programmes per channel id.
    function Invoke-Plan {
        param([byte[]]$Xmltv, [object[]]$Entry, [string[]]$Excluded = @())
        InModuleScope ChannelForge -Parameters @{ X = $Xmltv; E = $Entry; Ex = $Excluded } {
            $plan = Get-ChannelForgeEventGuidePlan -XmltvBytes $X -Entry $E -ExcludedKey $Ex
            $bytes = if ($plan.Channel.Count -gt 0) { [byte[]](Add-ChannelForgePlaceholderGuide -XmltvBytes $X -Channel $plan.Channel -TimeZone ([TimeZoneInfo]::Utc) | Select-Object -Last 1) } else { $X }
            $doc = [xml][Text.Encoding]::UTF8.GetString($bytes)
            $rows = @{}
            foreach ($p in @($doc.tv.programme)) {
                $rows[$p.channel] += @([pscustomobject]@{ Start = "$($p.start)".PadRight(14).Substring(8, 4); Stop = "$($p.stop)".PadRight(14).Substring(8, 4); Title = $p.title })
            }
            [pscustomobject]@{ Plan = $plan; Rows = $rows }
        }
    }
    $script:Day = '20261115'
    $script:Provider = @{
        ppv1 = @(@("$($script:Day)000000 +0000", "$($script:Day)180000 +0000", 'No Event'), @("$($script:Day)180000 +0000", "$($script:Day)210000 +0000", 'Big Fight Night'), @("$($script:Day)210000 +0000", "$($script:Day)235900 +0000", 'No Event'))
        news = @(,@("$($script:Day)000000 +0000", "$($script:Day)235900 +0000", 'News'))
    }
}

Describe 'Event guide for high channels' {
    It 'gives a high channel its own guide with the real title and times, and the channel name in the gaps' {
        $out = Invoke-Plan -Xmltv (New-Xmltv $script:Provider) -Entry @((New-Entry 'PPV 1' 1 'ppv1'), (New-Entry 'News' 2 'news'))
        $out.Plan.Channel.Count | Should -Be 1
        $id = $out.Plan.Channel[0].Id
        $id | Should -Be ('ChannelForge-' + ('{0:x64}' -f 1).Substring(0, 32))
        $rows = $out.Rows[$id]
        @($rows | ForEach-Object { "$($_.Start)-$($_.Stop) $($_.Title)" }) | Should -Be @('0000-1800 PPV 1', '1800-2100 Big Fight Night', '2100-2359 PPV 1')
        $out.Plan.Applied[0].Reason | Should -BeLike 'event guide applied*'
    }

    It 'shows the channel name for the whole window when the channel has no event' {
        $xmltv = New-Xmltv @{ ppv1 = $script:Provider.ppv1[0], $script:Provider.ppv1[2]; news = $script:Provider.news }
        $out = Invoke-Plan -Xmltv $xmltv -Entry @((New-Entry 'PPV 1' 1 'ppv1'), (New-Entry 'News' 2 'news'))
        @($out.Rows[$out.Plan.Channel[0].Id] | ForEach-Object { $_.Title } | Select-Object -Unique) | Should -Be @('PPV 1')
    }

    It 'leaves a medium channel on its normal guide' {
        $real = @{ fight = @(@("$($script:Day)000000 +0000", "$($script:Day)080000 +0000", 'Bout A'), @("$($script:Day)080000 +0000", "$($script:Day)160000 +0000", 'Bout B'), @("$($script:Day)160000 +0000", "$($script:Day)235900 +0000", 'Bout C')) }
        $out = Invoke-Plan -Xmltv (New-Xmltv $real) -Entry @(New-Entry 'Fight Network' 3 'fight')
        $out.Plan.Channel.Count | Should -Be 0
        $out.Plan.Fallback.Count | Should -Be 0
    }

    It 'falls back to the normal guide, and reports why, when a program time cannot be read' {
        $broken = @{ ppv1 = @(,@('garbage', "$($script:Day)180000 +0000", 'Big Fight Night')); news = $script:Provider.news }
        $out = Invoke-Plan -Xmltv (New-Xmltv $broken) -Entry @((New-Entry 'PPV 1' 1 'ppv1'), (New-Entry 'News' 2 'news'))
        $out.Plan.Channel.Count | Should -Be 0
        $out.Plan.Fallback[0].Name | Should -Be 'PPV 1'
        $out.Plan.Fallback[0].Reason | Should -BeLike '*could not be read*'
        $out.Rows['ppv1'].Count | Should -Be 1
    }

    It 'falls back when the provider guide has no programs for the channel' {
        $out = Invoke-Plan -Xmltv (New-Xmltv @{ news = $script:Provider.news }) -Entry @((New-Entry 'PPV 1' 1 'missing'), (New-Entry 'News' 2 'news'))
        $out.Plan.Channel.Count | Should -Be 0
        $out.Plan.Fallback[0].Reason | Should -BeLike '*no programs*'
    }

    It 'keeps a channel with a saved guide choice on that choice' {
        $out = Invoke-Plan -Xmltv (New-Xmltv $script:Provider) -Entry @(New-Entry 'PPV 1' 1 'ppv1') -Excluded @('{0:x64}' -f 1)
        $out.Plan.Channel.Count | Should -Be 0
        $out.Plan.Fallback[0].Reason | Should -BeLike '*saved a guide choice*'
    }
}
