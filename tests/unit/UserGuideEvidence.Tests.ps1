BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-userguide-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    # Fixture data: invented guides, not real listings.
    function New-Guide {
        param([string]$Name, [string[]]$Programmes)
        $path = Join-Path $script:Dir $Name
        $xml = '<?xml version="1.0" encoding="UTF-8"?><tv><channel id="chan.one"/>' + ($Programmes -join '') + '</tv>'
        [IO.File]::WriteAllText($path, $xml, [Text.UTF8Encoding]::new($false))
        $path
    }
    function New-Programme { param([string]$Start, [string]$Title, [string]$Desc = '') "<programme start=`"$Start`" stop=`"20301231000000 +0000`" channel=`"chan.one`"><title>$Title</title><desc>$Desc</desc></programme>" }
    function Get-Agreement {
        param([string]$GuidePath, [object[]]$Provider)
        InModuleScope ChannelForge -Parameters @{ G = $GuidePath; P = $Provider } {
            $evidence = @(Read-ChannelForgeUserGuideEvidence -Path $G)
            $all = @($P) + @(ConvertTo-ChannelForgeUserGuideChannel -Evidence $evidence)
            Get-ChannelForgeEventTimeAgreement -Candidate @($all | ForEach-Object { [pscustomobject]@{ Key = $_.Key } }) -Channel $all
        }
    }
    $script:Provider = [pscustomobject]@{ Key = 'provider1'; DisplayName = 'Provider 1'; Programmes = @([pscustomobject]@{ Title = 'Zeta Rovers vs Omega Hawks'; Start = [datetimeoffset]'2026-11-15T18:00:00Z'; Stop = $null }) }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'User-supplied guide evidence' {
    It 'reads facts with the file name as attribution and agrees with the provider time' {
        $path = New-Guide 'my-guide.xml' @(New-Programme '20261115130000 -0500' 'Zeta Rovers vs Omega Hawks')
        $records = @(InModuleScope ChannelForge -Parameters @{ G = $path } { Read-ChannelForgeUserGuideEvidence -Path $G })
        $records.Count | Should -Be 1
        $records[0].Source | Should -Be 'user-guide'
        $records[0].Attribution | Should -Be 'my-guide.xml'
        $records[0].StartUtc | Should -Be '2026-11-15T18:00:00Z'
        $records[0].Home | Should -Be 'Zeta Rovers'
        (Get-Agreement -GuidePath $path -Provider $script:Provider).Events[0].Status | Should -Be 'agreed'
    }

    It 'flags a time that disagrees with the provider guide' {
        $path = New-Guide 'late.xml' @(New-Programme '20261115181000 +0000' 'Zeta Rovers vs Omega Hawks')
        (Get-Agreement -GuidePath $path -Provider $script:Provider).Events[0].Status | Should -Be 'conflict'
    }

    It 'skips a programme with no usable date and keeps the others' {
        $path = New-Guide 'gap.xml' @((New-Programme '' 'Ghost Game vs Nobody'), (New-Programme '20261115180000 +0000' 'Zeta Rovers vs Omega Hawks'))
        $records = @(InModuleScope ChannelForge -Parameters @{ G = $path } { Read-ChannelForgeUserGuideEvidence -Path $G })
        $records.Count | Should -Be 1
        $records[0].Title | Should -Be 'Zeta Rovers vs Omega Hawks'
    }

    It 'never copies programme text or the full file path' {
        $path = New-Guide 'text.xml' @(New-Programme '20261115180000 +0000' 'Zeta Rovers vs Omega Hawks' 'SECRET-DESCRIPTION-TEXT')
        $json = InModuleScope ChannelForge -Parameters @{ G = $path } { Read-ChannelForgeUserGuideEvidence -Path $G | ConvertTo-Json -Depth 5 }
        $json | Should -Not -BeLike '*SECRET-DESCRIPTION-TEXT*'
        $json | Should -Not -BeLike "*$($script:Dir.Replace('\', '\\'))*"
    }
}
