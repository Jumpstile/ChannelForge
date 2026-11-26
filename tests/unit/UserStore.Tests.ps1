BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Password = 'test-password-one'
    $script:Other = 'test-password-two'

    function New-ConfigWithOldFile {
        param([string]$Password = $script:Password)
        $config = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $config | Out-Null
        & (Get-Module ChannelForge) {
            param($Config, $Password)
            Write-ChannelForgeAdminPasswordFile -ConfigRoot $Config -Record (New-ChannelForgeAdminPasswordRecord -Password $Password -Iterations 1000) | Out-Null
        } $config $Password
        $config
    }
    function Read-Store { param($Config) & (Get-Module ChannelForge) { param($c) Read-ChannelForgeUserStore -ConfigRoot $c } $Config }
    function Test-Pw {
        param($Config, $Password)
        & (Get-Module ChannelForge) { param($c, $p) Test-ChannelForgeAdminPassword -Password $p -Record (Get-ChannelForgeSignInUser -ConfigRoot $c).Password } $Config $Password
    }
}

Describe 'Upgrade from admin-password.json' {
    It 'keeps the same password working, keeps the old file as .migrated, and keeps one stable admin' {
        $config = New-ConfigWithOldFile
        $old = Join-Path $config 'admin-password.json'
        $before = (Get-FileHash -LiteralPath $old).Hash
        $first = Read-Store $config
        $first.Status | Should -Be 'Ok'
        @($first.Users).Count | Should -Be 1
        $first.Users[0].Name | Should -Be 'admin'
        $first.Users[0].Role | Should -Be 'admin'
        Test-Pw $config $script:Password | Should -BeTrue
        Test-Pw $config $script:Other | Should -BeFalse
        Test-Path -LiteralPath $old | Should -BeFalse
        (Get-FileHash -LiteralPath "$old.migrated").Hash | Should -Be $before
        (Read-Store $config).Users[0].Id | Should -Be $first.Users[0].Id
        $text = Get-Content -Raw -LiteralPath (Join-Path $config 'users.json')
        $text | Should -Not -Match ([regex]::Escape($script:Password))
    }

    It 'lets users.json win and leaves the old file alone when both exist' {
        $config = New-ConfigWithOldFile
        Read-Store $config | Out-Null
        $other = New-ConfigWithOldFile -Password $script:Other
        Copy-Item -LiteralPath (Join-Path $other 'admin-password.json') -Destination (Join-Path $config 'admin-password.json')
        $old = Join-Path $config 'admin-password.json'
        $before = (Get-FileHash -LiteralPath $old).Hash
        Test-Pw $config $script:Password | Should -BeTrue
        Test-Pw $config $script:Other | Should -BeFalse
        (Get-FileHash -LiteralPath $old).Hash | Should -Be $before
    }

    It 'refuses a damaged old file and never changes it' {
        $config = Join-Path $TestDrive 'bad-old'
        New-Item -ItemType Directory -Path $config | Out-Null
        $old = Join-Path $config 'admin-password.json'
        Set-Content -LiteralPath $old -Value '{ broken'
        $before = (Get-FileHash -LiteralPath $old).Hash
        (Read-Store $config).Status | Should -Be 'Corrupt'
        (Get-FileHash -LiteralPath $old).Hash | Should -Be $before
        Test-Path -LiteralPath (Join-Path $config 'users.json') | Should -BeFalse
    }
}

Describe 'A damaged users.json' {
    BeforeAll {
        $script:GoodText = { param($Config) Get-Content -Raw -LiteralPath (Join-Path $Config 'users.json') }
        function New-GoodUsersConfig {
            $config = New-ConfigWithOldFile
            Read-Store $config | Out-Null
            $config
        }
    }

    It 'refuses to start, says so plainly, and stays byte-identical when <Name>' -ForEach @(
        @{ Name = 'it is not JSON'; Edit = { param($t) '{ not json' } }
        @{ Name = 'it has an unknown field'; Edit = { param($t) $t.Replace('"Disabled":false', '"Disabled":false,"Extra":1') } }
        @{ Name = 'a role is not allowed'; Edit = { param($t) $t.Replace('"Role":"admin"', '"Role":"root"') } }
        @{ Name = 'the user list is empty'; Edit = { param($t) '{"Schema":1,"Users":[]}' } }
        @{ Name = 'the password record is cut short'; Edit = { param($t) $t.Replace('"Algorithm":"PBKDF2-SHA256",', '') } }
        @{ Name = 'it is larger than 64 KiB'; Edit = { param($t) $t + (' ' * 70000) } }
    ) {
        $config = New-GoodUsersConfig
        $file = Join-Path $config 'users.json'
        $text = & $script:GoodText $config
        [IO.File]::WriteAllText($file, (& $Edit $text))
        $old = Join-Path $config 'admin-password.json'
        Copy-Item -LiteralPath "$old.migrated" -Destination $old
        $hashFile = (Get-FileHash -LiteralPath $file).Hash
        $hashOld = (Get-FileHash -LiteralPath $old).Hash
        (Read-Store $config).Status | Should -Be 'Corrupt'
        Test-Pw $config $script:Password | Should -BeFalse
        $guard = & (Get-Module ChannelForge) { param($c) Get-ChannelForgeStartGuard -Address '0.0.0.0' -ConfigRoot $c -AllowSetupMode } $config
        $guard.State | Should -Be 'Refused'
        $guard.Reason | Should -BeLike '*damaged*'
        $guard.Reason | Should -Not -Match 'Salt|Hash|Extra|not json'
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $hashFile
        (Get-FileHash -LiteralPath $old).Hash | Should -Be $hashOld
    }
}

Describe 'First-time setup' {
    It 'creates users.json with the first user admin and puts the user id in the session' {
        $config = Join-Path $TestDrive 'fresh'
        $result = & (Get-Module ChannelForge) {
            param($Config, $Password)
            $setup = @{}
            $code = New-ChannelForgeSetupCode -Setup $setup
            $body = [Text.Encoding]::UTF8.GetBytes((@{ code = $code; password = $Password } | ConvertTo-Json -Compress))
            $store = @{}
            $response = Invoke-ChannelForgeFirstRunSubmit -Store $store -Setup $setup -BodyStream ([IO.MemoryStream]::new($body)) -ContentLength $body.Length -ConfigRoot $Config -CookieFormat 'cf_session={0}'
            [pscustomobject]@{ Status = $response.StatusCode; Session = @($store.Values)[0]; Code = $code; Body = $response.Body }
        } $config $script:Password
        $result.Status | Should -Be 200
        Test-Path -LiteralPath (Join-Path $config 'admin-password.json') | Should -BeFalse
        $users = (Read-Store $config).Users
        $users[0].Name | Should -Be 'admin'
        $users[0].Role | Should -Be 'admin'
        $result.Session.UserId | Should -Be $users[0].Id
        Test-Pw $config $script:Password | Should -BeTrue
        $text = Get-Content -Raw -LiteralPath (Join-Path $config 'users.json')
        $text | Should -Not -Match ([regex]::Escape($script:Password))
        $text | Should -Not -Match ([regex]::Escape($result.Code))
    }
}

Describe 'Console reset with users.json' {
    It 'removes users.json and the old file so the old password cannot come back, and keeps other files' {
        $config = New-ConfigWithOldFile
        Read-Store $config | Out-Null
        Copy-Item -LiteralPath (Join-Path $config 'admin-password.json.migrated') -Destination (Join-Path $config 'admin-password.json')
        Set-Content -LiteralPath (Join-Path $config 'lineup.json') -Value '{"keep":true}'
        Mock -ModuleName ChannelForge Test-ChannelForgeElevated { $true }
        (Reset-ChannelForgeAdminPassword -ConfigRoot $config -Confirm:$false).Reset | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $config 'users.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $config 'admin-password.json') | Should -BeFalse
        (Read-Store $config).Status | Should -Be 'Missing'
        Test-Path -LiteralPath (Join-Path $config 'lineup.json') | Should -BeTrue
    }
}
