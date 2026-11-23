BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Script = Join-Path $script:Root 'scripts\Enroll-ChannelForgeRemoteSource.ps1'
    Import-Module (Join-Path $script:Root 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Login = 'demo-not-real'
    $script:Link = 'https://tv.example.invalid/get.php?username=demo&password=demo-not-real&type=m3u_plus'
}

AfterAll {
    Remove-Variable -Name CfTestLink, CfTestProbePasses -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Enroll-ChannelForgeRemoteSource' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ('p' + [guid]::NewGuid().ToString('N'))
        $script:Creds = Join-Path $TestDrive ('c' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Project | Out-Null
        $global:CfTestLink = $script:Link
        Mock Read-Host { ConvertTo-SecureString -String $global:CfTestLink -AsPlainText -Force }
        $global:CfTestProbePasses = $true
        Mock -ModuleName ChannelForge Get-ChannelForgeSourceReachabilityFinding {
            $status = if ($global:CfTestProbePasses) { 'Pass' } else { 'Fail' }
            $seen = if ($global:CfTestProbePasses) { 'The source answered and the first 10 bytes were readable.' } else { 'The source could not be reached (HttpStatusRejected).' }
            [pscustomobject]@{ Status = $status; Observed = $seen }
        }
        function Invoke-Enroll {
            param([string[]]$Switches = @())
            $splat = @{ RepositoryRoot = $script:Project; CredentialRoot = $script:Creds; Label = 'Demo' }
            foreach ($s in $Switches) { $splat[$s] = $true }
            $out = $null
            $err = $null
            try { $out = & $script:Script @splat *>&1 | Out-String } catch { $err = $_.Exception.Message }
            [pscustomobject]@{ Output = [string]$out; Error = $err }
        }
        function Get-CredFiles { @(Get-ChildItem -LiteralPath $script:Creds -File -ErrorAction SilentlyContinue) }
        function Get-AllWrittenText {
            $text = ''
            foreach ($dir in $script:Project, $script:Creds) {
                foreach ($f in Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue) { $text += [IO.File]::ReadAllText($f.FullName) }
            }
            $text
        }
    }

    It 'dry run saves nothing and prints host only with the not-tested line' {
        $r = Invoke-Enroll -Switches DryRun
        $r.Error | Should -BeNullOrEmpty
        $r.Output | Should -BeLike '*Login test: PASS*'
        $r.Output | Should -BeLike '*Not tested: the full download*'
        Get-CredFiles | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:Project 'state\source-enrollment.json') | Should -BeFalse
        $r.Output | Should -Not -BeLike "*$script:Login*"
    }

    It 'saves nothing when the probe fails and names only the category' {
        $global:CfTestProbePasses = $false
        $r = Invoke-Enroll
        $r.Error | Should -BeLike '*HttpStatusRejected*'
        $r.Error | Should -Not -BeLike "*$script:Login*"
        Get-CredFiles | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:Project 'state\source-enrollment.json') | Should -BeFalse
    }

    It 'saves the secret and a record with ref and host only, and never shows the login' {
        $r = Invoke-Enroll
        $r.Error | Should -BeNullOrEmpty
        $r.Output | Should -BeLike '*Enrolled M3U source at https://tv.example.invalid*'
        $files = Get-CredFiles
        $files.Count | Should -Be 1
        $record = (Get-Content -LiteralPath (Join-Path $script:Project 'state\source-enrollment.json') -Raw | ConvertFrom-Json).Playlists[0]
        $record.CredentialRef | Should -Be $files[0].BaseName
        $record.DisplayHost | Should -Be 'https://tv.example.invalid'
        $record.Url | Should -BeNullOrEmpty
        $r.Output | Should -Not -BeLike "*$script:Login*"
        Get-AllWrittenText | Should -Not -BeLike "*$script:Login*"
    }

    It 'with -SkipProbe warns that the login was not tested and still saves' {
        $global:CfTestProbePasses = $false
        $r = Invoke-Enroll -Switches SkipProbe
        $r.Error | Should -BeNullOrEmpty
        $r.Output | Should -BeLike '*was not tested*'
        (Get-CredFiles).Count | Should -Be 1
    }

    It 'removes the new secret file and says so when the record write fails' {
        Mock -ModuleName ChannelForge Add-ChannelForgeCredentialedSourceSetSource { throw 'SOURCE_ENROLLMENT_INVALID: demo-not-real forced failure' }
        $r = Invoke-Enroll
        $r.Error | Should -BeLike '*could not be written*The new login file was removed*'
        $r.Error | Should -Not -BeLike "*$script:Login*"
        $r.Output | Should -Not -BeLike '*Enrolled*'
        Get-CredFiles | Should -BeNullOrEmpty
    }

    It 'refuses a user-info link and saves nothing' {
        $global:CfTestLink = 'https://demo:demo-not-real@tv.example.invalid/list.m3u'
        $r = Invoke-Enroll
        $r.Error | Should -BeLike '*UserInfoNotSupported*Nothing was saved*'
        $r.Error | Should -Not -BeLike "*$script:Login*"
        Get-CredFiles | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:Project 'state\source-enrollment.json') | Should -BeFalse
    }
}
