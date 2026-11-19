BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
    function script:Send-Remove {
        param([string]$Project, [string]$Json)
        $bytes = [Text.Encoding]::UTF8.GetBytes($Json)
        & (Get-Module ChannelForge) { param($p, $b) Get-ChannelForgeWebResponse -Method POST -Path '/api/sources/remove' -RepositoryRoot $p -BodyBytes $b -ContentType 'application/json' -ContentLength $b.Length } $Project $bytes
    }
}

Describe 'browser remove of one saved source' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $files = Join-Path $TestDrive ('files-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Project, $files | Out-Null
        function Add-Source {
            param([string]$Name, [string]$Kind)
            $path = Join-Path $files "$Name.$(if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' })"
            $text = if ($Kind -eq 'M3U') { "#EXTM3U`n#EXTINF:-1 tvg-id=`"$Name`",$Name`nhttps://example.invalid/$Name`n" }
            else { "<?xml version=`"1.0`"?><tv><channel id=`"$Name`"><display-name>$Name</display-name></channel><programme start=`"20260101000000 +0000`" stop=`"20260101010000 +0000`" channel=`"$Name`"><title>$Name</title></programme></tv>" }
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
            Add-ChannelForgeSourceSetSource -Kind $Kind -Path $path -Label $Name -RepositoryRoot $script:Project | Out-Null
        }
        function Get-SetBytes { [IO.File]::ReadAllBytes((Join-Path $script:Project 'state/source-enrollment.json')) }
        Add-Source 'Home playlist' 'M3U'
        Add-Source 'Backup playlist' 'M3U'
        Add-Source 'Sports guide' 'XMLTV'
    }

    It 'removes one source and leaves the others exactly as they were' {
        $before = & (Get-Module ChannelForge) { param($r) Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $r } $script:Project
        $keep = @($before.Playlists | Where-Object Label -eq 'Home playlist')[0]
        $guide = @($before.Guides)[0]

        $reply = Send-Remove $script:Project '{"Label":"Backup playlist","Kind":"M3U"}'
        $after = & (Get-Module ChannelForge) { param($r) Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $r } $script:Project

        $reply.StatusCode | Should -Be 200
        @($after.Playlists).Label | Should -Be @('Home playlist')
        @($after.Playlists)[0].ContentHash | Should -Be $keep.ContentHash
        @($after.Playlists)[0].SourceId | Should -Be $keep.SourceId
        @($after.Guides)[0].ContentHash | Should -Be $guide.ContentHash
        @(Get-ChildItem (Join-Path $script:Project 'state/managed-sources') -File).Count | Should -Be 2
    }

    It 'keeps the only playlist and says why in plain words' {
        Send-Remove $script:Project '{"Label":"Backup playlist","Kind":"M3U"}' | Out-Null
        $before = Get-SetBytes
        $reply = Send-Remove $script:Project '{"Label":"Home playlist","Kind":"M3U"}'

        $reply.StatusCode | Should -Be 409
        ($reply.Body | ConvertFrom-Json).Message | Should -BeLike '*only playlist*Nothing was changed*'
        [Convert]::ToBase64String((Get-SetBytes)) | Should -Be ([Convert]::ToBase64String($before))
    }

    It 'a source that is not saved changes nothing and a bad request is refused' {
        $before = Get-SetBytes
        (Send-Remove $script:Project '{"Label":"Nope","Kind":"M3U"}').StatusCode | Should -Be 409
        (Send-Remove $script:Project '{"Label":"Home playlist","Kind":"M3U","Extra":1}').StatusCode | Should -Be 400
        (Send-Remove $script:Project 'not json').StatusCode | Should -Be 400
        [Convert]::ToBase64String((Get-SetBytes)) | Should -Be ([Convert]::ToBase64String($before))
    }

    It 'shows no address, token or path in any reply' {
        $replies = @(
            (Send-Remove $script:Project '{"Label":"Backup playlist","Kind":"M3U"}'),
            (Send-Remove $script:Project '{"Label":"Home playlist","Kind":"M3U"}'),
            (Send-Remove $script:Project '{"Label":"Nope","Kind":"M3U"}')
        )
        foreach ($reply in $replies) { $reply.Body | Should -Not -Match 'https?:|token|managed-sources|[A-Za-z]:\\|[0-9a-f]{64}' }
    }
}
