BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force
    $script:ref = 'a' * 32
    $script:link = 'https://tv.example.invalid/get.php?username=demo&password=demo-not-real&type=m3u_plus'
    $script:hostOnly = 'https://tv.example.invalid'
    function Get-Finding {
        & (Get-Module ChannelForge) { param($r, $h) Get-ChannelForgeSourceReachabilityFinding -Name 'Main' -Kind M3U -CredentialRef $r -DisplayHost $h -RepositoryRoot $env:TEMP } $script:ref $script:hostOnly
    }
    function Mock-Secret {
        Mock -CommandName Read-ChannelForgeSourceSecret -ModuleName ChannelForge -MockWith {
            [pscustomobject]@{ Success = $true; Category = 'None'; Secret = (ConvertTo-SecureString -String 'https://tv.example.invalid/get.php?username=demo&password=demo-not-real&type=m3u_plus' -AsPlainText -Force) }
        }
    }
}

Describe 'Doctor for a credentialed source' {
    It 'probes with the saved link and shows the host only' {
        Mock-Secret
        $global:DoctorPayload = [pscustomobject]@{ ResponseStream = [IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes('#EXTM3U')) }
        $global:DoctorPayload | Add-Member ScriptMethod Dispose { $this.ResponseStream.Dispose() }
        Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith { $global:DoctorPayload }
        $f = Get-Finding
        $f.Status | Should -Be 'Pass'
        $f.Root | Should -Be 'https://tv.example.invalid/...'
        ($f | Out-String) | Should -Not -Match 'demo|password|username|get\.php'
        Should -Invoke Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -ParameterFilter { $Url -like '*password=demo-not-real*' }
    }

    It 'fails with the plain message and no network call when the secret is missing' {
        Mock -CommandName Read-ChannelForgeSourceSecret -ModuleName ChannelForge -MockWith { [pscustomobject]@{ Success = $false; Category = 'Missing'; Secret = $null } }
        Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith { throw 'must not be called' }
        $f = Get-Finding
        $f.Status | Should -Be 'Fail'
        $f.Observed | Should -Be 'The saved login for https://tv.example.invalid is missing, unreadable or was rejected (Missing).'
        $f.NextStep | Should -Match 'enroll command again'
        Should -Invoke Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -Times 0
    }

    It 'keeps a network error as Fail with the category only' {
        Mock-Secret
        Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith {
            $e = [System.InvalidOperationException]::new('failed for https://tv.example.invalid/get.php?password=demo-not-real'); $e.Data['ChannelForgeFailureCategory'] = 'Timeout'; throw $e }
        $f = Get-Finding
        $f.Status | Should -Be 'Fail'
        $f.Observed | Should -Be 'The source could not be reached (Timeout).'
        ($f | Out-String) | Should -Not -Match 'demo|password'
    }

    It 'lists a saved-login source from the enrollment record without a link' {
        Mock -CommandName Read-ChannelForgeProvider -ModuleName ChannelForge -MockWith { @() }
        Mock -CommandName Read-ChannelForgeEpgSource -ModuleName ChannelForge -MockWith { @() }
        Mock -CommandName Read-ChannelForgeSourceEnrollmentRecord -ModuleName ChannelForge -MockWith {
            [pscustomobject]@{ Playlists = @([pscustomobject]@{ Label = 'Main'; Kind = 'M3U'; Enabled = $true; CredentialRef = ('a' * 32); DisplayHost = 'https://tv.example.invalid' }); Guides = @() } }
        Mock -CommandName Read-ChannelForgeSourceSecret -ModuleName ChannelForge -MockWith { [pscustomobject]@{ Success = $false; Category = 'Missing'; Secret = $null } }
        $found = & (Get-Module ChannelForge) { Get-ChannelForgeSourceReachabilityFindings -RepositoryRoot $env:TEMP -ProviderConfigPath 'x' -EpgConfigPath 'y' }
        @($found).Count | Should -Be 1
        $found[0].Root | Should -Be 'https://tv.example.invalid/...'
        $found[0].Status | Should -Be 'Fail'
    }

    It 'reports an unreadable enrollment record and still probes the other sources' {
        Mock -CommandName Read-ChannelForgeProvider -ModuleName ChannelForge -MockWith { @([pscustomobject]@{ Name = 'Plain'; Enabled = $true; LocalPlaylist = ''; Url = 'https://plain.example.invalid/list.m3u' }) }
        Mock -CommandName Read-ChannelForgeEpgSource -ModuleName ChannelForge -MockWith { @() }
        Mock -CommandName Read-ChannelForgeSourceEnrollmentRecord -ModuleName ChannelForge -MockWith { throw 'FAIL_CLOSED: source enrollment integrity check failed.' }
        Mock -CommandName Get-ChannelForgeSourceReachabilityFinding -ModuleName ChannelForge -MockWith { [pscustomobject]@{ Check = $Name; Status = 'Pass' } }
        $found = @(& (Get-Module ChannelForge) { Get-ChannelForgeSourceReachabilityFindings -RepositoryRoot $env:TEMP -ProviderConfigPath 'x' -EpgConfigPath 'y' })
        $found.Count | Should -Be 2
        $found[0].Status | Should -Be 'Unknown'
        $found[1].Check | Should -Be 'Plain'
    }
}

Describe 'Remove-ChannelForgeSecretFromText' {
    It 'removes known secret values and whole links from error text' {
        $text = & (Get-Module ChannelForge) {
            param($l) Remove-ChannelForgeSecretFromText -Text "Request failed: $l (password demo-not-real rejected) see https://other.example.invalid/a?token=zzz" -Secret @($l, 'demo-not-real')
        } $script:link
        $text | Should -Not -Match 'demo|password=|token|get\.php|zzz'
        $text | Should -Match 'https://other\.example\.invalid/\.\.\.'
    }
}
