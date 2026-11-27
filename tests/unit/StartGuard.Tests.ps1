BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $PrivateDir = Join-Path $RepoRoot 'src\ChannelForge\Private'
    . (Join-Path $PrivateDir 'ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $PrivateDir 'Invoke-ChannelForgeSourceEnrollment.ps1')
    foreach ($name in 'New-ChannelForgeAdminPasswordRecord', 'Write-ChannelForgeAdminPasswordFile', 'Read-ChannelForgeAdminPasswordFile', 'Remove-ChannelForgeAdminPasswordFile', 'Read-ChannelForgeUserStore', 'Write-ChannelForgeUserStore', 'Write-ChannelForgeAuditEvent', 'Get-ChannelForgeStartGuard') {
        . (Join-Path $PrivateDir ($name + '.ps1'))
    }
    $script:Base = Join-Path ([System.IO.Path]::GetTempPath()) ('cf-guard-' + [guid]::NewGuid().ToString('N'))
    $script:None = Join-Path $script:Base 'none'
    $script:Good = Join-Path $script:Base 'good'
    $script:Bad = Join-Path $script:Base 'bad'
    foreach ($d in $script:None, $script:Good, $script:Bad) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    Write-ChannelForgeAdminPasswordFile -ConfigRoot $script:Good -Record (New-ChannelForgeAdminPasswordRecord -Password 'demo-test-password-1') | Out-Null
    $script:BadFile = Join-Path $script:Bad 'admin-password.json'
    [System.IO.File]::WriteAllText($script:BadFile, '{ not json')
    $script:BadBefore = (Get-FileHash -LiteralPath $script:BadFile).Hash
    $script:Message = 'ChannelForge will not listen on the network without a password. Run first-time setup, or turn off network access.'
}

AfterAll {
    Remove-Item -LiteralPath $script:Base -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Start guard' {
    It 'lets <_> start with no password and with a password' -ForEach 'localhost', '127.0.0.1', '::1', '[::1]' {
        (Get-ChannelForgeStartGuard -Address $_ -ConfigRoot $script:None).State | Should -Be 'Ready'
        (Get-ChannelForgeStartGuard -Address $_ -ConfigRoot $script:Good).State | Should -Be 'Ready'
    }
    It 'lets loopback start even when the password file is damaged' {
        (Get-ChannelForgeStartGuard -Address '127.0.0.1' -ConfigRoot $script:Bad).State | Should -Be 'Ready'
    }
    It 'refuses <_> with no password, in plain words' -ForEach '0.0.0.0', '::', '192.168.1.20', 'myserver.local' {
        $r = Get-ChannelForgeStartGuard -Address $_ -ConfigRoot $script:None
        $r.State | Should -Be 'Refused'
        $r.Reason | Should -Be $script:Message
    }
    It 'allows <_> when a good password file exists' -ForEach '0.0.0.0', '::', '192.168.1.20', 'myserver.local' {
        (Get-ChannelForgeStartGuard -Address $_ -ConfigRoot $script:Good).State | Should -Be 'Ready'
    }
    It 'reports setup-required instead of refusing when setup mode is allowed' {
        (Get-ChannelForgeStartGuard -Address '0.0.0.0' -ConfigRoot $script:None -AllowSetupMode).State | Should -Be 'SetupRequired'
    }
    It 'refuses a damaged password file, says why, leaves it untouched, and leaks nothing' {
        $r = Get-ChannelForgeStartGuard -Address '0.0.0.0' -ConfigRoot $script:Bad -AllowSetupMode
        $r.State | Should -Be 'Refused'
        $r.Reason | Should -BeLike '*damaged*'
        $r.Reason | Should -BeLike "*$script:Message"
        $r.Reason | Should -Not -BeLike '*not json*'
        $r.Reason | Should -Not -BeLike '*cf-guard*'
        (Get-FileHash -LiteralPath $script:BadFile).Hash | Should -Be $script:BadBefore
    }
    It 'never returns the password record' {
        $r = Get-ChannelForgeStartGuard -Address '0.0.0.0' -ConfigRoot $script:Good
        ($r | ConvertTo-Json -Compress) | Should -Not -Match 'Salt|Hash|demo-test-password'
    }
}
