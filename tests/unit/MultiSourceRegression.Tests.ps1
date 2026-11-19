BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
    function script:Send-Web {
        param([string]$Project, [string]$Method, [string]$Path, [string]$Json)
        $bytes = if ($Json) { [Text.Encoding]::UTF8.GetBytes($Json) } else { $null }
        & (Get-Module ChannelForge) { param($p, $m, $u, $b) Get-ChannelForgeWebResponse -Method $m -Path $u -RepositoryRoot $p -BodyBytes $b -ContentType 'application/json' -ContentLength $(if ($b) { $b.Length } else { 0 }) } $Project $Method $Path $bytes
    }
    function script:Get-Cards {
        param([string]$Project)
        @((Send-Web $Project GET '/api/status').Body | ConvertFrom-Json | ForEach-Object Sources)
    }
}

Describe 'several sources: what a user sees and keeps' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $script:Files = Join-Path $TestDrive ('files-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Project, $script:Files | Out-Null
        function Add-Source {
            param([string]$Name, [string]$Kind, [string]$Label = $Name)
            $path = Join-Path $script:Files "$Name.$(if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' })"
            $text = if ($Kind -eq 'M3U') { "#EXTM3U`n#EXTINF:-1 tvg-id=`"$Name`",$Name`nhttps://example.invalid/$Name`n" }
            else { "<?xml version=`"1.0`"?><tv><channel id=`"$Name`"><display-name>$Name</display-name></channel><programme start=`"20260101000000 +0000`" stop=`"20260101010000 +0000`" channel=`"$Name`"><title>$Name</title></programme></tv>" }
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
            Add-ChannelForgeSourceSetSource -Kind $Kind -Path $path -Label $Label -RepositoryRoot $script:Project
        }
        function Get-Set { & (Get-Module ChannelForge) { param($root) Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $root } $script:Project }
        function Get-SetBase64 { [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:Project 'state/source-enrollment.json'))) }
    }

    It 'shows no source cards before anything is saved' {
        @(Get-Cards $script:Project).Count | Should -Be 0
    }

    It 'shows one card for one source, then one card per source as more are added' {
        Add-Source 'alpha' 'M3U' 'Home playlist' | Out-Null
        $cards = @(Get-Cards $script:Project)
        $cards.Count | Should -Be 1
        $cards[0].Label | Should -Be 'Home playlist'

        Add-Source 'beta' 'M3U' 'Backup playlist' | Out-Null
        Add-Source 'guide-one' 'XMLTV' 'Sports guide' | Out-Null
        Add-Source 'guide-two' 'XMLTV' 'News guide' | Out-Null
        $cards = @(Get-Cards $script:Project)
        $cards.Count | Should -Be 4
        @($cards | Where-Object Kind -eq 'M3U').Count | Should -Be 2
        @($cards | Where-Object Kind -eq 'XMLTV').Count | Should -Be 2
    }

    It 'drops a removed source from the cards and keeps the rest' {
        Add-Source 'alpha' 'M3U' 'Home playlist' | Out-Null
        Add-Source 'beta' 'M3U' 'Backup playlist' | Out-Null
        Add-Source 'guide-one' 'XMLTV' 'Sports guide' | Out-Null

        (Send-Web $script:Project POST '/api/sources/remove' '{"Label":"Sports guide","Kind":"XMLTV"}').StatusCode | Should -Be 200
        (Send-Web $script:Project POST '/api/sources/remove' '{"Label":"Backup playlist","Kind":"M3U"}').StatusCode | Should -Be 200
        @(Get-Cards $script:Project).Label | Should -Be @('Home playlist')
    }

    It 'removes a guide that a playlist binding points to, and keeps the playlist' {
        $p = Add-Source 'alpha' 'M3U' 'Home playlist'
        Add-Source 'guide-one' 'XMLTV' 'Sports guide' | Out-Null
        @((Get-Set).Bindings).Count | Should -Be 1

        (Send-Web $script:Project POST '/api/sources/remove' '{"Label":"Sports guide","Kind":"XMLTV"}').StatusCode | Should -Be 200
        $after = Get-Set
        @($after.Guides).Count | Should -Be 0
        @($after.Bindings).Count | Should -Be 0
        @($after.Playlists).Count | Should -Be 1
        $after.Playlists[0].SourceId | Should -Be $p.SourceId
    }

    It 'saves two sources with the same label and removes neither by a label that fits both' {
        Add-Source 'alpha' 'M3U' 'Shared name' | Out-Null
        $guide = Add-Source 'guide-one' 'XMLTV' 'Shared name'
        Add-Source 'beta' 'M3U' 'Other playlist' | Out-Null
        @(Get-Cards $script:Project).Count | Should -Be 3
        $before = Get-SetBase64

        { Remove-ChannelForgeSourceSetSource -Label 'Shared name' -RepositoryRoot $script:Project } | Should -Throw '*more than one*'
        (Get-SetBase64) | Should -Be $before
        $reply = Send-Web $script:Project POST '/api/sources/remove' '{"Label":"Shared name","Kind":"XMLTV"}'
        $reply.StatusCode | Should -Be 200
        @((Get-Set).Guides).Count | Should -Be 0
        @((Get-Set).Playlists).Count | Should -Be 2
    }

    It 'refuses a second playlist with the same label and saves nothing' {
        Add-Source 'alpha' 'M3U' 'Twin' | Out-Null
        $before = Get-SetBase64

        { Add-Source 'beta' 'M3U' 'twin' } | Should -Throw '*duplicate source label*'
        (Get-SetBase64) | Should -Be $before
        @(Get-Cards $script:Project).Count | Should -Be 1
    }
}
