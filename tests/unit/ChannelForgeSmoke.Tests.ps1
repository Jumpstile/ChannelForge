BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SmokeDir = Join-Path $repoRoot 'scripts/smoke'
    . (Join-Path $script:SmokeDir 'Invoke-ChannelForgeSmoke.ps1')
    . (Join-Path $script:SmokeDir 'New-ChannelForgeSmokeLaunch.ps1')

    function New-Candidate([string]$Root, [string]$RecordedHash) {
        $zip = Join-Path $Root 'ChannelForge-test.zip'
        [IO.File]::WriteAllBytes($zip, [byte[]](1..64))
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        $hash = if ($RecordedHash) { $RecordedHash } else { $actual }
        [ordered]@{
            PackageFilename = 'ChannelForge-test.zip'
            PackageSha256 = $hash
            PackageSourceCommitSha = ('a' * 40)
        } | ConvertTo-Json | Set-Content -LiteralPath ($zip + '.evidence.json')
        return $zip
    }
}

Describe 'Smoke host launcher candidate checks' {
    It 'refuses a missing ZIP' {
        { Assert-SmokeCandidate -PackagePath (Join-Path $TestDrive 'nope.zip') } | Should -Throw '*not found*'
    }

    It 'refuses a ZIP whose SHA-256 does not match the evidence file' {
        $zip = New-Candidate -Root $TestDrive -RecordedHash ('0' * 64)
        { Assert-SmokeCandidate -PackagePath $zip } | Should -Throw '*does not match*'
    }

    It 'accepts a ZIP that matches its evidence file' {
        $zip = New-Candidate -Root $TestDrive
        (Assert-SmokeCandidate -PackagePath $zip).PackageSourceCommitSha | Should -Be ('a' * 40)
    }
}

Describe 'Windows Sandbox template' {
    It 'fills every placeholder and escapes host paths' {
        $template = Join-Path $script:SmokeDir 'ChannelForge-Smoke.wsb.template'
        $xml = New-SmokeWsbContent -TemplatePath $template -InputFolder 'C:\temp\a & b\in' -ResultsFolder 'C:\temp\a & b\results'
        $xml | Should -Not -Match '\{\{'
        $xml | Should -Match ([regex]::Escape('C:\temp\a &amp; b\in'))
        { [xml]$xml } | Should -Not -Throw
    }

    It 'maps the input folder read-only and the results folder writable' {
        $template = Join-Path $script:SmokeDir 'ChannelForge-Smoke.wsb.template'
        $config = [xml](New-SmokeWsbContent -TemplatePath $template -InputFolder 'C:\in' -ResultsFolder 'C:\out')
        $folders = @($config.Configuration.MappedFolders.MappedFolder)
        ($folders | Where-Object { $_.HostFolder -eq 'C:\in' }).ReadOnly | Should -Be 'true'
        ($folders | Where-Object { $_.HostFolder -eq 'C:\out' }).ReadOnly | Should -Be 'false'
    }
}

Describe 'Smoke evidence writer' {
    BeforeEach { $script:Steps.Clear() }

    It 'never reports PASS for a step marked NOT RUN, and the run is not PASS' {
        Add-SmokeStep -Id 'a' -Name 'First' -Status 'PASS'
        Skip-SmokeStep -Id 'update-check-github' -Name 'GitHub check' -Reason 'No network.'
        $out = Join-Path $TestDrive 'ev1'
        $result = Write-SmokeEvidence -Steps @($script:Steps) -ResultsRoot $out -PackageFilename 'p.zip' -PackageSha256 ('b' * 64) -SourceCommitSha ('c' * 40) -StartedUtc 'x'
        $result.Overall | Should -Be 'INCOMPLETE'
        $json = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        ($json.Steps | Where-Object Id -eq 'update-check-github').Status | Should -Be 'NOT RUN'
        $json.Overall | Should -Not -Be 'PASS'
        (Get-Content -LiteralPath $result.TextPath) -match '^NOT RUN\s+update-check-github' | Should -Not -BeNullOrEmpty
        (Get-Content -LiteralPath $result.TextPath) -match '^PASS\s+update-check-github' | Should -BeNullOrEmpty
        $json.PackageSha256 | Should -Be ('b' * 64)
        $json.SourceCommitSha | Should -Be ('c' * 40)
    }

    It 'writes planned steps that never ran as NOT RUN' {
        Add-SmokeStep -Id 'package-hash' -Name 'Hash' -Status 'FAIL' -Detail 'bad'
        $result = Write-SmokeEvidence -Steps @($script:Steps) -PlannedIds @('package-hash', 'install') -ResultsRoot (Join-Path $TestDrive 'ev2') -PackageFilename 'p.zip' -PackageSha256 '' -SourceCommitSha '' -StartedUtc 'x'
        $result.Overall | Should -Be 'FAIL'
        $json = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        ($json.Steps | Where-Object Id -eq 'install').Status | Should -Be 'NOT RUN'
    }

    It 'turns a check that does not return true into FAIL, not PASS' {
        Invoke-SmokeStep -Id 's1' -Name 'Returns text' -Check { 'looks fine' }
        Invoke-SmokeStep -Id 's2' -Name 'Throws' -Check { throw 'boom' }
        Invoke-SmokeStep -Id 's3' -Name 'True' -Check { $true }
        ($script:Steps | Where-Object Id -eq 's1').Status | Should -Be 'FAIL'
        ($script:Steps | Where-Object Id -eq 's2').Status | Should -Be 'FAIL'
        ($script:Steps | Where-Object Id -eq 's3').Status | Should -Be 'PASS'
    }

    It 'rejects a status that is not PASS, FAIL, or NOT RUN' {
        { Add-SmokeStep -Id 'x' -Name 'Bad' -Status 'OK' } | Should -Throw
    }
}
