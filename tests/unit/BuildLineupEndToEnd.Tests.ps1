BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    $script:GuideXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="alpha.us"><display-name>Alpha</display-name></channel>
  <channel id="gone.us"><display-name>Gone</display-name></channel>
  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>
  <programme start="20260824110000 +0000" stop="20260824120000 +0000" channel="alpha.us"><title>Alpha Noon</title></programme>
  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="gone.us"><title>Gone Show</title></programme>
</tv>
'@

    function New-E2EBuildRoot {
        param([string]$GuideFile)

        $root = Join-Path $TestDrive ('e2e-' + [guid]::NewGuid().ToString('N'))
        $dataDir = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $dataDir 'providers'), (Join-Path $dataDir 'epg'), (Join-Path $dataDir 'lineup'),
            (Join-Path $dataDir 'rules'), (Join-Path $dataDir 'playlists') | Out-Null
        @('#EXTM3U', '#EXTINF:-1 tvg-id="alpha.us" group-title="News",Alpha', 'https://example.invalid/live/alpha') -join "`n" |
            Set-Content -LiteralPath (Join-Path $dataDir 'playlists\playlist.m3u') -Encoding utf8NoBOM
        @{ provider = 'fixture-provider'; sources = @(
                @{ name = 'Playlist'; group = 'News'; url = 'https://example.invalid/iptv/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }
            ) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @(@{ name = 'Guide'; priority = 10; path = $GuideFile; enabled = $true; role = 'primary' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'News'; notes = 'fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8
        return $root
    }

    function Write-E2EGuide {
        # Writes the guide in the shape the file name asks for. Zip entries are [name, text] pairs.
        param([string]$Root, [string]$File, [string]$Text, [string[][]]$ZipEntries)

        $path = Join-Path $Root ('data\epg\' + $File)
        if ($File -like '*.zip') {
            $stream = [IO.File]::Create($path)
            $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($pair in $ZipEntries) {
                    $writer = [IO.StreamWriter]::new($zip.CreateEntry($pair[0]).Open())
                    try { $writer.Write($pair[1]) } finally { $writer.Dispose() }
                }
            }
            finally { $zip.Dispose(); $stream.Dispose() }
        }
        elseif ($File -like '*.gz') {
            $stream = [IO.File]::Create($path)
            $gzip = [IO.Compression.GZipStream]::new($stream, [IO.Compression.CompressionMode]::Compress)
            try { $bytes = [Text.Encoding]::UTF8.GetBytes($Text); $gzip.Write($bytes, 0, $bytes.Length) }
            finally { $gzip.Dispose(); $stream.Dispose() }
        }
        else {
            [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
        }
    }

    function Get-E2EGuidePath {
        param([string]$Root)
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        return Join-Path $Root (($summary.XMLTVPath) -replace '/', '\')
    }
}

Describe 'Build-Lineup.ps1 end to end with a local guide' {
    It 'publishes a playlist and a guide holding the kept channel programmes, the same for .xml, .xml.gz and .zip' {
        $hashes = @()
        foreach ($file in 'guide.xml', 'guide.xml.gz', 'guide.zip') {
            $root = New-E2EBuildRoot -GuideFile $file
            Write-E2EGuide -Root $root -File $file -Text $script:GuideXml -ZipEntries @(, @('guide.xml', $script:GuideXml))

            & $script:BuildScriptPath -Root $root *> $null

            $summary = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
            $summary.XMLTVStatus | Should -Be 'GENERATED'
            $guidePath = Get-E2EGuidePath -Root $root
            $guide = Get-Content -LiteralPath $guidePath -Raw
            $guide | Should -Match 'Alpha Morning'
            $guide | Should -Match 'Alpha Noon'
            Test-Path -LiteralPath (Join-Path (Split-Path -Parent $guidePath) 'merged.m3u') | Should -BeTrue
            $hashes += (Get-FileHash -LiteralPath $guidePath -Algorithm SHA256).Hash
        }
        @($hashes | Select-Object -Unique).Count | Should -Be 1
    }

    It 'writes the public https logo into the guide for the exact-bound channel and none for an http logo' -ForEach @(
        @{ Logo = 'https://img.example.invalid/alpha.png'; Expected = $true }
        @{ Logo = 'http://img.example.invalid/alpha.png'; Expected = $false }
    ) {
        $root = New-E2EBuildRoot -GuideFile 'guide.xml'
        Write-E2EGuide -Root $root -File 'guide.xml' -Text $script:GuideXml
        @('#EXTM3U', "#EXTINF:-1 tvg-id=`"alpha.us`" tvg-logo=`"$Logo`" group-title=`"News`",Alpha", 'https://example.invalid/live/alpha') -join "`n" |
            Set-Content -LiteralPath (Join-Path $root 'data\playlists\playlist.m3u') -Encoding utf8NoBOM

        & $script:BuildScriptPath -Root $root *> $null

        $guide = Get-Content -LiteralPath (Get-E2EGuidePath -Root $root) -Raw
        $guide | Should -Match 'Alpha Morning'
        if ($Expected) { $guide | Should -Match '<icon src="https://img.example.invalid/alpha.png"' } else { $guide | Should -Not -Match '<icon' }
    }

    It 'gives byte-identical guide output when the same build runs twice' {
        $root = New-E2EBuildRoot -GuideFile 'guide.xml'
        Write-E2EGuide -Root $root -File 'guide.xml' -Text $script:GuideXml

        & $script:BuildScriptPath -Root $root *> $null
        $guidePath = Get-E2EGuidePath -Root $root
        $first = [IO.File]::ReadAllBytes($guidePath)
        & $script:BuildScriptPath -Root $root *> $null

        (Get-E2EGuidePath -Root $root) | Should -Be $guidePath
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($guidePath)) | Should -Be ([Convert]::ToBase64String($first))
    }

    It 'fails closed and leaves the previous guide untouched for a <Name> guide' -ForEach @(
        @{ Name = 'DTD with external entity'; File = 'guide.xml'
           Text = "<?xml version=`"1.0`"?>`n<!DOCTYPE tv [<!ENTITY x SYSTEM `"file:///does-not-exist.invalid`">]>`n<tv><channel id=`"alpha.us`"><display-name>&x;</display-name></channel></tv>"; Zip = $null }
        @{ Name = 'corrupt gzip'; File = 'guide.xml.gz'; Text = 'this is not gzip data'; Zip = $null }
        @{ Name = 'two-entry zip'; File = 'guide.zip'; Text = $null
           Zip = @(@('a.xml', '<tv/>'), @('b.xml', '<tv/>')) }
        @{ Name = 'path-escaping zip'; File = 'guide.zip'; Text = $null
           Zip = @(, @('..\evil.xml', '<tv/>')) }
    ) {
        $root = New-E2EBuildRoot -GuideFile $File
        Write-E2EGuide -Root $root -File $File -Text $script:GuideXml -ZipEntries @(, @('guide.xml', $script:GuideXml))
        & $script:BuildScriptPath -Root $root *> $null
        $guidePath = Get-E2EGuidePath -Root $root
        $before = (Get-FileHash -LiteralPath $guidePath -Algorithm SHA256).Hash
        $guideCount = @(Get-ChildItem -LiteralPath (Join-Path $root 'output\candidates') -Recurse -Filter merged.xml).Count

        if ($null -ne $Zip) { Write-E2EGuide -Root $root -File $File -ZipEntries $Zip }
        elseif ($File -like '*.gz') { [IO.File]::WriteAllText((Join-Path $root 'data\epg\guide.xml.gz'), $Text) }
        else { [IO.File]::WriteAllText((Join-Path $root 'data\epg\guide.xml'), $Text) }

        $message = $null
        try { & $script:BuildScriptPath -Root $root *> $null } catch { $message = $_.Exception.Message }

        $message | Should -Match 'could not be imported|contains no programs'
        $message | Should -Not -Match '[A-Za-z]:\\|https?://'
        $summary = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.Status | Should -Be 'FAILED'
        $summary.XMLTVGenerated | Should -BeFalse
        (Get-FileHash -LiteralPath $guidePath -Algorithm SHA256).Hash | Should -Be $before
        @(Get-ChildItem -LiteralPath (Join-Path $root 'output\candidates') -Recurse -Filter merged.xml).Count | Should -Be $guideCount
        Test-Path -LiteralPath (Join-Path $root 'output\merged.xml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'data\evil.xml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'data\epg\evil.xml') | Should -BeFalse
    }

    It 'says an empty guide has no programs instead of saying it could not be imported (issue 191)' {
        $root = New-E2EBuildRoot -GuideFile 'guide.xml'
        Write-E2EGuide -Root $root -File 'guide.xml' -Text '<?xml version="1.0" encoding="UTF-8"?><tv/>'
        $message = $null
        try { & $script:BuildScriptPath -Root $root *> $null } catch { $message = $_.Exception.Message }

        $message | Should -Match 'contains no programs'
        $message | Should -Not -Match 'could not be imported'
    }

    It 'finishes a build with a guide of several thousand programmes in a generous time (issue 191)' {
        # Before the fix, serializing the evidence took minutes on a guide this size.
        $guide = [System.Text.StringBuilder]::new()
        [void]$guide.Append('<?xml version="1.0" encoding="UTF-8"?><tv>')
        foreach ($channelId in 'alpha.us', 'beta.us', 'gamma.us') {
            [void]$guide.Append("<channel id=`"$channelId`"><display-name>$channelId</display-name></channel>")
            foreach ($slot in 0..1999) {
                $start = [datetime]::new(2026, 8, 24, 0, 0, 0, [DateTimeKind]::Utc).AddMinutes(30 * $slot)
                $stamp = '{0:yyyyMMddHHmmss} +0000' -f $start
                $stop = '{0:yyyyMMddHHmmss} +0000' -f $start.AddMinutes(30)
                [void]$guide.Append("<programme start=`"$stamp`" stop=`"$stop`" channel=`"$channelId`"><title>Fixture Show $slot</title><desc>Fixture description $slot</desc><category>News</category></programme>")
            }
        }
        [void]$guide.Append('</tv>')
        $root = New-E2EBuildRoot -GuideFile 'guide.xml'
        Write-E2EGuide -Root $root -File 'guide.xml' -Text $guide.ToString()

        $elapsed = Measure-Command { & $script:BuildScriptPath -Root $root *> $null }

        $summary = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.XMLTVStatus | Should -Be 'GENERATED'
        (Get-Content -LiteralPath (Get-E2EGuidePath -Root $root) -Raw) | Should -Match 'Fixture Show 1999'
        $elapsed.TotalSeconds | Should -BeLessThan 120
    }

    It 'adds a Catch-up section to the plan and keeps catch-up attributes out of the playlist' {
        $root = New-E2EBuildRoot -GuideFile 'guide.xml'
        Write-E2EGuide -Root $root -File 'guide.xml' -Text $script:GuideXml
        @('#EXTM3U', '#EXTINF:-1 tvg-id="alpha.us" group-title="News" catchup="default" catchup-source="https://example.invalid/a/{utc}" catchup-days="3",Alpha', 'https://example.invalid/live/alpha') -join "`n" |
            Set-Content -LiteralPath (Join-Path $root 'data\playlists\playlist.m3u') -Encoding utf8NoBOM

        & $script:BuildScriptPath -Root $root *> $null

        $plan = Get-Content -LiteralPath (Join-Path $root 'output\reports\lineup-plan.md') -Raw
        $plan | Should -Match '## Catch-up'
        $plan | Should -Match '1 of 1 streams say they support it'
        $plan | Should -Match 'Most archive days a stream declares: 3'
        (Get-ChildItem -LiteralPath (Join-Path $root 'output') -Recurse -Filter 'merged.m3u' | Get-Content -Raw) | Should -Not -Match 'catchup'
    }

    It 'only warns and leaves the section out when the catch-up check fails' {
        # Build-Lineup loads the module next to itself, so break the check in a private copy of the repo.
        $copy = Join-Path $TestDrive ('copy-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $copy 'scripts'), (Join-Path $copy 'src') | Out-Null
        Copy-Item -LiteralPath $script:BuildScriptPath -Destination (Join-Path $copy 'scripts')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'src\ChannelForge') -Destination (Join-Path $copy 'src') -Recurse
        foreach ($dir in 'schemas', 'config', 'docs', 'tools', 'engineering', 'data') { Copy-Item -LiteralPath (Join-Path $RepoRoot $dir) -Destination $copy -Recurse }
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'VERSION') -Destination $copy
        Set-Content -LiteralPath (Join-Path $copy 'src\ChannelForge\Private\Get-ChannelForgeCatchupReport.ps1') -Value "function Get-ChannelForgeCatchupReport { throw 'boom' }"
        $root = New-E2EBuildRoot -GuideFile 'guide.xml'
        Write-E2EGuide -Root $root -File 'guide.xml' -Text $script:GuideXml

        # A child process keeps the private copy's classes apart from the ones this session already loaded.
        $output = & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File (Join-Path $copy 'scripts\Build-Lineup.ps1') -Root $root *>&1 | Out-String

        $output | Should -Match 'catch-up check could not run'
        Write-Host $output
        (Get-Content -LiteralPath (Join-Path $root 'output\reports\lineup-plan.md') -Raw) | Should -Not -Match '## Catch-up'
        (Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json).XMLTVStatus | Should -Be 'GENERATED'
    }
}
