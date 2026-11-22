BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:doctor = Join-Path $repoRoot 'scripts/Invoke-ChannelForgeDoctor.ps1'
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force
    . (Join-Path $PSScriptRoot 'PreflightFixture.ps1')

    function Invoke-Doctor([string]$Root, [string[]]$Extra = @()) {
        $out = & pwsh -NoProfile -File $script:doctor -Root $Root @Extra 2>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out -replace "`e\[[0-9;]*m", '' }
    }

    function Add-LocalSources([string]$Project) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Project 'data/providers'), (Join-Path $Project 'data/epg'), (Join-Path $Project 'data/playlists') | Out-Null
        Set-Content -LiteralPath (Join-Path $Project 'data/playlists/a.m3u') -Value '#EXTM3U'
        Set-Content -LiteralPath (Join-Path $Project 'data/epg/g.xml') -Value '<tv></tv>'
        '{"provider":"p","sources":[{"name":"Local","group":"G","url":"https://example.invalid/x","enabled":true,"local_playlist":"data/playlists/a.m3u"}]}' | Set-Content -LiteralPath (Join-Path $Project 'data/providers/provider.local.json')
        '{"epg_sources":[{"name":"Guide","path":"g.xml","priority":1,"enabled":true,"role":"primary"}]}' | Set-Content -LiteralPath (Join-Path $Project 'data/epg/epg_sources.local.json')
    }
}

Describe 'Invoke-ChannelForgeDoctor.ps1' {
    It 'exits 0 and shows only Pass for a healthy project' {
        $p = New-Project; Publish-Fixture $p | Out-Null; Add-LocalSources $p
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
        $p = New-Project; Add-LocalSources $p
        $r = Invoke-Doctor $p
        $r.Code | Should -Be 1
        $r.Text | Should -Match '\[UNKNOWN\] published M3U matches manifest'
        $r.Text | Should -Not -Match '\[PASS   \] published'
    }

    It 'fails a missing local source file and never shows it as Pass' {
        $p = New-Project; Publish-Fixture $p | Out-Null; Add-LocalSources $p
        Remove-Item -LiteralPath (Join-Path $p 'data/playlists/a.m3u')
        $r = Invoke-Doctor $p
        $r.Code | Should -Be 1
        $r.Text | Should -Match "\[FAIL   \] M3U source 'Local' reachable"
    }

    It 'is Unknown when no source settings can be read' {
        $p = New-Project; Publish-Fixture $p | Out-Null
        $r = Invoke-Doctor $p
        $r.Code | Should -Be 1
        $r.Text | Should -Match '\[UNKNOWN\] (source settings readable|sources configured)'
    }
}

Describe 'Get-ChannelForgeSourceReachabilityFinding' {
    BeforeAll {
        $script:url = 'https://user:secret@example.invalid/path-token/list.m3u?key=abc123'
        function Set-Payload([byte[]]$Bytes) {
            $global:DoctorPayload = [pscustomobject]@{ ResponseStream = [IO.MemoryStream]::new($Bytes) }
            $global:DoctorPayload | Add-Member ScriptMethod Dispose { $this.ResponseStream.Dispose() }
            Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith { $global:DoctorPayload }
        }
        function Get-Finding { & (Get-Module ChannelForge) { param($u) Get-ChannelForgeSourceReachabilityFinding -Name 'S' -Kind M3U -Url $u -RepositoryRoot $env:TEMP } $script:url }
    }

    It 'passes on a readable answer and shows no credentials, path or query' {
        Set-Payload ([Text.Encoding]::ASCII.GetBytes('#EXTM3U'))
        $f = Get-Finding
        $f.Status | Should -Be 'Pass'
        ($f | Out-String) | Should -Not -Match 'secret|path-token|abc123|key='
        $f.Root | Should -Be 'https://example.invalid/...'
    }

    It 'fails an empty answer' {
        Set-Payload ([byte[]]@())
        (Get-Finding).Status | Should -Be 'Fail'
    }

    It 'fails a transport error and is Unknown when the transport cannot start' {
        foreach ($case in @(@('NetworkFailure', 'Fail'), @('HelperInitializationFailure', 'Unknown'))) {
            $global:DoctorCategory = $case[0]
            Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith {
                $e = [System.InvalidOperationException]::new('x'); $e.Data['ChannelForgeFailureCategory'] = $global:DoctorCategory; throw $e }
            (Get-Finding).Status | Should -Be $case[1]
        }
    }
}

Describe 'Doctor result in the web status' {
    It 'shows the saved Doctor result without addresses, and "not run yet" before Doctor runs' {
        $p = New-Project; Publish-Fixture $p | Out-Null; Add-LocalSources $p
        (Get-ChannelForgeWebStatus -RepositoryRoot $p).DoctorStatus.Overall | Should -Be 'NotRun'
        (Invoke-Doctor $p).Code | Should -Be 0
        $doctor = (Get-ChannelForgeWebStatus -RepositoryRoot $p).DoctorStatus
        $doctor.Overall | Should -Be 'Pass'
        $doctor.Fail | Should -Be 0
        $doctor.Summary | Should -Match '^PASS: \d+ passed'
        ($doctor | ConvertTo-Json -Compress) | Should -Not -Match '(?i)https?://|[A-Z]:[\\/]'
    }

    It 'reports a failed Doctor run and honors -OutputPath' {
        $p = New-Project
        $target = Join-Path $p 'elsewhere/result.json'
        (Invoke-Doctor $p @('-OutputRoot', (Join-Path $p 'output/nope'), '-OutputPath', $target)).Code | Should -Be 1
        (Get-Content -LiteralPath $target -Raw | ConvertFrom-Json).Overall | Should -Be 'Fail'
        New-Item -ItemType Directory -Force -Path (Join-Path $p 'state') | Out-Null
        Copy-Item -LiteralPath $target -Destination (Join-Path $p 'state/doctor-result.json')
        $doctor = (Get-ChannelForgeWebStatus -RepositoryRoot $p).DoctorStatus
        $doctor.Overall | Should -Be 'Fail'
        $doctor.Fail | Should -BeGreaterThan 0
    }

    It 'never reports an unreadable saved result as Pass' {
        $p = New-Project
        New-Item -ItemType Directory -Force -Path (Join-Path $p 'state') | Out-Null
        Set-Content -LiteralPath (Join-Path $p 'state/doctor-result.json') -Value '{not json'
        (Get-ChannelForgeWebStatus -RepositoryRoot $p).DoctorStatus.Overall | Should -Be 'Unknown'
    }
}

Describe 'Doctor result save failure' {
    It 'says so and exits 1 when the result cannot be saved, even for a healthy project' {
        $p = New-Project; Publish-Fixture $p | Out-Null; Add-LocalSources $p
        $blocker = Join-Path $p 'blocker'
        Set-Content -LiteralPath $blocker -Value 'x'
        $r = Invoke-Doctor $p @('-OutputPath', (Join-Path $blocker 'result.json'))
        $r.Code | Should -Be 1
        $r.Text | Should -Match 'Could not save the Doctor result'
    }
}
