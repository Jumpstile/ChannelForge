BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # An import folder with guide files and some files that must not be listed, plus a config folder with one admin and one viewer.
    function New-TestSetup {
        $root = Join-Path $TestDrive ('imp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'guide one.xml') -Value '<tv/>'
        Set-Content -LiteralPath (Join-Path $root 'big.xml.gz') -Value 'gz'
        Set-Content -LiteralPath (Join-Path $root 'notes.txt') -Value 'x'
        Set-Content -LiteralPath (Join-Path $root 'run.ps1') -Value 'x'
        New-Item -ItemType Directory -Path (Join-Path $root 'sub.xml') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'sub.xml\inner.xml') -Value '<tv/>'
        $config = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $config | Out-Null
        & (Get-Module ChannelForge) {
            param($Config)
            $users = @(
                (New-ChannelForgeUserRecord -Name 'boss' -Role admin -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password 'x-pass-1' -Iterations 1000)),
                (New-ChannelForgeUserRecord -Name 'view' -Role viewer -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password 'x-pass-1' -Iterations 1000))
            )
            Write-ChannelForgeUserStore -ConfigRoot $Config -User $users | Out-Null
        } $config
        [pscustomobject]@{ Root = $root; Config = $config; Store = @{} }
    }

    function Start-TestSession {
        param($S, [string]$Name = 'boss', [datetime]$Now = [datetime]::UtcNow)
        & (Get-Module ChannelForge) {
            param($Config, $Store, $Name, $Now)
            $id = (Read-ChannelForgeUserStore -ConfigRoot $Config).Users | Where-Object Name -eq $Name | Select-Object -First 1 -ExpandProperty Id
            New-ChannelForgeWebSession -Store $Store -UserId $id -Now $Now
        } $S.Config $S.Store $Name $Now
    }

    # One GET /api/import-guides through the real sign-in gate.
    function Get-Guides {
        param($S, [string]$Token, [datetime]$Now = [datetime]::UtcNow, [string]$Method = 'GET')
        $r = & (Get-Module ChannelForge) {
            param($S, $Token, $Now, $Method)
            $x = Get-ChannelForgeWebSignInResponse -Store $S.Store -Method $Method -Path '/api/import-guides' -CookieHeader "cf_session=$Token" -ConfigRoot $S.Config -ImportRoot $S.Root -Now $Now
            [pscustomobject]@{ StatusCode = $x.StatusCode; Raw = [string]$x.Body }
        } $S $Token $Now $Method
        [pscustomobject]@{ StatusCode = $r.StatusCode; Raw = $r.Raw; Json = $(if ($r.Raw) { $r.Raw | ConvertFrom-Json } else { $null }) }
    }

    function Resolve-Handle {
        param($S, [string]$Token, [string]$Handle, [datetime]$Now = [datetime]::UtcNow)
        & (Get-Module ChannelForge) {
            param($S, $Token, $Handle, $Now)
            $session = Get-ChannelForgeWebSession -Store $S.Store -Token $Token -Now $Now
            Resolve-ChannelForgeImportHandle -Session $session -Handle $Handle -ImportRoot $S.Root -Now $Now
        } $S $Token $Handle $Now
    }
}

Describe 'Import folder listing' {
    It 'lists only guide files, with a handle, a safe name and a size, and no path' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $r = Get-Guides $s $t
        $r.StatusCode | Should -Be 200
        @($r.Json.Guides).Count | Should -Be 2
        ($r.Json.Guides.Name | Sort-Object) | Should -Be @('big.xml.gz', 'guide one.xml')
        @($r.Json.Guides[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('Handle', 'Name', 'Size')
        $r.Raw | Should -Not -Match ([regex]::Escape($s.Root))
        $r.Raw | Should -Not -Match '[A-Za-z]:\\\\'
        $r.Raw | Should -Not -Match 'notes|run\.ps1|inner|sub\.xml|Time|Modified'
    }

    It 'shows a sanitized name' {
        $s = New-TestSetup
        Set-Content -LiteralPath (Join-Path $s.Root 'jo$e@home.xml') -Value '<tv/>'
        $r = Get-Guides $s (Start-TestSession $s)
        $r.Json.Guides.Name | Should -Contain 'jo_e_home.xml'
    }

    It 'offers nothing without a session or without an import folder' {
        $s = New-TestSetup
        (Get-Guides $s '').StatusCode | Should -Be 401
        $t = Start-TestSession $s
        $r = & (Get-Module ChannelForge) {
            param($S, $Token)
            $x = Get-ChannelForgeWebSignInResponse -Store $S.Store -Method GET -Path '/api/import-guides' -CookieHeader "cf_session=$Token" -ConfigRoot $S.Config
            $x.Body | ConvertFrom-Json
        } $s $t
        $r.Available | Should -BeFalse
        @($r.Guides).Count | Should -Be 0
    }

    It 'lets a viewer be refused' {
        $s = New-TestSetup
        (Get-Guides $s (Start-TestSession $s 'view')).StatusCode | Should -Be 403
    }
}

Describe 'Import handles' {
    It 'resolves a fresh handle to the file inside the root' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $h = (Get-Guides $s $t).Json.Guides | Where-Object Name -eq 'guide one.xml'
        Resolve-Handle $s $t $h.Handle | Should -Be (Join-Path ([IO.Path]::GetFullPath($s.Root)) 'guide one.xml')
    }

    It 'expires after 15 minutes, using the clock that is passed in' {
        $s = New-TestSetup
        $t0 = [datetime]::UtcNow
        $t = Start-TestSession $s 'boss' $t0
        $h = (Get-Guides $s $t $t0).Json.Guides[0].Handle
        Resolve-Handle $s $t $h $t0.AddMinutes(14) | Should -Not -BeNullOrEmpty
        # Past 15 minutes the handle is gone. Keep the session alive (idle limit is 30 minutes).
        Resolve-Handle $s $t $h $t0.AddMinutes(16) | Should -BeNullOrEmpty
        Resolve-Handle $s $t $h $t0.AddMinutes(17) | Should -BeNullOrEmpty
    }

    It 'rejects a handle from another session' {
        $s = New-TestSetup
        $a = Start-TestSession $s
        $b = Start-TestSession $s
        $h = (Get-Guides $s $a).Json.Guides[0].Handle
        Resolve-Handle $s $b $h | Should -BeNullOrEmpty
        Resolve-Handle $s $a $h | Should -Not -BeNullOrEmpty
    }

    It 'rejects the handle after sign-out' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $h = (Get-Guides $s $t).Json.Guides[0].Handle
        & (Get-Module ChannelForge) { param($S, $T) Remove-ChannelForgeWebSession -Store $S.Store -Token $T } $s $t
        Resolve-Handle $s $t $h | Should -BeNullOrEmpty
    }

    It 'rejects an unknown or empty handle' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $null = Get-Guides $s $t
        Resolve-Handle $s $t 'not-a-handle' | Should -BeNullOrEmpty
        Resolve-Handle $s $t '' | Should -BeNullOrEmpty
    }

    It 'rejects a file that was removed after listing' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $h = (Get-Guides $s $t).Json.Guides | Where-Object Name -eq 'guide one.xml'
        Remove-Item -LiteralPath (Join-Path $s.Root 'guide one.xml')
        Resolve-Handle $s $t $h.Handle | Should -BeNullOrEmpty
    }

    It 'rejects a file that was replaced by a link after listing' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $h = (Get-Guides $s $t).Json.Guides | Where-Object Name -eq 'guide one.xml'
        $outside = Join-Path $TestDrive ('outside-' + [guid]::NewGuid().ToString('N') + '.xml')
        Set-Content -LiteralPath $outside -Value '<tv/>'
        Remove-Item -LiteralPath (Join-Path $s.Root 'guide one.xml')
        try { New-Item -ItemType SymbolicLink -Path (Join-Path $s.Root 'guide one.xml') -Target $outside -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'this account cannot create symbolic links'; return }
        Resolve-Handle $s $t $h.Handle | Should -BeNullOrEmpty
    }

    It 'rejects names that try to leave the root' {
        $s = New-TestSetup
        $t = Start-TestSession $s
        $outside = Join-Path $TestDrive 'escape.xml'
        Set-Content -LiteralPath $outside -Value '<tv/>'
        foreach ($name in @('..\escape.xml', '../escape.xml', $outside, 'sub.xml\inner.xml', 'C:escape.xml')) {
            $handle = & (Get-Module ChannelForge) {
                param($S, $T, $Name)
                $session = Get-ChannelForgeWebSession -Store $S.Store -Token $T
                $session.Handles['forged'] = [pscustomobject]@{ FileName = $Name; ExpiresUtc = [datetime]::UtcNow.AddMinutes(5) }
                'forged'
            } $s $t $name
            Resolve-Handle $s $t $handle | Should -BeNullOrEmpty -Because "name '$name' must not resolve"
        }
    }
}
