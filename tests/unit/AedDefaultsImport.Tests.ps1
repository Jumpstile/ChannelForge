BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Fixture = Join-Path $RepoRoot 'tests\fixtures\aed-defaults-export.json'

    # Writes a changed copy of the real export. $Change edits the parsed object.
    function New-AedVariant {
        param([scriptblock]$Change)
        $doc = Get-Content -LiteralPath $script:Fixture -Raw | ConvertFrom-Json
        & $Change $doc
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        $doc | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
        $path
    }
}

Describe 'Read-ChannelForgeAedDefaults' {
    It 'reads the real export with typed values and no warnings' {
        $r = Read-ChannelForgeAedDefaults -Path $script:Fixture
        $r.Warnings.Count | Should -Be 0
        $r.Defaults.event_duration | Should -Be '3 Hours'
        $r.Defaults.include_within_hours | Should -Be 720
        $r.Defaults.clean_regex_output | Should -BeTrue
        $r.Defaults.match_by_name | Should -BeFalse
        $r.Defaults.title_regex | Should -Be ''
    }

    It 'rejects a wrong type' {
        $p = New-AedVariant { param($d) $d.type = 'something_else' }
        { Read-ChannelForgeAedDefaults -Path $p } | Should -Throw '*not a valid AED defaults export*Details*'
    }

    It 'rejects a wrong version' {
        $p = New-AedVariant { param($d) $d.version = 2 }
        { Read-ChannelForgeAedDefaults -Path $p } | Should -Throw '*not a valid AED defaults export*Details*'
    }

    It 'rejects a file with no defaults' {
        $p = New-AedVariant { param($d) $d.PSObject.Properties.Remove('defaults') }
        { Read-ChannelForgeAedDefaults -Path $p } | Should -Throw '*not a valid AED defaults export*Details*'
    }

    It 'rejects an unknown top-level field' {
        $p = New-AedVariant { param($d) $d | Add-Member -NotePropertyName extra -NotePropertyValue 1 }
        { Read-ChannelForgeAedDefaults -Path $p } | Should -Throw '*not a valid AED defaults export*Details*'
    }

    It 'rejects bad value types' {
        $p = New-AedVariant { param($d) $d.defaults.include_ended_hours = 'eighteen' }
        { Read-ChannelForgeAedDefaults -Path $p } | Should -Throw '*not a valid AED defaults export*'
        $p = New-AedVariant { param($d) $d.defaults.clean_regex_output = 'yes' }
        { Read-ChannelForgeAedDefaults -Path $p } | Should -Throw '*not a valid AED defaults export*'
    }

    It 'gives a plain error for a missing file and for bad JSON' {
        { Read-ChannelForgeAedDefaults -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw '*not found*Details*'
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ not json'
        { Read-ChannelForgeAedDefaults -Path $bad } | Should -Throw '*not a valid AED defaults export*Details*'
    }

    It 'blanks a web address in logo_url and never returns it' {
        $secret = 'http://user:pw@example.invalid/logo.png'
        $p = New-AedVariant { param($d) $d.defaults.logo_url = $secret }
        $r = Read-ChannelForgeAedDefaults -Path $p
        $r.Defaults.logo_url | Should -Be ''
        $r.Warnings.Count | Should -Be 1
        $r.Warnings[0] | Should -BeLike "*logo_url*"
        (($r | ConvertTo-Json -Depth 5) -match 'example.invalid|user:pw') | Should -BeFalse
    }

    It 'ignores an unknown default with a warning and keeps the rest' {
        $p = New-AedVariant { param($d) $d.defaults | Add-Member -NotePropertyName new_setting -NotePropertyValue 'x' }
        $r = Read-ChannelForgeAedDefaults -Path $p
        $r.Warnings | Should -Contain "Unknown setting 'new_setting' was ignored."
        $r.Defaults.PSObject.Properties.Name | Should -Not -Contain 'new_setting'
        $r.Defaults.event_duration | Should -Be '3 Hours'
    }

    It 'accepts empty strings' {
        $p = New-AedVariant { param($d) $d.defaults.source_time_zone = ''; $d.defaults.event_duration = '' }
        $r = Read-ChannelForgeAedDefaults -Path $p
        $r.Defaults.source_time_zone | Should -Be ''
        $r.Warnings.Count | Should -Be 0
    }
}
