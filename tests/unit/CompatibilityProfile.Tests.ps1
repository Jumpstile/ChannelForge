BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:ProfilePath = Join-Path $script:RepoRoot 'data\compatibility\generic-m3u-xmltv.profile.json'

    function script:New-ProfileCopy {
        param([scriptblock]$Edit)
        $profile = Get-Content -LiteralPath $script:ProfilePath -Raw | ConvertFrom-Json
        & $Edit $profile
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
        $path
    }
}

Describe 'Get-ChannelForgeCompatibilityProfile' {
    It 'loads the generic profile' {
        $result = Get-ChannelForgeCompatibilityProfile -Path $script:ProfilePath
        $result.id | Should -Be 'generic-m3u-xmltv'
        $result.capabilities.timezones.evidence.state | Should -Be 'tested'
    }

    It 'rejects an evidence state that is not one of the five' {
        $path = New-ProfileCopy { param($p) $p.capabilities.tvg_id.evidence.state = 'probably' }
        { Get-ChannelForgeCompatibilityProfile -Path $path } | Should -Throw '*not valid*'
    }

    It 'rejects a capability with no evidence state' {
        $path = New-ProfileCopy { param($p) $p.capabilities.tvg_id.evidence.PSObject.Properties.Remove('state') }
        { Get-ChannelForgeCompatibilityProfile -Path $path } | Should -Throw '*not valid*'
    }

    It 'keeps unknown as unknown and refuses to turn it into a claim' {
        $result = Get-ChannelForgeCompatibilityProfile -Path $script:ProfilePath
        $result.capabilities.catchup_timeshift.evidence.state | Should -Be 'unknown'
        $result.capabilities.catchup_timeshift.value | Should -Be 'unknown'

        $path = New-ProfileCopy { param($p) $p.capabilities.catchup_timeshift.value = 'supported' }
        { Get-ChannelForgeCompatibilityProfile -Path $path } | Should -Throw '*not valid*'
    }

    It 'fails with a plain message when the file is missing' {
        { Get-ChannelForgeCompatibilityProfile -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw '*not found*'
    }

    It 'never writes anything' {
        $dir = Split-Path $script:ProfilePath
        $before = @(Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object { '{0}:{1}' -f $_.Name, (Get-FileHash -LiteralPath $_.FullName).Hash })
        Get-ChannelForgeCompatibilityProfile -Path $script:ProfilePath | Out-Null
        $after = @(Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object { '{0}:{1}' -f $_.Name, (Get-FileHash -LiteralPath $_.FullName).Hash })
        $after | Should -Be $before
    }
}
