BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Password = 'test-password-one'
    $script:Temp = 'temporary-pass-123'

    # Writes a fresh users.json (all with $script:Password) in a new config folder. Returns the folder and the ids by name.
    function New-TestConfig {
        param([object[]]$Spec)
        $config = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $config | Out-Null
        $ids = & (Get-Module ChannelForge) {
            param($Config, $Spec, $Password)
            $record = New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000
            $users = foreach ($item in $Spec) {
                $user = New-ChannelForgeUserRecord -Name $item.Name -Role $item.Role -PasswordRecord $record
                $user.Disabled = [bool]$item.Disabled
                $user
            }
            Write-ChannelForgeUserStore -ConfigRoot $Config -User @($users) | Out-Null
            $ids = @{}
            foreach ($user in $users) { $ids[$user.Name] = $user.Id }
            $ids
        } $config $Spec $script:Password
        [pscustomobject]@{ Config = $config; Ids = $ids }
    }

    function Read-TestUsers { param($Config) @((& (Get-Module ChannelForge) { param($c) (Read-ChannelForgeUserStore -ConfigRoot $c).Users } $Config)) }

    # One request through the sign-in gate in process, as the given user. Returns StatusCode, parsed Json and Raw text.
    function Invoke-Api {
        param($Setup, [string]$As, [string]$Method, [string]$Path, $Body = $null, [hashtable]$Store = @{}, [hashtable]$Limiter = $null)
        $result = & (Get-Module ChannelForge) {
            param($Config, $UserId, $Method, $Path, $Json, $Store, $Limiter)
            $token = New-ChannelForgeWebSession -Store $Store -UserId $UserId
            $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Json))
            $response = Get-ChannelForgeWebSignInResponse -Store $Store -Method $Method -Path $Path -CookieHeader "cf_session=$token" -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config -Limiter $Limiter
            [pscustomobject]@{ StatusCode = $response.StatusCode; Raw = [string]$response.Body }
        } $Setup.Config $Setup.Ids[$As] $Method $Path $(if ($null -eq $Body) { '' } else { $Body | ConvertTo-Json -Compress }) $Store $Limiter
        $json = if ($result.Raw) { $result.Raw | ConvertFrom-Json } else { $null }
        [pscustomobject]@{ StatusCode = $result.StatusCode; Json = $json; Raw = $result.Raw }
    }
}

Describe 'Users API: happy paths' {
    It 'adds, lists, updates, resets and deletes a user, and never returns a password record' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' })
        $add = Invoke-Api $s 'boss' 'POST' '/api/users' @{ adminPassword = $script:Password; name = 'Maria'; role = 'viewer'; temporaryPassword = $script:Temp }
        $add.StatusCode | Should -Be 201
        $add.Json.User.MustChange | Should -BeTrue
        $id = $add.Json.User.Id

        $list = Invoke-Api $s 'boss' 'GET' '/api/users'
        $list.StatusCode | Should -Be 200
        @($list.Json.Users).Count | Should -Be 2
        $maria = @($list.Json.Users | Where-Object Name -eq 'Maria')[0]
        ($maria.PSObject.Properties.Name -join ',') | Should -Be 'Id,Name,Role,MustChange,Disabled,CreatedUtc,PasswordChangedUtc'

        $put = Invoke-Api $s 'boss' 'PUT' "/api/users/$id" @{ name = 'Maria2'; role = 'editor'; disabled = $true }
        $put.StatusCode | Should -Be 200
        $put.Json.User.Name | Should -Be 'Maria2'
        $put.Json.User.Role | Should -Be 'editor'
        $put.Json.User.Disabled | Should -BeTrue

        $before = (Read-TestUsers $s.Config | Where-Object Id -eq $id).Password.Hash
        Start-Sleep -Seconds 1
        $reset = Invoke-Api $s 'boss' 'POST' "/api/users/$id/reset-password" @{ adminPassword = $script:Password; temporaryPassword = 'another-temporary-1' }
        $reset.StatusCode | Should -Be 200
        $after = Read-TestUsers $s.Config | Where-Object Id -eq $id
        $after.Password.Hash | Should -Not -Be $before
        $after.MustChange | Should -BeTrue
        $after.PasswordChangedUtc | Should -Not -Be $after.CreatedUtc

        foreach ($response in $add, $list, $put, $reset) { $response.Raw | Should -Not -Match 'Hash|Salt|Iterations|temporary-pass|another-temporary|test-password-one' }

        (Invoke-Api $s 'boss' 'DELETE' "/api/users/$id" @{ adminPassword = $script:Password }).StatusCode | Should -Be 200
        @(Read-TestUsers $s.Config).Count | Should -Be 1
    }

    It 'refuses a bad name, a taken name (any case), a bad role and a weak temporary password' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' })
        $good = @{ adminPassword = $script:Password; name = 'Maria'; role = 'viewer'; temporaryPassword = $script:Temp }
        foreach ($change in @{ name = 'ab' }, @{ name = 'BOSS' }, @{ name = 'has space' }, @{ role = 'owner' }, @{ temporaryPassword = 'short' }) {
            $body = $good.Clone()
            foreach ($key in $change.Keys) { $body[$key] = $change[$key] }
            (Invoke-Api $s 'boss' 'POST' '/api/users' $body).StatusCode | Should -Be 400
        }
        @(Read-TestUsers $s.Config).Count | Should -Be 1
    }

    It 'reads a schema 1 record without PasswordChangedUtc as changed when created' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' })
        $path = Join-Path $s.Config 'users.json'
        $doc = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -DateKind String
        $doc.Users[0].PSObject.Properties.Remove('PasswordChangedUtc')
        [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 5))
        $user = (Read-TestUsers $s.Config)[0]
        $user.Name | Should -Be 'boss'
        $user.PasswordChangedUtc | Should -Be $user.CreatedUtc
    }
}

Describe 'Users API: last active Admin' {
    It 'refuses delete, disable and demote of the last enabled Admin with 409 and changes nothing' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' }, @{ Name = 'off'; Role = 'admin'; Disabled = $true }, @{ Name = 'eddie'; Role = 'editor' })
        $id = $s.Ids['boss']
        $before = Get-Content -Raw -LiteralPath (Join-Path $s.Config 'users.json')
        $attempts = @(
            @{ Method = 'DELETE'; Body = @{ adminPassword = $script:Password } }
            @{ Method = 'PUT'; Body = @{ disabled = $true } }
            @{ Method = 'PUT'; Body = @{ role = 'editor' } }
        )
        foreach ($attempt in $attempts) {
            $response = Invoke-Api $s 'boss' $attempt.Method "/api/users/$id" $attempt.Body
            $response.StatusCode | Should -Be 409
            $response.Json.Message | Should -Be 'There must always be at least one active Admin.'
        }
        Get-Content -Raw -LiteralPath (Join-Path $s.Config 'users.json') | Should -Be $before
    }

    It 'lets an Admin go once another enabled Admin exists' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' }, @{ Name = 'second'; Role = 'admin' })
        (Invoke-Api $s 'boss' 'PUT' "/api/users/$($s.Ids['second'])" @{ role = 'viewer' }).StatusCode | Should -Be 200
        (Invoke-Api $s 'boss' 'DELETE' "/api/users/$($s.Ids['boss'])" @{ adminPassword = $script:Password }).StatusCode | Should -Be 409
    }

    It 'lets only one of two Admins remove the other when both ask at once' {
        $s = New-TestConfig @(@{ Name = 'aaa'; Role = 'admin' }, @{ Name = 'bbb'; Role = 'admin' })
        $codes = 1..4 | ForEach-Object -ThrottleLimit 2 -Parallel {
            $setup = $using:s
            Import-Module $using:ModulePath -Force
            $pair = if ($_ % 2) { @('aaa', 'bbb') } else { @('bbb', 'aaa') }
            & (Get-Module ChannelForge) {
                param($Config, $Actor, $Target, $Password)
                $store = @{}
                $token = New-ChannelForgeWebSession -Store $store -UserId $Actor
                $json = @{ adminPassword = $Password } | ConvertTo-Json -Compress
                $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($json))
                (Get-ChannelForgeWebSignInResponse -Store $store -Method 'DELETE' -Path "/api/users/$Target" -CookieHeader "cf_session=$token" -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config).StatusCode
            } $setup.Config $setup.Ids[$pair[0]] $setup.Ids[$pair[1]] $using:Password
        }
        @($codes | Where-Object { $_ -eq 200 }).Count | Should -Be 1
        $left = @(Read-TestUsers $s.Config)
        $left.Count | Should -Be 1
        $left[0].Role | Should -Be 'admin'
    }
}

Describe 'Users API: the Admin must retype their own password' {
    It 'refuses a wrong or missing adminPassword with one uniform 403 and changes nothing' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' }, @{ Name = 'eddie'; Role = 'editor' })
        $before = Get-Content -Raw -LiteralPath (Join-Path $s.Config 'users.json')
        $eddie = $s.Ids['eddie']
        $calls = @(
            @{ Method = 'POST'; Path = '/api/users'; Body = @{ name = 'Maria'; role = 'viewer'; temporaryPassword = $script:Temp } }
            @{ Method = 'POST'; Path = '/api/users'; Body = @{ adminPassword = 'wrong-password-here'; name = 'Maria'; role = 'viewer'; temporaryPassword = $script:Temp } }
            @{ Method = 'DELETE'; Path = "/api/users/$eddie"; Body = @{ adminPassword = 'wrong-password-here' } }
            @{ Method = 'POST'; Path = "/api/users/$eddie/reset-password"; Body = @{ adminPassword = 123; temporaryPassword = $script:Temp } }
        )
        $raws = foreach ($call in $calls) {
            $response = Invoke-Api $s 'boss' $call.Method $call.Path $call.Body
            $response.StatusCode | Should -Be 403
            $response.Raw
        }
        @($raws | Select-Object -Unique).Count | Should -Be 1
        $raws[0] | Should -Not -Match 'wrong-password-here|temporary-pass'
        Get-Content -Raw -LiteralPath (Join-Path $s.Config 'users.json') | Should -Be $before
    }

    It 'counts wrong tries in the sign-in limiter and answers 429 once it makes the address wait' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' })
        $limiter = & (Get-Module ChannelForge) { New-ChannelForgeSignInLimiter }
        1..5 | ForEach-Object { (Invoke-Api $s 'boss' 'POST' '/api/users' @{ adminPassword = 'wrong-password-here' } -Limiter $limiter).StatusCode | Should -Be 403 }
        $limiter.GlobalFailures | Should -Be 5
        (Invoke-Api $s 'boss' 'POST' '/api/users' @{ adminPassword = $script:Password; name = 'Maria'; role = 'viewer'; temporaryPassword = $script:Temp } -Limiter $limiter).StatusCode | Should -Be 429
        @(Read-TestUsers $s.Config).Count | Should -Be 1
    }
}

Describe 'Users API: who may use it' {
    It 'gives Viewer and Editor 403 on every Users route, and the data stays unchanged' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' }, @{ Name = 'vera'; Role = 'viewer' }, @{ Name = 'eddie'; Role = 'editor' })
        $before = Get-Content -Raw -LiteralPath (Join-Path $s.Config 'users.json')
        $id = $s.Ids['vera']
        $routes = @(
            @{ Method = 'GET'; Path = '/api/users' }
            @{ Method = 'POST'; Path = '/api/users' }
            @{ Method = 'PUT'; Path = "/api/users/$id" }
            @{ Method = 'POST'; Path = "/api/users/$id/reset-password" }
            @{ Method = 'DELETE'; Path = "/api/users/$id" }
        )
        foreach ($who in 'vera', 'eddie') {
            foreach ($route in $routes) {
                $body = @{ adminPassword = $script:Password; name = 'Maria'; role = 'admin'; temporaryPassword = $script:Temp; disabled = $true }
                (Invoke-Api $s $who $route.Method $route.Path $body).StatusCode | Should -Be 403
            }
        }
        Get-Content -Raw -LiteralPath (Join-Path $s.Config 'users.json') | Should -Be $before
    }
}

Describe 'Users API: sessions of disabled and deleted users' {
    It 'ends a session on the next request after the user is disabled or deleted' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin' }, @{ Name = 'one'; Role = 'viewer' }, @{ Name = 'two'; Role = 'viewer' })
        $store = @{}
        $state = { param($Config, $Store, $Token) (Get-ChannelForgeWebSignInResponse -Store $Store -Method 'GET' -Path '/api/auth/session' -CookieHeader "cf_session=$Token" -ConfigRoot $Config).Body }
        foreach ($name in 'one', 'two') {
            $token = & (Get-Module ChannelForge) { param($s, $u) New-ChannelForgeWebSession -Store $s -UserId $u } $store $s.Ids[$name]
            (& (Get-Module ChannelForge) $state $s.Config $store $token | ConvertFrom-Json).SignedIn | Should -BeTrue
            if ($name -eq 'one') { (Invoke-Api $s 'boss' 'PUT' "/api/users/$($s.Ids[$name])" @{ disabled = $true }).StatusCode | Should -Be 200 }
            else { (Invoke-Api $s 'boss' 'DELETE' "/api/users/$($s.Ids[$name])" @{ adminPassword = $script:Password }).StatusCode | Should -Be 200 }
            (& (Get-Module ChannelForge) $state $s.Config $store $token | ConvertFrom-Json).SignedIn | Should -BeFalse
        }
    }
}
