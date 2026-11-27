BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Config | Out-Null
    $script:AdminId = & (Get-Module ChannelForge) {
        param($Config)
        $user = New-ChannelForgeUserRecord -Name 'Maria' -Role 'admin' -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password 'password-for-maria' -Iterations 1000)
        Write-ChannelForgeUserStore -ConfigRoot $Config -User @($user) | Out-Null
        $user.Id
    } $script:Config

    # One sign-in in process from a given address and time, through the real gate and the shared limiter.
    function Send-TestSignIn {
        param($Limiter, [string]$Name, [string]$Password, [string]$Address, [datetime]$Now)
        & (Get-Module ChannelForge) {
            param($Config, $Limiter, $Body, $Address, $Now)
            $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Body))
            $r = Get-ChannelForgeWebSignInResponse -Store @{} -Method 'POST' -Path '/api/auth/sign-in' -CookieHeader '' -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config -Limiter $Limiter -SourceAddress $Address -Now $Now
            [pscustomobject]@{ StatusCode = $r.StatusCode; Body = [string]$r.Body; RetryAfter = [string]$r.Headers['Retry-After'] }
        } $script:Config $Limiter (@{ name = $Name; password = $Password } | ConvertTo-Json -Compress) $Address $Now
    }

    function New-TestLimiter { & (Get-Module ChannelForge) { New-ChannelForgeSignInLimiter } }
}

Describe 'Wrong tries per user name' {
    BeforeEach { $script:T0 = [datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Utc); $script:Limiter = New-TestLimiter }

    It 'makes a name wait 60 seconds from any address, refuses the right password meanwhile, then recovers' {
        1..5 | ForEach-Object { (Send-TestSignIn $script:Limiter 'MARIA' 'wrong' "10.0.0.$_" $script:T0).StatusCode | Should -Be 401 }
        $refused = Send-TestSignIn $script:Limiter ' maria ' 'password-for-maria' '10.9.9.9' $script:T0.AddSeconds(30)
        $refused.StatusCode | Should -Be 429
        [int]$refused.RetryAfter | Should -BeGreaterThan 0
        [int]$refused.RetryAfter | Should -BeLessOrEqual 60
        (Send-TestSignIn $script:Limiter 'maria' 'password-for-maria' '10.9.9.9' $script:T0.AddSeconds(61)).StatusCode | Should -Be 200
        $script:Limiter.Names.Count | Should -Be 0
        (Send-TestSignIn $script:Limiter 'maria' 'wrong' '10.9.9.9' $script:T0.AddSeconds(62)).StatusCode | Should -Be 401
    }

    It 'treats an unknown name exactly like a known one' {
        1..5 | ForEach-Object { (Send-TestSignIn $script:Limiter 'nobody' 'wrong' "10.0.0.$_" $script:T0).StatusCode | Should -Be 401 }
        $unknown = Send-TestSignIn $script:Limiter 'nobody' 'wrong' '10.9.9.9' $script:T0.AddSeconds(1)
        $other = New-TestLimiter
        1..5 | ForEach-Object { Send-TestSignIn $other 'maria' 'wrong' "10.0.0.$_" $script:T0 | Out-Null }
        $known = Send-TestSignIn $other 'maria' 'wrong' '10.9.9.9' $script:T0.AddSeconds(1)
        $unknown.StatusCode | Should -Be 429
        $known.StatusCode | Should -Be 429
        $unknown.Body | Should -Be $known.Body
        $unknown.RetryAfter | Should -Be $known.RetryAfter
    }

    It 'keeps the tracked names bounded' {
        $count = & (Get-Module ChannelForge) { param($L, $T) 1..1005 | ForEach-Object { Register-ChannelForgeSignInNameFailure -Limiter $L -Name "random-$_" -Now $T.AddSeconds($_) }; $L.Names.Count } $script:Limiter $script:T0
        $count | Should -Be 1000
    }

    It 'audits the wait as a refused sign-in for this name' {
        1..5 | ForEach-Object { Send-TestSignIn $script:Limiter 'maria' 'wrong' "10.0.0.$_" $script:T0 | Out-Null }
        Send-TestSignIn $script:Limiter 'maria' 'password-for-maria' '10.9.9.9' $script:T0.AddSeconds(1) | Out-Null
        $last = @(Get-Content -LiteralPath (Join-Path $script:Config 'audit.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })[-1]
        $last.Result | Should -Be 'refused'
        $last.Reason | Should -Be 'too many tries for this name'
    }
}

Describe 'Audit gaps' {
    It 'records admin-password-wrong when the Admin retypes their own password wrong, without the password' {
        $r = & (Get-Module ChannelForge) {
            param($Config, $Id)
            $body = @{ name = 'Joe'; role = 'viewer'; temporaryPassword = 'temp-probe-123'; adminPassword = 'typo-probe-xyz' } | ConvertTo-Json -Compress
            $stream = [System.IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($body))
            Invoke-ChannelForgeUsersApi -Method 'POST' -Path '/api/users' -ActorId $Id -BodyStream $stream -ContentLength $stream.Length -ConfigRoot $Config -SourceAddress '10.1.1.1'
        } $script:Config $script:AdminId
        $r.StatusCode | Should -Be 403
        $raw = Get-Content -Raw -LiteralPath (Join-Path $script:Config 'audit.jsonl')
        $raw | Should -Not -Match 'typo-probe-xyz'
        $event = @($raw -split "`n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.Event -eq 'admin-password-wrong' })[0]
        $event.Result | Should -Be 'refused'
        $event.ActorName | Should -Be 'Maria'
    }

    It 'starts a new line when the last line was cut off mid-write' {
        $dir = Join-Path $TestDrive 'cut'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'audit.jsonl'), '{"TimeUtc":"2026-01-01T00:00:00Z","Event":"sign-in","Ac')
        & (Get-Module ChannelForge) { param($Dir) Write-ChannelForgeAuditEvent -ConfigRoot $Dir -EventName 'sign-out' } $dir
        $lines = @(Get-Content -LiteralPath (Join-Path $dir 'audit.jsonl'))
        $lines.Count | Should -Be 2
        ($lines[1] | ConvertFrom-Json).Event | Should -Be 'sign-out'
    }
}
