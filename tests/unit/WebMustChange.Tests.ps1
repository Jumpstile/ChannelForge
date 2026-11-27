BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Port = 18934
    $script:Probe = 'test-password-one'
    $script:Chosen = 'test-password-chosen-two'
    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-mustchange-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null

    # users.json with a normal admin, and an editor and a viewer who both start on a temporary password.
    $script:Ids = & (Get-Module ChannelForge) {
        param($Config, $Probe)
        $record = New-ChannelForgeAdminPasswordRecord -Password $Probe -Iterations 1000
        $users = @(
            (New-ChannelForgeUserRecord -Name 'boss' -Role 'admin' -PasswordRecord $record)
            (New-ChannelForgeUserRecord -Name 'temp1' -Role 'editor' -PasswordRecord $record -MustChange $true)
            (New-ChannelForgeUserRecord -Name 'temp2' -Role 'viewer' -PasswordRecord $record -MustChange $true)
        )
        Write-ChannelForgeUserStore -ConfigRoot $Config -User $users | Out-Null
        $ids = @{}
        foreach ($user in $users) { $ids[$user.Name] = $user.Id }
        $ids
    } $script:Config $script:Probe

    $launcher = Join-Path $script:Root 'server.ps1'
    @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $script:Port -RepositoryRoot '$script:Root' -RequireSignIn -ConfigRoot '$script:Config'") | Set-Content -LiteralPath $launcher
    $script:Process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput (Join-Path $script:LogDir 'out.log') -RedirectStandardError (Join-Path $script:LogDir 'err.log')
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        if ($script:Process.HasExited) { break }
        $tcp = [Net.Sockets.TcpClient]::new()
        try { $tcp.Connect('127.0.0.1', $script:Port); break } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
    }

    function Invoke-TestCall {
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body = $null, [string]$Cookie = '')
        $headers = @{ Origin = "http://127.0.0.1:$script:Port" }
        if ($Cookie) { $headers.Cookie = $Cookie }
        $arguments = @{ Uri = "http://127.0.0.1:$($script:Port)$Path"; Method = $Method; Headers = $headers; SkipHttpErrorCheck = $true }
        if ($null -ne $Body) { $arguments.Body = $Body | ConvertTo-Json -Compress; $arguments.ContentType = 'application/json' }
        Invoke-WebRequest @arguments
    }

    function Start-TestSession {
        param([string]$Name, [string]$Password)
        $r = Invoke-TestCall -Method POST -Path '/api/auth/sign-in' -Body @{ name = $Name; password = $Password }
        [pscustomobject]@{ Status = $r.StatusCode; Json = ($r.Content | ConvertFrom-Json); Cookie = (@($r.Headers['Set-Cookie'])[0] -split ';')[0] }
    }

    function Set-TestMustChange {
        # Flips the flag on the stored record only; the password and the session stay as they are.
        param([string]$Id, [bool]$Value)
        & (Get-Module ChannelForge) {
            param($Config, $Id, $Value)
            $users = @((Read-ChannelForgeUserStore -ConfigRoot $Config).Users)
            foreach ($user in $users | Where-Object { $_.Id -ceq $Id }) { $user.MustChange = $Value }
            Write-ChannelForgeUserStore -ConfigRoot $Config -User $users | Out-Null
        } $script:Config $Id $Value
    }
}

AfterAll {
    if ($null -ne $script:Process) {
        if (-not $script:Process.HasExited) { $script:Process.Kill($true) }
        $script:Process.WaitForExit(10000) | Out-Null
        $script:Process.Dispose()
        foreach ($log in 'out.log', 'err.log') {
            $path = Join-Path $script:LogDir $log
            for ($try = 0; $try -lt 50 -and (Test-Path -LiteralPath $path); $try++) {
                try { [IO.File]::Open($path, 'Open', 'ReadWrite', 'None').Dispose(); break } catch { Start-Sleep -Milliseconds 100 }
            }
        }
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'A temporary password only chooses a new password' {
    It 'tells the page at sign-in, refuses normal routes with a stable code, and still answers the session read' {
        $session = Start-TestSession -Name 'temp1' -Password $script:Probe
        $session.Status | Should -Be 200
        $session.Json.MustChange | Should -BeTrue
        $refused = Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie
        $refused.StatusCode | Should -Be 403
        $body = $refused.Content | ConvertFrom-Json
        $body.Code | Should -Be 'must-change-password'
        $body.Message | Should -Match 'new password'
        (Invoke-TestCall -Path '/api/settings/me' -Cookie $session.Cookie).StatusCode | Should -Be 403
        $state = Invoke-TestCall -Path '/api/auth/session' -Cookie $session.Cookie
        $state.StatusCode | Should -Be 200
        ($state.Content | ConvertFrom-Json).MustChange | Should -BeTrue
    }

    It 'refuses the same password, then a new one clears the flag and normal routes work' {
        $session = Start-TestSession -Name 'temp1' -Password $script:Probe
        $same = Invoke-TestCall -Method POST -Path '/api/auth/change-password' -Cookie $session.Cookie -Body @{ currentPassword = $script:Probe; newPassword = $script:Probe }
        $same.StatusCode | Should -Be 400
        $same.Content | Should -Not -Match 'test-password'
        (Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie).StatusCode | Should -Be 403
        (Invoke-TestCall -Method POST -Path '/api/auth/change-password' -Cookie $session.Cookie -Body @{ currentPassword = $script:Probe; newPassword = $script:Chosen }).StatusCode | Should -Be 200
        $state = (Invoke-TestCall -Path '/api/auth/session' -Cookie $session.Cookie).Content | ConvertFrom-Json
        $state.SignedIn | Should -BeTrue
        $state.MustChange | Should -BeFalse
        (Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie).StatusCode | Should -Be 200
        $again = Start-TestSession -Name 'temp1' -Password $script:Chosen
        $again.Json.MustChange | Should -BeFalse
    }

    It 'lets a temporary-password user sign out' {
        $session = Start-TestSession -Name 'temp2' -Password $script:Probe
        (Invoke-TestCall -Method POST -Path '/api/auth/sign-out' -Cookie $session.Cookie -Body @{}).StatusCode | Should -Be 200
        (Invoke-TestCall -Path '/api/auth/session' -Cookie $session.Cookie).Content | ConvertFrom-Json | Select-Object -ExpandProperty SignedIn | Should -BeFalse
    }

    It 'takes a reset into effect on a live session at once, and leaves normal users alone before it' {
        $session = Start-TestSession -Name 'boss' -Password $script:Probe
        $session.Json.MustChange | Should -BeFalse
        (Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie).StatusCode | Should -Be 200
        Set-TestMustChange -Id $script:Ids['boss'] -Value $true
        (Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie).StatusCode | Should -Be 403
        (Invoke-TestCall -Path '/api/users' -Cookie $session.Cookie).StatusCode | Should -Be 403
        Set-TestMustChange -Id $script:Ids['boss'] -Value $false
        (Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie).StatusCode | Should -Be 200
    }

    It 'still serves the page shell so a reload shows the Change password form' {
        $session = Start-TestSession -Name 'temp2' -Password $script:Probe
        (Invoke-TestCall -Path '/' -Cookie $session.Cookie).StatusCode | Should -Be 200
    }

    It 'does not write the refusal to the audit log' {
        $session = Start-TestSession -Name 'temp2' -Password $script:Probe
        1..3 | ForEach-Object { Invoke-TestCall -Path '/api/status' -Cookie $session.Cookie | Out-Null }
        $audit = Get-ChildItem -LiteralPath $script:Config -Filter 'audit*' -Recurse -File | Get-Content -Raw
        $audit | Should -Match 'sign-in'
        $audit | Should -Not -Match 'role-check'
    }
}

Describe 'Users that never had a temporary password' {
    It 'keeps MustChange false for an upgraded admin-password.json' {
        $config = Join-Path $TestDrive 'upgrade'
        New-Item -ItemType Directory -Force -Path $config | Out-Null
        $user = & (Get-Module ChannelForge) {
            param($Config, $Probe)
            Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Probe -Iterations 1000) | Out-Null
            @((Read-ChannelForgeUserStore -ConfigRoot $Config).Users)[0]
        } $config $script:Probe
        $user.Name | Should -Be 'admin'
        $user.MustChange | Should -BeFalse
    }
}
