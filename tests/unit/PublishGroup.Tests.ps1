BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Baseline = Get-Content (Join-Path $script:Root 'tests/fixtures/publish-group-baseline.json') -Raw | ConvertFrom-Json
    # Baseline values were recorded by running the same probe on the unchanged code.
    $script:Now = (& pwsh -NoProfile -File (Join-Path $script:Root 'tests/fixtures/publish-group-probe.ps1') -Root $script:Root -WorkDir $TestDrive 2>$null) -join "`n" -replace '(?s)^.*?(?=\{)', '' | ConvertFrom-Json
}

Describe 'Publish group step, filling off' {
    It 'keeps v8 M3U bytes and candidate values identical to the unchanged code' {
        $v = 'blocker-2-contract/v8'
        $script:Now.$v.M3UBase64 | Should -Be $script:Baseline.$v.M3UBase64
        $script:Now.$v.Entries.Count | Should -Be 4
        ($script:Now.$v.Entries | ConvertTo-Json -Depth 5) | Should -Be ($script:Baseline.$v.Entries | ConvertTo-Json -Depth 5)
    }
    It 'keeps v7 M3U bytes and candidate values identical to the unchanged code' {
        $v = 'blocker-2-contract/v7'
        $script:Now.$v.M3UBase64 | Should -Be $script:Baseline.$v.M3UBase64
        $script:Now.$v.Entries.Count | Should -Be 4
        ($script:Now.$v.Entries | ConvertTo-Json -Depth 5) | Should -Be ($script:Baseline.$v.Entries | ConvertTo-Json -Depth 5)
    }
    It 'returns the raw group for empty and non-empty groups and drops nothing' {
        Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force 3>$null
        $a = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'A' -DisplayName 'A' -TvgId 'a.invalid' -Url 'https://a.example.invalid/s' -Group 'My Sports'
        $b = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'B' -DisplayName 'B' -TvgId 'b.invalid' -Url 'https://b.example.invalid/s' -Group ''
        $r = @(& (Get-Module ChannelForge) { param($c) Get-ChannelForgePublishGroup -Channel $c } @($a, $b))
        $r.Count | Should -Be 2
        $r[0].Group | Should -BeExactly 'My Sports'
        $r[0].Source | Should -Be 'Provider'
        $r[1].Group | Should -BeExactly ''
        $r[1].RawGroup | Should -BeExactly ''
        $r[1].Source | Should -Be 'None'
        @($r[0].ReviewCandidates).Count | Should -Be 0
        $a.Group | Should -BeExactly 'My Sports'
    }
    It 'refuses -FillFromCategories in this slice' {
        { & (Get-Module ChannelForge) { Get-ChannelForgePublishGroup -Channel @() -FillFromCategories } } | Should -Throw '*not implemented*'
    }
}
