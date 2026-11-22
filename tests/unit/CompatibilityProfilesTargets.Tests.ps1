BeforeDiscovery {
    $script:Ids = @('plex', 'iptvboss', 'dispatcharr')
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Target compatibility profile <_>' -ForEach $script:Ids {
    BeforeAll {
        $script:Path = Join-Path $script:RepoRoot "data\compatibility\$_.profile.json"
        $script:Profile = Get-ChannelForgeCompatibilityProfile -Path $script:Path
    }

    It 'loads and validates against the schema' {
        $script:Profile.id | Should -Be $_
    }

    It 'has no observed state, because no repo doc names an observation' {
        $states = $script:Profile.capabilities.PSObject.Properties | ForEach-Object { $_.Value.evidence.state }
        $states | Should -Not -Contain 'observed'
    }

    It 'has no documented or tested state, because the repo holds no target documentation or target test' {
        $states = $script:Profile.capabilities.PSObject.Properties | ForEach-Object { $_.Value.evidence.state }
        $states | Should -Not -Contain 'documented'
        $states | Should -Not -Contain 'tested'
    }

    It 'names a repo doc for every claim that is not unknown' {
        foreach ($cap in $script:Profile.capabilities.PSObject.Properties) {
            if ($cap.Value.evidence.state -ne 'unknown') {
                Test-Path -LiteralPath (Join-Path $script:RepoRoot $cap.Value.evidence.source) | Should -BeTrue -Because $cap.Name
            }
        }
    }

    It 'contains no URL other than example.invalid' {
        $text = Get-Content -LiteralPath $script:Path -Raw
        $text | Should -Not -Match 'https?://(?!example\.invalid)'
    }
}
