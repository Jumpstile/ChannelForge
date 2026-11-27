BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Probe = 'test-password-one'

    # A fresh config folder with one users.json (three users, one per role). Returns the folder and the ids by name.
    function New-TestConfig {
        $config = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $config | Out-Null
        $ids = & (Get-Module ChannelForge) {
            param($Config, $Probe)
            $record = New-ChannelForgeAdminPasswordRecord -Password $Probe -Iterations 1000
            $users = foreach ($pair in @(@('boss', 'admin'), @('edith', 'editor'), @('vera', 'viewer'))) { New-ChannelForgeUserRecord -Name $pair[0] -Role $pair[1] -PasswordRecord $record }
            Write-ChannelForgeUserStore -ConfigRoot $Config -User @($users) | Out-Null
            $map = @{}
            foreach ($user in $users) { $map[$user.Name] = $user.Id }
            $map
        } $config $script:Probe
        [pscustomobject]@{ Config = $config; Ids = $ids }
    }

    # One request through the sign-in gate, in process, as the named user.
    function Invoke-Api {
        param($Setup, [string]$As, [string]$Method, [string]$Path, $Body = $null)
        $result = & (Get-Module ChannelForge) {
            param($Config, $UserId, $Method, $Path, $Json)
            $store = @{}
            $token = New-ChannelForgeWebSession -Store $store -UserId $UserId
            $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Json))
            $response = Get-ChannelForgeWebSignInResponse -Store $store -Method $Method -Path $Path -CookieHeader "cf_session=$token" -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config
            [pscustomobject]@{ StatusCode = $response.StatusCode; Raw = [string]$response.Body }
        } $Setup.Config $Setup.Ids[$As] $Method $Path $(if ($null -eq $Body) { '' } else { $Body | ConvertTo-Json -Compress })
        [pscustomobject]@{ StatusCode = $result.StatusCode; Json = $(if ($result.Raw) { $result.Raw | ConvertFrom-Json } else { $null }); Raw = $result.Raw }
    }

    function Get-SettingsFile { param($Setup) Join-Path $Setup.Config 'user-settings.json' }
    function Read-SettingsFile { param($Setup) Get-Content -LiteralPath (Get-SettingsFile $Setup) -Raw | ConvertFrom-Json }
}

Describe 'Per-user settings' {
    It 'lets every role save only its own appearance, in a file apart from users.json' {
        $s = New-TestConfig
        $usersBefore = (Get-FileHash -LiteralPath (Join-Path $s.Config 'users.json')).Hash
        foreach ($pair in @(@('vera', 'dark'), @('edith', 'light'), @('boss', 'system'))) {
            $put = Invoke-Api $s $pair[0] 'PUT' '/api/settings/me' @{ appearance = $pair[1] }
            $put.StatusCode | Should -Be 200
            $put.Json.appearance | Should -Be $pair[1]
        }
        (Invoke-Api $s 'vera' 'GET' '/api/settings/me').Json.appearance | Should -Be 'dark'
        (Invoke-Api $s 'edith' 'GET' '/api/settings/me').Json.effective | Should -Be 'light'
        $file = Read-SettingsFile $s
        @($file.Users).Count | Should -Be 3
        @($file.Users | Where-Object { $_.Id -eq $s.Ids['vera'] })[0].Settings.appearance | Should -Be 'dark'
        (Get-FileHash -LiteralPath (Join-Path $s.Config 'users.json')).Hash | Should -Be $usersBefore
    }

    It 'uses the user value, else the server value, else system' {
        $s = New-TestConfig
        $r = Invoke-Api $s 'vera' 'GET' '/api/settings/me'
        $r.Json.appearance | Should -BeNullOrEmpty
        $r.Json.effective | Should -Be 'system'
        Test-Path -LiteralPath (Get-SettingsFile $s) | Should -BeFalse
        [IO.File]::WriteAllText((Join-Path $s.Config 'settings.json'), '{"schema":1,"appearance":"dark"}')
        (Invoke-Api $s 'vera' 'GET' '/api/settings/me').Json.effective | Should -Be 'dark'
        Invoke-Api $s 'vera' 'PUT' '/api/settings/me' @{ appearance = 'light' } | Out-Null
        $r = Invoke-Api $s 'vera' 'GET' '/api/settings/me'
        $r.Json.appearance | Should -Be 'light'
        $r.Json.effective | Should -Be 'light'
        (Invoke-Api $s 'edith' 'GET' '/api/settings/me').Json.effective | Should -Be 'dark'
    }

    It 'refuses unknown names, bad values and a user id in the body, and saves nothing' {
        $s = New-TestConfig
        foreach ($bad in @(@{ colour = 'red' }, @{ appearance = 'purple' }, @{ appearance = 5 }, @{ appearance = 'dark'; userId = $s.Ids['boss'] }, @{})) {
            $r = Invoke-Api $s 'vera' 'PUT' '/api/settings/me' $bad
            $r.StatusCode | Should -Be 400
            $r.Json.Error | Should -Be 'invalid-settings'
        }
        Test-Path -LiteralPath (Get-SettingsFile $s) | Should -BeFalse
    }

    It 'keeps the server-wide PUT for Admin only' {
        $s = New-TestConfig
        (Invoke-Api $s 'vera' 'PUT' '/api/settings' @{ appearance = 'dark' }).StatusCode | Should -Be 403
        (Invoke-Api $s 'edith' 'PUT' '/api/settings' @{ appearance = 'dark' }).StatusCode | Should -Be 403
    }

    It 'uses defaults for an unreadable file, keeps it aside on the next save, and leaves users.json alone' {
        $s = New-TestConfig
        $usersBefore = (Get-FileHash -LiteralPath (Join-Path $s.Config 'users.json')).Hash
        [IO.File]::WriteAllText((Get-SettingsFile $s), '{ not json')
        $r = Invoke-Api $s 'vera' 'GET' '/api/settings/me'
        $r.StatusCode | Should -Be 200
        $r.Json.effective | Should -Be 'system'
        (Invoke-Api $s 'vera' 'PUT' '/api/settings/me' @{ appearance = 'dark' }).StatusCode | Should -Be 200
        @(Get-ChildItem -LiteralPath $s.Config -Filter 'user-settings.json.bad-*').Count | Should -Be 1
        (Get-Content -LiteralPath (Get-ChildItem -LiteralPath $s.Config -Filter 'user-settings.json.bad-*')[0].FullName -Raw) | Should -Be '{ not json'
        (Invoke-Api $s 'vera' 'GET' '/api/settings/me').Json.appearance | Should -Be 'dark'
        (Get-FileHash -LiteralPath (Join-Path $s.Config 'users.json')).Hash | Should -Be $usersBefore
    }

    It 'removes a deleted user entry, keeps the others, and ignores a leftover entry for an unknown id' {
        $s = New-TestConfig
        Invoke-Api $s 'vera' 'PUT' '/api/settings/me' @{ appearance = 'dark' } | Out-Null
        Invoke-Api $s 'edith' 'PUT' '/api/settings/me' @{ appearance = 'light' } | Out-Null
        $del = Invoke-Api $s 'boss' 'DELETE' "/api/users/$($s.Ids['vera'])" @{ adminPassword = $script:Probe }
        $del.StatusCode | Should -Be 200
        $file = Read-SettingsFile $s
        @($file.Users).Count | Should -Be 1
        $file.Users[0].Id | Should -Be $s.Ids['edith']
        $ghost = '0' * 32
        [IO.File]::WriteAllText((Get-SettingsFile $s), (@{ Schema = 1; Users = @(@{ Id = $ghost; Settings = @{ appearance = 'dark' } }) } | ConvertTo-Json -Depth 5 -Compress))
        $r = Invoke-Api $s 'edith' 'GET' '/api/settings/me'
        $r.StatusCode | Should -Be 200
        $r.Json.appearance | Should -BeNullOrEmpty
    }

    It 'writes one settings-changed audit line with the user and the setting name and value only' {
        $s = New-TestConfig
        Invoke-Api $s 'vera' 'PUT' '/api/settings/me' @{ appearance = 'dark' } | Out-Null
        $line = @(Get-Content -LiteralPath (Join-Path $s.Config 'audit.jsonl') | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object Event -eq 'settings-changed')
        $line.Count | Should -Be 1
        $line[0].ActorName | Should -Be 'vera'
        $line[0].Result | Should -Be 'ok'
        $line[0].Reason | Should -Be 'appearance dark'
    }
}
