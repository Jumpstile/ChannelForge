BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # A fresh config folder with users.json. Spec items: Name, Role, Password. Returns the folder and the ids by name.
    function New-TestConfig {
        param([object[]]$Spec)
        $config = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $config | Out-Null
        $ids = & (Get-Module ChannelForge) {
            param($Config, $Spec)
            $users = foreach ($item in $Spec) {
                New-ChannelForgeUserRecord -Name $item.Name -Role $item.Role -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password $item.Password -Iterations 1000)
            }
            Write-ChannelForgeUserStore -ConfigRoot $Config -User @($users) | Out-Null
            $ids = @{}
            foreach ($user in $users) { $ids[$user.Name] = $user.Id }
            $ids
        } $config $Spec
        [pscustomobject]@{ Config = $config; Ids = $ids; Store = @{}; Audit = (Join-Path $config 'audit.jsonl') }
    }

    # One request through the sign-in gate in process. Returns StatusCode, Raw, Json and the session token a sign-in set.
    function Invoke-Gate {
        param($Setup, [string]$Method, [string]$Path, $Body = $null, [string]$Token = '')
        $result = & (Get-Module ChannelForge) {
            param($Config, $Store, $Method, $Path, $Json, $Token)
            $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Json))
            $response = Get-ChannelForgeWebSignInResponse -Store $Store -Method $Method -Path $Path -CookieHeader "cf_session=$Token" -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config -SourceAddress '10.1.2.3'
            [pscustomobject]@{ StatusCode = $response.StatusCode; Raw = [string]$response.Body; Cookie = [string]$response.Headers['Set-Cookie'] }
        } $Setup.Config $Setup.Store $Method $Path $(if ($null -eq $Body) { '' } else { $Body | ConvertTo-Json -Compress }) $Token
        $newToken = if ($result.Cookie -match 'cf_session=([0-9A-Za-z_-]+)') { $Matches[1] } else { '' }
        [pscustomobject]@{ StatusCode = $result.StatusCode; Raw = $result.Raw; Json = $(if ($result.Raw) { $result.Raw | ConvertFrom-Json } else { $null }); Token = $newToken }
    }

    function Read-TestAudit { param($Setup) @(Get-Content -LiteralPath $Setup.Audit | ForEach-Object { $_ | ConvertFrom-Json }) }
}

Describe 'Audit trail: a full run' {
    It 'records who did what and never writes a password, code, token, session id or password record' {
        $probes = @('AdminProbe-pass-111', 'WrongProbe-pass-222', 'TempProbe-pass-333', 'NewProbe-pass-444', 'ResetProbe-pass-555', 'StrangerName-666')
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin'; Password = $probes[0] }, @{ Name = 'viewer1'; Role = 'viewer'; Password = $probes[0] })

        (Invoke-Gate $s POST '/api/auth/sign-in' @{ name = 'boss'; password = $probes[1] }).StatusCode | Should -Be 401
        (Invoke-Gate $s POST '/api/auth/sign-in' @{ name = $probes[5]; password = $probes[1] }).StatusCode | Should -Be 401
        $in = Invoke-Gate $s POST '/api/auth/sign-in' @{ name = 'boss'; password = $probes[0] }
        $in.StatusCode | Should -Be 200
        $token = $in.Token
        $token | Should -Not -BeNullOrEmpty

        $add = Invoke-Gate $s POST '/api/users' @{ adminPassword = $probes[0]; name = 'Maria'; role = 'editor'; temporaryPassword = $probes[2] } $token
        $add.StatusCode | Should -Be 201
        $maria = $add.Json.User.Id
        (Invoke-Gate $s PUT "/api/users/$maria" @{ role = 'viewer'; disabled = $false } $token).StatusCode | Should -Be 200
        (Invoke-Gate $s POST "/api/users/$maria/reset-password" @{ adminPassword = $probes[0]; temporaryPassword = $probes[4] } $token).StatusCode | Should -Be 200
        (Invoke-Gate $s DELETE "/api/users/$maria" @{ adminPassword = $probes[0] } $token).StatusCode | Should -Be 200
        (Invoke-Gate $s DELETE "/api/users/$($s.Ids['boss'])" @{ adminPassword = $probes[0] } $token).StatusCode | Should -Be 409
        (Invoke-Gate $s POST '/api/auth/change-password' @{ currentPassword = $probes[0]; newPassword = $probes[3] } $token).StatusCode | Should -Be 200
        (Invoke-Gate $s POST '/api/auth/sign-out' $null $token).StatusCode | Should -Be 200

        $viewer = (Invoke-Gate $s POST '/api/auth/sign-in' @{ name = 'viewer1'; password = $probes[0] })
        (Invoke-Gate $s GET '/api/audit' $null $viewer.Token).StatusCode | Should -Be 403

        $events = Read-TestAudit $s
        ($events | ForEach-Object { "$($_.Event):$($_.Result)" }) | Should -Be @(
            'sign-in:refused', 'sign-in:refused', 'sign-in:ok', 'user-added:ok', 'user-changed:ok', 'password-reset:ok',
            'user-deleted:ok', 'last-admin:refused', 'change-password:ok', 'sign-out:ok', 'sign-in:ok', 'role-check:refused')
        $events[1].ActorName | Should -Be 'unknown'
        $events[2].ActorName | Should -Be 'boss'
        $events[2].RemoteAddress | Should -Be '10.1.2.3'
        $events[4].Reason | Should -Be 'role editor to viewer'
        $events[6].TargetName | Should -Be 'Maria'

        $text = [System.IO.File]::ReadAllText($s.Audit)
        $record = (Get-Content -LiteralPath (Join-Path $s.Config 'users.json') -Raw | ConvertFrom-Json).Users[0].Password
        foreach ($secret in $probes + @($token, $viewer.Token, $record.Hash, $record.Salt)) { $text | Should -Not -BeLike "*$secret*" }
    }
}

Describe 'Audit trail: reading it' {
    It 'is Admin only, newest first, filters by user and limits the count' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin'; Password = 'AdminProbe-pass-111' }, @{ Name = 'Maria'; Role = 'viewer'; Password = 'AdminProbe-pass-111' })
        $boss = (Invoke-Gate $s POST '/api/auth/sign-in' @{ name = 'boss'; password = 'AdminProbe-pass-111' }).Token
        foreach ($i in 1..3) { Invoke-Gate $s POST '/api/auth/sign-in' @{ name = 'Maria'; password = 'bad-password-xyz' } | Out-Null }

        $all = Invoke-Gate $s GET '/api/audit' $null $boss
        $all.StatusCode | Should -Be 200
        @($all.Json.Events).Count | Should -Be 4
        $all.Json.Events[0].ActorName | Should -Be 'Maria'
        $all.Json.Events[3].ActorName | Should -Be 'boss'
        @((Invoke-Gate $s GET '/api/audit?user=boss' $null $boss).Json.Events).Count | Should -Be 1
        @((Invoke-Gate $s GET "/api/audit?user=$($s.Ids['Maria'])" $null $boss).Json.Events).Count | Should -Be 3
        @((Invoke-Gate $s GET '/api/audit?limit=2' $null $boss).Json.Events).Count | Should -Be 2
        @((Invoke-Gate $s GET '/api/audit?limit=nonsense' $null $boss).Json.Events).Count | Should -Be 4
    }
}

Describe 'Audit trail: trimming' {
    It 'drops events older than 12 months and keeps only the newest lines; a bad line inside the limit stays' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin'; Password = 'AdminProbe-pass-111' })
        $now = [datetime]'2026-11-26T12:00:00Z'
        $line = { param($t) '{"TimeUtc":"' + $t + '","Event":"sign-in","Result":"ok"}' }
        $lines = @((& $line '2025-01-01T00:00:00Z'), 'not json at all', (& $line '2026-05-01T00:00:00Z'), (& $line '2026-06-01T00:00:00Z'), (& $line '2026-07-01T00:00:00Z'))
        [System.IO.File]::WriteAllText($s.Audit, (($lines -join "`n") + "`n"))
        & (Get-Module ChannelForge) { param($c, $n) Invoke-ChannelForgeAuditTrim -ConfigRoot $c -Now $n } $s.Config $now
        @(Get-Content -LiteralPath $s.Audit).Count | Should -Be 4

        & (Get-Module ChannelForge) { param($c, $n) Invoke-ChannelForgeAuditTrim -ConfigRoot $c -Now $n -MaxLines 2 } $s.Config $now
        $left = @(Get-Content -LiteralPath $s.Audit)
        $left.Count | Should -Be 2
        $left[1] | Should -BeLike '*2026-07-01*'
    }

    It 'leaves the file whole when the trim fails' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin'; Password = 'AdminProbe-pass-111' })
        $old = '{"TimeUtc":"2020-01-01T00:00:00Z","Event":"sign-in","Result":"ok"}'
        [System.IO.File]::WriteAllText($s.Audit, "$old`n")
        $hold = [System.IO.File]::Open($s.Audit, 'Open', 'Read', 'None')
        try { & (Get-Module ChannelForge) { param($c) $WarningPreference = 'SilentlyContinue'; Invoke-ChannelForgeAuditTrim -ConfigRoot $c } $s.Config }
        finally { $hold.Dispose() }
        [System.IO.File]::ReadAllText($s.Audit) | Should -Be "$old`n"
    }
}

Describe 'Audit trail: a broken audit file never stops the user' {
    It 'still signs in and still adds a user when audit.jsonl cannot be written' {
        $s = New-TestConfig @(@{ Name = 'boss'; Role = 'admin'; Password = 'AdminProbe-pass-111' })
        New-Item -ItemType Directory -Path $s.Audit | Out-Null
        $in = Invoke-Gate $s POST '/api/auth/sign-in' @{ name = 'boss'; password = 'AdminProbe-pass-111' }
        $in.StatusCode | Should -Be 200
        (Invoke-Gate $s POST '/api/users' @{ adminPassword = 'AdminProbe-pass-111'; name = 'Maria'; role = 'viewer'; temporaryPassword = 'TempProbe-pass-333' } $in.Token).StatusCode | Should -Be 201
    }
}
