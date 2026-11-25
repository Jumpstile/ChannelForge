BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $PrivateDir = Join-Path $RepoRoot 'src\ChannelForge\Private'
    . (Join-Path $PrivateDir 'ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $PrivateDir 'Invoke-ChannelForgeSourceEnrollment.ps1')
    foreach ($name in 'New-ChannelForgeAdminPasswordRecord', 'Test-ChannelForgeAdminPassword', 'Test-ChannelForgeAdminPasswordRule',
        'Write-ChannelForgeAdminPasswordFile', 'Read-ChannelForgeAdminPasswordFile', 'Remove-ChannelForgeAdminPasswordFile') {
        . (Join-Path $PrivateDir ($name + '.ps1'))
    }
    $script:Pw = 'demo-test-password-1'
    $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('cf-admin-' + [guid]::NewGuid().ToString('N'))
    $script:Record = New-ChannelForgeAdminPasswordRecord -Password $script:Pw
}

AfterAll {
    Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Admin password record' {
    It 'accepts the right password and refuses a wrong one' {
        Test-ChannelForgeAdminPassword -Password $script:Pw -Record $script:Record | Should -BeTrue
        Test-ChannelForgeAdminPassword -Password 'demo-test-password-2' -Record $script:Record | Should -BeFalse
    }
    It 'stores the algorithm and iteration count' {
        $script:Record.Algorithm | Should -Be 'PBKDF2-SHA256'
        $script:Record.Iterations | Should -BeGreaterOrEqual 600000
        $script:Record.Schema | Should -Be 1
    }
    It 'gives different salts and hashes for the same password' {
        $other = New-ChannelForgeAdminPasswordRecord -Password $script:Pw
        $other.Salt | Should -Not -Be $script:Record.Salt
        $other.Hash | Should -Not -Be $script:Record.Hash
    }
    It 'takes well under a second to hash one password' {
        $ms = (Measure-Command { New-ChannelForgeAdminPasswordRecord -Password $script:Pw }).TotalMilliseconds
        Write-Host ('one hash: {0:N0} ms' -f $ms)
        $ms | Should -BeLessThan 1000
    }
    It 'returns false for a missing, empty or corrupt record without throwing' {
        Test-ChannelForgeAdminPassword -Password $script:Pw -Record $null | Should -BeFalse
        Test-ChannelForgeAdminPassword -Password $script:Pw -Record ([pscustomobject]@{}) | Should -BeFalse
        Test-ChannelForgeAdminPassword -Password $script:Pw -Record ([pscustomobject]@{ Schema = 1; Algorithm = 'PBKDF2-SHA256'; Iterations = 1000; Salt = '!!'; Hash = '??' }) | Should -BeFalse
        Test-ChannelForgeAdminPassword -Password '' -Record $script:Record | Should -BeFalse
    }
}

Describe 'Admin password rule' {
    It 'refuses blank, short and common passwords with a reason' {
        foreach ($bad in '', '   ', 'short-pw', 'PASSWORD12345', 'ChannelForge') {
            $r = Test-ChannelForgeAdminPasswordRule -Password $bad
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Not -BeNullOrEmpty
        }
    }
    It 'accepts a 12-character password that is not common' {
        (Test-ChannelForgeAdminPasswordRule -Password 'twelve-chars').Ok | Should -BeTrue
    }
}

Describe 'Admin password file' {
    It 'reads Missing before anything is written' {
        (Read-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root).Status | Should -Be 'Missing'
    }
    It 'round-trips, never stores the password, and still verifies' {
        (Write-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root -Record $script:Record).Success | Should -BeTrue
        $text = Get-Content -LiteralPath (Join-Path $script:Root 'admin-password.json') -Raw
        $text | Should -Not -BeLike ('*' + $script:Pw + '*')
        $read = Read-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root
        $read.Status | Should -Be 'Ok'
        $read.Record.Iterations | Should -Be $script:Record.Iterations
        Test-ChannelForgeAdminPassword -Password $script:Pw -Record $read.Record | Should -BeTrue
    }
    It 'reads Corrupt for empty or broken files and verifies false' {
        foreach ($body in '', '{not json', '{"Schema":1}') {
            Set-Content -LiteralPath (Join-Path $script:Root 'admin-password.json') -Value $body -NoNewline
            $read = Read-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root
            $read.Status | Should -Be 'Corrupt'
            Test-ChannelForgeAdminPassword -Password $script:Pw -Record $read.Record | Should -BeFalse
        }
    }
    It 'removes only its own file' {
        Set-Content -LiteralPath (Join-Path $script:Root 'settings.json') -Value '{}'
        (Remove-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root).Success | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Root 'admin-password.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Root 'settings.json') | Should -BeTrue
        (Remove-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root).Category | Should -Be 'Missing'
    }
    It 'limits file access to the current account and administrators on Windows' -Skip:(-not $IsWindows) {
        Write-ChannelForgeAdminPasswordFile -ConfigRoot $script:Root -Record $script:Record | Out-Null
        $acl = Get-Acl -LiteralPath (Join-Path $script:Root 'admin-password.json')
        $acl.AreAccessRulesProtected | Should -BeTrue
        @($acl.Access | Where-Object { $_.IdentityReference.Value -match 'Users$|Everyone' }) | Should -HaveCount 0
    }
}
