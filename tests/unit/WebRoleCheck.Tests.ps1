BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Config | Out-Null
    $script:Password = 'test-password-one'

    # Writes users.json with one user per role name given (user name = role name) and returns the ids by name.
    function Set-TestUsers {
        param([hashtable]$Roles, [string[]]$Disabled = @())
        & (Get-Module ChannelForge) {
            param($Config, $Roles, $Disabled, $Password)
            $record = New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000
            $users = foreach ($name in $Roles.Keys) {
                $user = New-ChannelForgeUserRecord -Name $name -Role $Roles[$name] -PasswordRecord $record
                $user.Disabled = $name -in $Disabled
                $user
            }
            Write-ChannelForgeUserStore -ConfigRoot $Config -User @($users) | Out-Null
            $ids = @{}
            foreach ($user in $users) { $ids[$user.Name] = $user.Id }
            $ids
        } $script:Config $Roles $Disabled $script:Password
    }

    # Runs one request through the sign-in gate in process. Returns the response, or $null when the request may go on.
    function Invoke-TestGate {
        param([hashtable]$Store, [string]$UserId, [string]$Method, [string]$Path)
        & (Get-Module ChannelForge) {
            param($Config, $Store, $UserId, $Method, $Path)
            $token = New-ChannelForgeWebSession -Store $Store -UserId $UserId
            Get-ChannelForgeWebSignInResponse -Store $Store -Method $Method -Path $Path -CookieHeader "cf_session=$token" -ConfigRoot $Config
        } $script:Config $Store $UserId $Method $Path
    }

    $script:Routes = @(
        @{ Method = 'GET'; Path = '/api/status'; Role = 'viewer' }
        @{ Method = 'GET'; Path = '/api/lineup/channels?limit=5'; Role = 'viewer' }
        @{ Method = 'GET'; Path = '/api/one-guide/live-now'; Role = 'viewer' }
        @{ Method = 'GET'; Path = '/api/one-guide/category/sports'; Role = 'viewer' }
        @{ Method = 'GET'; Path = '/api/settings'; Role = 'viewer' }
        @{ Method = 'GET'; Path = '/'; Role = 'viewer' }
        @{ Method = 'POST'; Path = '/api/guided-setup/proposal'; Role = 'editor' }
        @{ Method = 'POST'; Path = '/api/guided-setup/accept'; Role = 'editor' }
        @{ Method = 'POST'; Path = '/api/sources/refresh'; Role = 'editor' }
        @{ Method = 'POST'; Path = '/api/sources/remove'; Role = 'editor' }
        @{ Method = 'PUT'; Path = '/api/settings'; Role = 'admin' }
    )
}

Describe 'Role check on every route' {
    It 'allows each role exactly the routes at or below its level' {
        $ids = Set-TestUsers @{ viewer = 'viewer'; editor = 'editor'; admin = 'admin' }
        $rank = @{ viewer = 1; editor = 2; admin = 3 }
        foreach ($route in $script:Routes) {
            foreach ($role in 'viewer', 'editor', 'admin') {
                $response = Invoke-TestGate -Store @{} -UserId $ids[$role] -Method $route.Method -Path $route.Path
                if ($rank[$role] -ge $rank[$route.Role]) { $response | Should -BeNullOrEmpty -Because "$role may use $($route.Method) $($route.Path)" }
                else { $response.StatusCode | Should -Be 403 -Because "$role may not use $($route.Method) $($route.Path)" }
            }
        }
    }

    It 'refuses a route that is not in the table, even for an admin' {
        $ids = Set-TestUsers @{ admin = 'admin' }
        foreach ($route in @(@('GET', '/api/users'), @('POST', '/api/brand-new-route'), @('DELETE', '/api/settings/me'), @('PATCH', '/api/status'))) {
            (Invoke-TestGate -Store @{} -UserId $ids['admin'] -Method $route[0] -Path $route[1]).StatusCode | Should -Be 403
        }
    }

    It 'gives the same 403 answer for every route and role, with no role words in it' {
        $ids = Set-TestUsers @{ viewer = 'viewer' }
        $bodies = foreach ($route in $script:Routes | Where-Object { $_.Role -ne 'viewer' }) {
            $response = Invoke-TestGate -Store @{} -UserId $ids['viewer'] -Method $route.Method -Path $route.Path
            $response.StatusCode | Should -Be 403
            $response.Body
        }
        @($bodies | Select-Object -Unique).Count | Should -Be 1
        ($bodies[0] | ConvertFrom-Json).Message | Should -Be 'Your account is not allowed to do that.'
        $bodies[0] | Should -Not -Match '(?i)viewer|editor|admin'
    }

    It 'takes a role change, a disable or a delete into effect on the next request, with the same session' {
        $ids = Set-TestUsers @{ helper = 'editor'; admin = 'admin' }
        $store = @{}
        $token = & (Get-Module ChannelForge) { param($Store, $Id) New-ChannelForgeWebSession -Store $Store -UserId $Id } $store $ids['helper']
        $ask = {
            param($Method, $Path)
            & (Get-Module ChannelForge) {
                param($Config, $Store, $Token, $Method, $Path)
                Get-ChannelForgeWebSignInResponse -Store $Store -Method $Method -Path $Path -CookieHeader "cf_session=$Token" -ConfigRoot $Config
            } $script:Config $store $token $Method $Path
        }
        # Changes the helper's record in place (same id), the way a later Users screen will.
        $change = {
            param($Role, $Disabled, $Remove)
            & (Get-Module ChannelForge) {
                param($Config, $Id, $Role, $Disabled, $Remove)
                $users = @((Read-ChannelForgeUserStore -ConfigRoot $Config).Users | Where-Object { -not ($Remove -and $_.Id -eq $Id) })
                foreach ($user in $users | Where-Object { $_.Id -eq $Id }) { $user.Role = $Role; $user.Disabled = $Disabled }
                Write-ChannelForgeUserStore -ConfigRoot $Config -User $users | Out-Null
            } $script:Config $ids['helper'] $Role $Disabled $Remove
        }
        & $ask 'POST' '/api/sources/refresh' | Should -BeNullOrEmpty
        & $change 'viewer' $false $false
        (& $ask 'POST' '/api/sources/refresh').StatusCode | Should -Be 403
        & $ask 'GET' '/api/status' | Should -BeNullOrEmpty
        & $change 'editor' $true $false
        $disabled = & $ask 'GET' '/api/status'
        $disabled.StatusCode | Should -Be 401
        ($disabled.Body | ConvertFrom-Json).Message | Should -Be 'Sign in is required.'
        $store.Count | Should -Be 0

        $token = & (Get-Module ChannelForge) { param($Store, $Id) New-ChannelForgeWebSession -Store $Store -UserId $Id } $store $ids['helper']
        & $change 'editor' $false $true
        (& $ask 'GET' '/api/status').StatusCode | Should -Be 401
    }
}

Describe 'Every route the server knows has a role row' {
    It 'finds each route path written in the router and the server loop in the role table' {
        $paths = foreach ($file in 'Private\Get-ChannelForgeWebResponse.ps1', 'Public\Start-ChannelForgeWebServer.ps1') {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot "src\ChannelForge\$file"), [ref]$tokens, [ref]$errors)
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '^/(health|api/)' }, $true) | ForEach-Object { $_.Value }
        }
        $paths = @($paths | Select-Object -Unique)
        $paths.Count | Should -BeGreaterThan 5
        $missing = & (Get-Module ChannelForge) {
            param($Paths)
            $Paths | Where-Object { $path = $_; -not (@('GET', 'POST', 'PUT') | Where-Object { $null -ne (Get-ChannelForgeWebRouteMinimumRole -Method $_ -Path $path) }) }
        } $paths
        @($missing) | Should -BeNullOrEmpty
    }

    It 'finds the guide routes written as a pattern in the router' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeWebResponse.ps1')
        $text | Should -Match ([regex]::Escape('live-now|starting-soon|category/([^/]+)|items/([^/]+)'))
        $samples = '/api/one-guide/live-now', '/api/one-guide/starting-soon', '/api/one-guide/category/x', ('/api/one-guide/items/' + ('a' * 64))
        $missing = & (Get-Module ChannelForge) { param($Samples) $Samples | Where-Object { $null -eq (Get-ChannelForgeWebRouteMinimumRole -Method GET -Path $_) } } $samples
        @($missing) | Should -BeNullOrEmpty
    }
}

Describe 'Sign-in off and sign-in on over a real server' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'root'
        New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
        $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-role-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
        $script:Servers = @()
        $script:OnPort = 18927
        $script:OffPort = 18928
        $script:Ids = Set-TestUsers @{ viewer = 'viewer'; admin = 'admin' }
        foreach ($case in @(@($script:OnPort, " -RequireSignIn -ConfigRoot '$script:Config'"), @($script:OffPort, ''))) {
            $launcher = Join-Path $script:Root "server-$($case[0]).ps1"
            @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $($case[0]) -RepositoryRoot '$script:Root'$($case[1])") | Set-Content -LiteralPath $launcher
            $log = Join-Path $script:LogDir "$($case[0]).log"
            $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
            $script:Servers += $process
            for ($attempt = 0; $attempt -lt 100; $attempt++) {
                if ($process.HasExited) { break }
                $tcp = [Net.Sockets.TcpClient]::new()
                try { $tcp.Connect('127.0.0.1', $case[0]); break } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
            }
        }

        function Send-TestRequest {
            param([int]$Port, [string]$Path, [string]$Method = 'GET', [string]$Cookie = '')
            $headers = @{}
            if ($Method -ne 'GET') { $headers['Origin'] = "http://127.0.0.1:$Port" }
            if ($Cookie) { $headers['Cookie'] = $Cookie }
            $arguments = @{ Uri = "http://127.0.0.1:$Port$Path"; Method = $Method; Headers = $headers; SkipHttpErrorCheck = $true }
            if ($Method -ne 'GET') { $arguments.Body = '{}'; $arguments.ContentType = 'application/json' }
            Invoke-WebRequest @arguments
        }
    }

    AfterAll {
        foreach ($server in $script:Servers) {
            if (-not $server.HasExited) { $server.Kill() }
            $server.WaitForExit(10000) | Out-Null
            $server.Dispose()
        }
        Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'lets a viewer read but refuses changes, and an admin through' {
        $signIn = Send-TestRequest -Port $script:OnPort -Path '/api/auth/sign-in' -Method POST -Cookie ''
        $signIn.StatusCode | Should -Be 401
        $cookies = foreach ($name in 'viewer', 'admin') {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:OnPort)/api/auth/sign-in" -Method POST -Headers @{ Origin = "http://127.0.0.1:$($script:OnPort)" } -Body (@{ name = $name; password = $script:Password } | ConvertTo-Json -Compress) -ContentType 'application/json' -SkipHttpErrorCheck
            $response.StatusCode | Should -Be 200
            (@($response.Headers['Set-Cookie'])[0] -split ';')[0]
        }
        (Send-TestRequest -Port $script:OnPort -Path '/api/status' -Cookie $cookies[0]).StatusCode | Should -Be 200
        $denied = Send-TestRequest -Port $script:OnPort -Path '/api/sources/refresh' -Method POST -Cookie $cookies[0]
        $denied.StatusCode | Should -Be 403
        ($denied.Content | ConvertFrom-Json).Message | Should -Be 'Your account is not allowed to do that.'
        (Send-TestRequest -Port $script:OnPort -Path '/api/sources/refresh' -Method POST -Cookie $cookies[1]).StatusCode | Should -Not -Be 403
        (Send-TestRequest -Port $script:OnPort -Path '/api/brand-new-route' -Cookie $cookies[1]).StatusCode | Should -Be 403
    }

    It 'does no role check when sign-in is off' {
        (Send-TestRequest -Port $script:OffPort -Path '/api/sources/refresh' -Method POST).StatusCode | Should -Not -BeIn 401, 403
        (Send-TestRequest -Port $script:OffPort -Path '/api/brand-new-route').StatusCode | Should -Be 404
    }
}
