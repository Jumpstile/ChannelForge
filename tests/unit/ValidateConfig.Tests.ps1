BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Validate-Config.ps1'

    function New-ValidatorFixture {
        param([object]$EpgSource)

        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $dataDir = Join-Path $fixtureRoot 'data'
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers'), (Join-Path $dataDir 'epg'), (Join-Path $dataDir 'lineup'), (Join-Path $dataDir 'rules') | Out-Null

        @{ sources = @(@{ name = 'fixture-provider'; url = 'https://example.invalid/provider'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @($EpgSource) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @(1..14 | ForEach-Object { @{ number = $_ } }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ categories = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\categories.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8

        if ($EpgSource.path) {
            '<tv />' | Set-Content -LiteralPath (Join-Path $dataDir 'epg\guide.xml') -Encoding UTF8
        }

        return $fixtureRoot
    }
}

Describe 'Validate-Config.ps1 EPG source boundary' {
    It 'accepts local XMLTV path configuration without dereferencing a network source' {
        $fixtureRoot = New-ValidatorFixture -EpgSource @{
            name = 'local-guide'
            priority = 10
            path = 'guide.xml'
            enabled = $true
            role = 'primary'
        }

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Not -Throw
        $output = & $script:ScriptPath -Root $fixtureRoot *>&1 | Out-String
        $output | Should -Match 'EPG local sources: 1'
        $output | Should -Match 'EPG remote sources: 0'
    }

    It 'accepts an acceptable HTTPS EPG URL without dereferencing it' {
        $fixtureRoot = New-ValidatorFixture -EpgSource @{
            name = 'remote-guide'
            priority = 10
            url = 'https://example.invalid/guide.xml'
            enabled = $true
            role = 'primary'
        }

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Not -Throw
        $output = & $script:ScriptPath -Root $fixtureRoot *>&1 | Out-String
        $output | Should -Match 'EPG local sources: 0'
        $output | Should -Match 'EPG remote sources: 1'
        $output | Should -Not -Match 'https?://'
    }

    It 'rejects a remote EPG URL that is not acceptable HTTPS' {
        $fixtureRoot = New-ValidatorFixture -EpgSource @{
            name = 'insecure-guide'
            priority = 10
            url = 'http://example.invalid/guide.xml'
            enabled = $true
            role = 'primary'
        }

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw
    }
}