BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Port = 18929
    $script:Base = "http://127.0.0.1:$($script:Port)"
    $script:Password = 'real-server-pass-1'
    $script:Temp = 'temporary-pass-123'
    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null

    & (Get-Module ChannelForge) {
        param($Config, $Password)
        $record = New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000
        Write-ChannelForgeUserStore -ConfigRoot $Config -User @(New-ChannelForgeUserRecord -Name 'boss' -Role 'admin' -PasswordRecord $record) | Out-Null
    } $script:Config $script:Password

    # One real HTTP call. Returns StatusCode, parsed Json and the session cookie when one is set.
    function Invoke-Call {
        param([string]$Method = 'GET', [string]$Path, $Body = $null, [string]$Cookie = '')
        $headers = @{ Origin = $script:Base }
        if ($Cookie) { $headers.Cookie = $Cookie }
        $p = @{ Uri = "$($script:Base)$Path"; Method = $Method; Headers = $headers; SkipHttpErrorCheck = $true }
        if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Compress); $p.ContentType = 'application/json' }
        $r = Invoke-WebRequest @p
        $setCookie = @($r.Headers['Set-Cookie'])[0]
        [pscustomobject]@{
            StatusCode = [int]$r.StatusCode
            Json       = $(if ($r.Content) { $r.Content | ConvertFrom-Json } else { $null })
            Cookie     = $(if ($setCookie) { ($setCookie -split ';')[0] } else { '' })
        }
    }

    function Connect-TestUser {
        param([string]$Name, [string]$Password)
        $r = Invoke-Call -Method POST -Path '/api/auth/sign-in' -Body @{ name = $Name; password = $Password }
        $r.StatusCode | Should -Be 200
        $r.Cookie
    }

    $launcher = Join-Path $script:Root 'server.ps1'
    @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $($script:Port) -RepositoryRoot '$($script:Root)' -RequireSignIn -ConfigRoot '$($script:Config)'") | Set-Content -LiteralPath $launcher
    $script:Process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput (Join-Path $script:Root 'out.log') -RedirectStandardError (Join-Path $script:Root 'err.log')
    $ready = $false
    for ($attempt = 0; $attempt -lt 100 -and -not $ready; $attempt++) {
        if ($script:Process.HasExited) { break }
        $tcp = [Net.Sockets.TcpClient]::new()
        try { $tcp.Connect('127.0.0.1', $script:Port); $ready = $true } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
    }
    if (-not $ready) { throw 'Test server did not start.' }
}

AfterAll {
    if ($null -ne $script:Process) {
        if (-not $script:Process.HasExited) { $script:Process.Kill($true) }
        $script:Process.WaitForExit(10000) | Out-Null
        $script:Process.Dispose()
        # Windows can hold the log files for a moment after the process ends; wait until they open.
        foreach ($log in 'out.log', 'err.log') {
            $path = Join-Path $script:Root $log
            for ($try = 0; $try -lt 50 -and (Test-Path -LiteralPath $path); $try++) {
                try { [IO.File]::Open($path, 'Open', 'ReadWrite', 'None').Dispose(); break } catch { Start-Sleep -Milliseconds 100 }
            }
        }
    }
}

Describe 'Users API over a real server' {
    It 'lists, adds, changes the role, resets, deletes, and refuses to remove the last Admin' {
        $admin = Connect-TestUser 'boss' $script:Password
        $bossId = (Invoke-Call -Path '/api/users' -Cookie $admin).Json.Users[0].Id

        $add = Invoke-Call -Method POST -Path '/api/users' -Cookie $admin -Body @{ adminPassword = $script:Password; name = 'Maria'; role = 'viewer'; temporaryPassword = $script:Temp }
        $add.StatusCode | Should -Be 201
        $id = $add.Json.User.Id
        @((Invoke-Call -Path '/api/users' -Cookie $admin).Json.Users).Count | Should -Be 2

        $put = Invoke-Call -Method PUT -Path "/api/users/$id" -Cookie $admin -Body @{ role = 'editor' }
        $put.StatusCode | Should -Be 200
        $put.Json.User.Role | Should -Be 'editor'

        (Invoke-Call -Method POST -Path "/api/users/$id/reset-password" -Cookie $admin -Body @{ adminPassword = $script:Password; temporaryPassword = 'another-temporary-1' }).StatusCode | Should -Be 200
        (Invoke-Call -Method DELETE -Path "/api/users/$id" -Cookie $admin -Body @{ adminPassword = $script:Password }).StatusCode | Should -Be 200
        @((Invoke-Call -Path '/api/users' -Cookie $admin).Json.Users).Count | Should -Be 1

        $last = Invoke-Call -Method DELETE -Path "/api/users/$bossId" -Cookie $admin -Body @{ adminPassword = $script:Password }
        $last.StatusCode | Should -Be 409
        $last.Json.Message | Should -Be 'There must always be at least one active Admin.'
    }

    It 'signs a user out when an Admin resets their password' {
        $admin = Connect-TestUser 'boss' $script:Password
        $id = (Invoke-Call -Method POST -Path '/api/users' -Cookie $admin -Body @{ adminPassword = $script:Password; name = 'Ben'; role = 'viewer'; temporaryPassword = $script:Temp }).Json.User.Id
        $ben = Connect-TestUser 'Ben' $script:Temp
        (Invoke-Call -Path '/api/auth/session' -Cookie $ben).Json.SignedIn | Should -BeTrue

        (Invoke-Call -Method POST -Path "/api/users/$id/reset-password" -Cookie $admin -Body @{ adminPassword = $script:Password; temporaryPassword = 'another-temporary-1' }).StatusCode | Should -Be 200

        (Invoke-Call -Path '/api/status' -Cookie $ben).StatusCode | Should -Be 401
        (Invoke-Call -Path '/api/auth/session' -Cookie $ben).Json.SignedIn | Should -BeFalse
        (Invoke-Call -Path '/api/users' -Cookie $admin).StatusCode | Should -Be 200
    }

    It 'keeps the session that changed its own password and ends the user''s other sessions' {
        $admin = Connect-TestUser 'boss' $script:Password
        (Invoke-Call -Method POST -Path '/api/users' -Cookie $admin -Body @{ adminPassword = $script:Password; name = 'Cleo'; role = 'viewer'; temporaryPassword = $script:Temp }).StatusCode | Should -Be 201
        $first = Connect-TestUser 'Cleo' $script:Temp
        $second = Connect-TestUser 'Cleo' $script:Temp

        (Invoke-Call -Method POST -Path '/api/auth/change-password' -Cookie $first -Body @{ currentPassword = $script:Temp; newPassword = 'cleo-new-pass-77' }).StatusCode | Should -Be 200

        (Invoke-Call -Path '/api/auth/session' -Cookie $first).Json.SignedIn | Should -BeTrue
        (Invoke-Call -Path '/api/auth/session' -Cookie $second).Json.SignedIn | Should -BeFalse
        (Invoke-Call -Path '/api/users' -Cookie $admin).StatusCode | Should -Be 200
        (Invoke-Call -Method POST -Path '/api/auth/sign-in' -Body @{ name = 'boss'; password = $script:Password }).StatusCode | Should -Be 200
    }
}
