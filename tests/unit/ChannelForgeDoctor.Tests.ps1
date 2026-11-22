BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:doctor = Join-Path $repoRoot 'scripts/Invoke-ChannelForgeDoctor.ps1'
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force
    . (Join-Path $PSScriptRoot 'PreflightFixture.ps1')

    function Invoke-Doctor([string]$Root, [string[]]$Extra = @()) {
        $out = & pwsh -NoProfile -File $script:doctor -Root $Root @Extra 2>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out -replace "`e\[[0-9;]*m", '' }
    }
}

Describe 'Invoke-ChannelForgeDoctor.ps1' {
    It 'exits 0 and shows only Pass for a healthy project' {
        $p = New-Project; Publish-Fixture $p | Out-Null
        $r = Invoke-Doctor $p
        $r.Code | Should -Be 0
        $r.Text | Should -Not -Match '\[(FAIL|UNKNOWN)'
        $r.Text | Should -Match 'PASS'
    }

    It 'fails a missing output folder with a next step and exits 1' {
        $p = New-Project
        $r = Invoke-Doctor $p @('-OutputRoot', (Join-Path $p 'output/nope'))
        $r.Code | Should -Be 1
        $r.Text | Should -Match '\[FAIL   \] OutputRoot exists'
        $r.Text | Should -Match 'Next step: \S'
    }

    It 'never shows an unknown check as Pass' {
        $p = New-Project
        $r = Invoke-Doctor $p
        $r.Code | Should -Be 1
        $r.Text | Should -Match '\[UNKNOWN\] published M3U matches manifest'
        $r.Text | Should -Not -Match '\[PASS   \] published'
    }
}
