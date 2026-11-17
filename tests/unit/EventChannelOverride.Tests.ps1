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
    function New-Choice { param([int]$Number, [string]$Decision) [pscustomobject]@{ key = ('{0:x64}' -f $Number); name = ''; decision = $Decision; decidedAt = '' } }
    function Invoke-Plan {
        param([byte[]]$Xmltv, [object[]]$Entry, [object[]]$Override = @())
        InModuleScope ChannelForge -Parameters @{ X = $Xmltv; E = $Entry; O = $Override } { Get-ChannelForgeEventGuidePlan -XmltvBytes $X -Entry $E -Override $O }
    }
    $day = '20261115'
    $script:Ppv = @(@("${day}000000 +0000", "${day}180000 +0000", 'No Event'), @("${day}180000 +0000", "${day}210000 +0000", 'Big Fight Night'), @("${day}210000 +0000", "${day}235900 +0000", 'No Event'))
    $script:Real = @(@("${day}000000 +0000", "${day}080000 +0000", 'Bout A'), @("${day}080000 +0000", "${day}160000 +0000", 'Bout B'), @("${day}160000 +0000", "${day}235900 +0000", 'Bout C'))

    $script:Root = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'state'), (Join-Path $script:Root 'output') | Out-Null
    $source = Join-Path $script:Root 'source.m3u'
    [IO.File]::WriteAllText($source, "#EXTM3U`n#EXTINF:-1 tvg-id=`"ppv1`" group-title=`"Sports`",PPV 1`nhttps://example.com/secret/ppv1`n", [System.Text.UTF8Encoding]::new($false))
    $built = & (Join-Path $script:RepoRoot 'scripts\Build-Candidate.ps1') -Root $script:Root -M3UPath $source -OutputRoot (Join-Path $script:Root 'output')
    $script:Candidate = [string]$built.CandidateDirectory
    $script:StatePath = Join-Path $script:Root 'state\event-channels.json'
}

Describe 'Event channel override in the guide plan' {
    It 'forceOff gives a high channel its normal guide back and says overridden' {
        $out = Invoke-Plan -Xmltv (New-Xmltv @{ ppv1 = $script:Ppv }) -Entry @(New-Entry 'PPV 1' 1 'ppv1') -Override @(New-Choice 1 'forceOff')
        $out.Channel.Count | Should -Be 0
        $out.Fallback[0].Reason | Should -BeLike '*overridden*'
    }

    It 'forceOn gives a medium channel an event guide when it has times' {
        $out = Invoke-Plan -Xmltv (New-Xmltv @{ fight = $script:Real }) -Entry @(New-Entry 'Fight Network' 3 'fight') -Override @(New-Choice 3 'forceOn')
        $out.Channel.Count | Should -Be 1
        $out.Applied[0].Reason | Should -BeLike '*overridden*'
    }

    It 'forceOn on a channel with no times keeps the normal guide and the channel is still there' {
        $out = Invoke-Plan -Xmltv (New-Xmltv @{ news = $script:Real }) -Entry @(New-Entry 'Fight 4' 4 'missing') -Override @(New-Choice 4 'forceOn')
        $out.Channel.Count | Should -Be 0
        $out.Fallback.Count | Should -Be 1
        $out.Fallback[0].Name | Should -Be 'Fight 4'
        $out.Fallback[0].Reason | Should -BeLike '*no programs*'
    }

    It 'ignores a stale key' {
        $out = Invoke-Plan -Xmltv (New-Xmltv @{ ppv1 = $script:Ppv }) -Entry @(New-Entry 'PPV 1' 1 'ppv1') -Override @(New-Choice 9 'forceOn')
        $out.Channel.Count | Should -Be 1
        $out.Fallback.Count | Should -Be 0
    }
}

Describe 'Event channel override file and report' {
    BeforeEach { Remove-Item -LiteralPath $script:StatePath -Force -ErrorAction SilentlyContinue }

    It 'saves a choice, shows it and a stale choice in the report, and -Clear removes the record' {
        $key = (Get-ChannelForgeEventChannelReport -CandidateDirectory $script:Candidate -RepositoryRoot $script:Root).Rows[0].ChannelKey
        Set-ChannelForgeEventChannel -ChannelKey $key -Decision ForceOff -RepositoryRoot $script:Root
        Set-ChannelForgeEventChannel -ChannelKey ('b' * 64) -Decision ForceOn -Name 'Gone' -RepositoryRoot $script:Root
        $report = Get-ChannelForgeEventChannelReport -CandidateDirectory $script:Candidate -RepositoryRoot $script:Root
        $report.Rows[0].DisplayName | Should -Be 'PPV 1'
        $report.Rows[0].Override | Should -Be 'forceOff'
        @($report.Stale).Count | Should -Be 1
        $report.Stale[0].Key | Should -Be ('b' * 64)
        Set-ChannelForgeEventChannel -ChannelKey $key -Clear -RepositoryRoot $script:Root
        @((Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json).overrides).Count | Should -Be 1
        (Get-ChannelForgeEventChannelReport -CandidateDirectory $script:Candidate -RepositoryRoot $script:Root).Rows[0].Override | Should -BeNullOrEmpty
    }

    It 'never replaces a damaged file, and the reader throws so the build can warn and carry on' {
        [IO.File]::WriteAllText($script:StatePath, '{ not json')
        $before = [IO.File]::ReadAllBytes($script:StatePath)
        { Set-ChannelForgeEventChannel -ChannelKey ('b' * 64) -Decision ForceOn -RepositoryRoot $script:Root } | Should -Throw '*Nothing was written*'
        { InModuleScope ChannelForge -Parameters @{ P = $script:StatePath } { Read-ChannelForgeEventChannelOverrides -Path $P } } | Should -Throw '*Nothing was written*'
        [IO.File]::ReadAllBytes($script:StatePath) | Should -Be $before
    }
}
