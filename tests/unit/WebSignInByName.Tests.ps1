BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Config | Out-Null

    # Builds users.json with the given users (Name, Password, Disabled) and returns their ids by name.
    function New-TestUsers {
        param([object[]]$Spec)
        & (Get-Module ChannelForge) {
            param($Config, $Spec)
            Remove-Item -LiteralPath (Join-Path $Config 'users.json') -Force -ErrorAction SilentlyContinue
            $users = foreach ($item in $Spec) {
                $user = New-ChannelForgeUserRecord -Name $item.Name -Role 'admin' -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password $item.Password -Iterations 1000)
                $user.Disabled = [bool]$item.Disabled
                $user
            }
            Write-ChannelForgeUserStore -ConfigRoot $Config -User @($users) | Out-Null
            $ids = @{}
            foreach ($user in $users) { $ids[$user.Name] = $user.Id }
            $ids
        } $script:Config $Spec
    }

    # Posts a sign-in body in process. Returns the response and the session store.
    function Invoke-TestSignIn {
        param([string]$Body)
        & (Get-Module ChannelForge) {
            param($Config, $Body)
            $store = @{}
            $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Body))
            $response = Get-ChannelForgeWebSignInResponse -Store $store -Method 'POST' -Path '/api/auth/sign-in' -CookieHeader '' -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config
            [pscustomobject]@{ Response = $response; Sessions = @($store.Values) }
        } $script:Config $Body
    }
}

Describe 'Sign in by user name' {
    It 'signs in with the right name and password, ignoring name case, and the session belongs to that user' {
        $ids = New-TestUsers @(@{ Name = 'admin'; Password = 'password-for-admin' }, @{ Name = 'Maria'; Password = 'password-for-maria' })
        $result = Invoke-TestSignIn '{"name":"mARIA","password":"password-for-maria"}'
        $result.Response.StatusCode | Should -Be 200
        $result.Sessions.Count | Should -Be 1
        $result.Sessions[0].UserId | Should -Be $ids['Maria']
    }

    It 'gives the same answer for a wrong name, a wrong password and a disabled user' {
        New-TestUsers @(@{ Name = 'admin'; Password = 'password-for-admin' }, @{ Name = 'Maria'; Password = 'password-for-maria'; Disabled = $true }) | Out-Null
        $bodies = @(
            '{"name":"nobody","password":"password-for-admin"}',
            '{"name":"admin","password":"wrong-password-here"}',
            '{"name":"Maria","password":"password-for-maria"}'
        )
        $responses = foreach ($body in $bodies) { (Invoke-TestSignIn $body).Response }
        foreach ($response in $responses) {
            $response.StatusCode | Should -Be 401
            $response.Body | Should -Be $responses[0].Body
            @($response.Headers.Keys) | Should -Be @($responses[0].Headers.Keys)
            $response.Headers.Keys | Should -Not -Contain 'Set-Cookie'
        }
        $responses[0].Body | Should -Not -Match 'password-for|wrong-password-here'
    }

    It 'still works with a password alone when there is exactly one enabled user' {
        $ids = New-TestUsers @(@{ Name = 'admin'; Password = 'password-for-admin' }, @{ Name = 'Maria'; Password = 'password-for-maria'; Disabled = $true })
        $result = Invoke-TestSignIn '{"password":"password-for-admin"}'
        $result.Response.StatusCode | Should -Be 200
        $result.Sessions[0].UserId | Should -Be $ids['admin']
    }

    It 'refuses a password alone when two users are enabled' {
        New-TestUsers @(@{ Name = 'admin'; Password = 'password-for-admin' }, @{ Name = 'Maria'; Password = 'password-for-maria' }) | Out-Null
        $result = Invoke-TestSignIn '{"password":"password-for-admin"}'
        $result.Response.StatusCode | Should -Be 401
        $result.Response.Body | Should -Be (Invoke-TestSignIn '{"name":"nobody","password":"x-wrong-password"}').Response.Body
        $result.Sessions.Count | Should -Be 0
    }
}
