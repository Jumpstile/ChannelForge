BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Executor = Join-Path $script:Root 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
    $script:Login = 'demo-not-real'
    $script:Link = 'https://tv.example.invalid/get.php?username=demo&password=' + $script:Login
    $script:HostLabel = 'https://tv.example.invalid'
    $script:Message = "The saved login for $($script:HostLabel) is missing, unreadable or was rejected. Run the enroll command again for this source."
    $script:M3U = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n")
    $script:NewM3U = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttp://tv.example.invalid/live/demo/$($script:Login)/1.ts`n")
    $global:CredNewM3U = $script:NewM3U
    $global:CredLink = $script:Link

    function Save-FakeSecret {
        param([string]$CredentialRoot)
        & (Get-Module ChannelForge) {
            param($Link, $CredentialRoot)
            (Save-ChannelForgeSourceSecret -Secret (ConvertTo-SecureString -String $Link -AsPlainText -Force) -CredentialRoot $CredentialRoot).RefId
        } $script:Link $CredentialRoot
    }

    function New-RefreshProject {
        param([string]$Ref)
        $root = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/rules'), (Join-Path $root 'data/lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Root 'data/rules/aliases.json') -Destination (Join-Path $root 'data/rules/aliases.json')
        Copy-Item -LiteralPath (Join-Path $script:Root 'data/lineup/numbering_blocks.json') -Destination (Join-Path $root 'data/lineup/numbering_blocks.json')
        $secretSource = [pscustomobject]@{ Kind = 'M3U'; SourceKind = 'public-https'; Label = 'Credentialed'; Priority = 1; Url = $null; CredentialRef = $Ref; DisplayHost = $script:HostLabel }
        $publicSource = [pscustomobject]@{ Kind = 'M3U'; SourceKind = 'public-https'; SourceKey = 'public'; Label = 'Public'; Priority = 2; Url = 'https://example.invalid/public.m3u'; Bytes = $script:M3U }
        & (Get-Module ChannelForge) {
            param($root, $sources)
            Write-ChannelForgeSourceSet -RepositoryRoot $root -PlaylistSources @($sources) | Out-Null
        } $root @($secretSource, $publicSource)
        return $root
    }

    function Invoke-Refresh {
        param([string]$Root)
        $out = & $script:Executor -Root $Root -EnrollmentPath (Join-Path $Root 'state/source-enrollment.json') -OutputRoot (Join-Path $Root 'reports') *>&1
        $result = @($out | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.Properties['JsonPath'] })[0]
        [pscustomobject]@{
            Report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
            Shown  = (($out | ForEach-Object { [string]$_ }) -join "`n") + (Get-Content -LiteralPath $result.JsonPath -Raw) + (Get-Content -LiteralPath $result.MarkdownPath -Raw)
        }
    }

    function Get-SavedSetHash {
        param([string]$Root)
        # Saved snapshots (the last-known-good data). The refresh status marker in the record may change by design.
        ((Get-ChildItem -LiteralPath (Join-Path $Root 'state/managed-sources') -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash) -join '')
    }
}

Describe 'credentialed remote source bytes' {
    BeforeEach {
        $script:CredRoot = Join-Path $TestDrive ('cred-' + [guid]::NewGuid().ToString('N'))
        Mock -ModuleName ChannelForge -CommandName Get-ChannelForgeCredentialRoot -MockWith { $script:CredRoot }
        $script:Ref = Save-FakeSecret -CredentialRoot $script:CredRoot
    }

    It 'sends the saved link to the transport in memory and returns the bytes' {
        $script:SeenUrl = $null
        Mock -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -MockWith { $script:SeenUrl = $Url; , $script:M3U }
        $bytes = Get-ChannelForgeRemoteSourceBytes -Kind M3U -CredentialRef $script:Ref -DisplayHost $script:HostLabel -MaxBytes 1MB
        $script:SeenUrl | Should -Be $script:Link
        [Text.Encoding]::UTF8.GetString($bytes) | Should -Be ([Text.Encoding]::UTF8.GetString($script:M3U))
    }

    It 'fails with the host-only message when the secret file is missing' {
        Remove-Item -LiteralPath (Join-Path $script:CredRoot ($script:Ref + '.cred')) -Force
        Mock -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -MockWith { , $script:M3U }
        $err = { Get-ChannelForgeRemoteSourceBytes -Kind M3U -CredentialRef $script:Ref -DisplayHost $script:HostLabel -MaxBytes 1MB } | Should -Throw -PassThru
        $err.Exception.Message | Should -Be $script:Message
        Should -Invoke -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -Times 0
    }

    It 'fails with the host-only message when the secret file is corrupt' {
        Set-Content -LiteralPath (Join-Path $script:CredRoot ($script:Ref + '.cred')) -Value 'not json'
        $err = { Get-ChannelForgeRemoteSourceBytes -Kind M3U -CredentialRef $script:Ref -DisplayHost $script:HostLabel -MaxBytes 1MB } | Should -Throw -PassThru
        $err.Exception.Message | Should -Be $script:Message
    }

    It 'treats a 401 or 403 from the provider as a rejected login' -ForEach @(401, 403) {
        $script:Code = $_
        Mock -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -MockWith {
            $e = [System.InvalidOperationException]::new("denied $($script:Link)")
            $e.Data['ChannelForgeFailureStatusCode'] = $script:Code
            throw $e
        }
        $err = { Get-ChannelForgeRemoteSourceBytes -Kind M3U -CredentialRef $script:Ref -DisplayHost $script:HostLabel -MaxBytes 1MB } | Should -Throw -PassThru
        $err.Exception.Message | Should -Be $script:Message
    }

    It 'replaces any other transport failure with a category-only message' {
        Mock -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -MockWith {
            $e = [System.InvalidOperationException]::new("failed for $($script:Link)")
            $e.Data['ChannelForgeFailureCategory'] = 'NonSuccessHttpStatus'
            throw $e
        }
        $err = { Get-ChannelForgeRemoteSourceBytes -Kind M3U -CredentialRef $script:Ref -DisplayHost $script:HostLabel -MaxBytes 1MB } | Should -Throw -PassThru
        $err.Exception.Message | Should -Be 'Remote source request failed [NonSuccessHttpStatus].'
        $err.Exception.Message | Should -Not -BeLike "*$($script:Login)*"
    }
}

Describe 'refresh run with a credentialed source' {
    BeforeEach {
        Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
    }

    It 'refreshes it with the saved login and keeps the login out of every shown output' {
        $ref = ('a' * 32)
        $root = New-RefreshProject -Ref $ref
        $global:CredCalls = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -MockWith {
            $global:CredCalls.Add([pscustomobject]@{ Ref = $CredentialRef; Url = $Url }) | Out-Null
            , $global:CredNewM3U
        }
        $run = Invoke-Refresh $root
        $global:CredCalls.Count | Should -Be 2
        @($global:CredCalls | Where-Object { $_.Ref -eq $ref -and -not $_.Url }).Count | Should -Be 1
        @($run.Report.Sources | Where-Object Result -eq 'REFRESH_FAILED').Count | Should -Be 0
        $run.Shown | Should -Not -BeLike "*$($script:Login)*"
        # The private snapshot candidate may carry the login in stream links.
        $candidateText = (Get-ChildItem -LiteralPath (Join-Path $root 'reports/refresh-candidates') -Recurse -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $candidateText | Should -BeLike "*$($script:Login)*"
    }

    It 'skips only that source when the saved login is missing, with the host-only message' {
        $cred = Join-Path $TestDrive ('cred-' + [guid]::NewGuid().ToString('N'))
        Mock -ModuleName ChannelForge -CommandName Get-ChannelForgeCredentialRoot -MockWith { $cred }
        $global:CredTransportCalled = $false
        Mock -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -MockWith { $global:CredTransportCalled = $true; , $global:CredNewM3U }
        $root = New-RefreshProject -Ref ('b' * 32)
        $global:CredReal = (Get-Command Get-ChannelForgeRemoteSourceBytes).ScriptBlock
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -ParameterFilter { $Url } -MockWith { , $global:CredNewM3U }
        # The real function runs for the credentialed source. No secret file exists, so the transport double must not run.
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -ParameterFilter { $CredentialRef } -MockWith { & $global:CredReal @PesterBoundParameters }
        $before = Get-SavedSetHash $root
        $run = Invoke-Refresh $root
        $failed = @($run.Report.Sources | Where-Object Result -eq 'REFRESH_FAILED')
        $failed.Count | Should -Be 1
        $failed[0].Name | Should -Be 'Credentialed'
        $failed[0].SafeReason | Should -Be $script:Message
        @($run.Report.Sources | Where-Object { $_.Name -eq 'Public' -and $_.Result -ne 'REFRESH_FAILED' }).Count | Should -Be 1
        Get-SavedSetHash $root | Should -Be $before
        $global:CredTransportCalled | Should -BeFalse
        $run.Shown | Should -Not -BeLike '*password=*'
        $run.Shown | Should -Not -BeLike "*$($script:Login)*"
    }

    It 'skips only that source on a provider 401 and shows no login' {
        $cred = Join-Path $TestDrive ('cred-' + [guid]::NewGuid().ToString('N'))
        Mock -ModuleName ChannelForge -CommandName Get-ChannelForgeCredentialRoot -MockWith { $cred }
        $ref = Save-FakeSecret -CredentialRoot $cred
        $root = New-RefreshProject -Ref $ref
        $global:CredTransportCalled = $false
        Mock -ModuleName ChannelForge -CommandName Read-ChannelForgeGuidedSetupRemoteBytes -MockWith {
            $global:CredTransportCalled = $true
            $e = [System.InvalidOperationException]::new("denied $($global:CredLink)")
            $e.Data['ChannelForgeFailureStatusCode'] = 401
            throw $e
        }
        $global:CredReal = (Get-Command Get-ChannelForgeRemoteSourceBytes).ScriptBlock
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -ParameterFilter { $Url } -MockWith { , $global:CredNewM3U }
        Mock -CommandName Get-ChannelForgeRemoteSourceBytes -ParameterFilter { $CredentialRef } -MockWith { & $global:CredReal @PesterBoundParameters }
        $before = Get-SavedSetHash $root
        $run = Invoke-Refresh $root
        $failed = @($run.Report.Sources | Where-Object Result -eq 'REFRESH_FAILED')
        $failed.Count | Should -Be 1
        $failed[0].SafeReason | Should -Be $script:Message
        @($run.Report.Sources | Where-Object { $_.Name -eq 'Public' -and $_.Result -ne 'REFRESH_FAILED' }).Count | Should -Be 1
        Get-SavedSetHash $root | Should -Be $before
        $global:CredTransportCalled | Should -BeTrue
        $run.Shown | Should -Not -BeLike "*$($script:Login)*"
    }
}
