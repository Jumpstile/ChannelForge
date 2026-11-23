BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $PrivateDir = Join-Path $RepoRoot 'src\ChannelForge\Private'
    . (Join-Path $PrivateDir 'Get-ChannelForgeCredentialRoot.ps1')
    foreach ($name in 'Save', 'Read', 'Remove') {
        . (Join-Path $PrivateDir ('{0}-ChannelForgeSourceSecret.ps1' -f $name))
    }
    $script:Plain = 'demo-not-real'
    $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('cf-secret-' + [guid]::NewGuid().ToString('N'))
    function New-FakeSecret { ConvertTo-SecureString -String ('https://example.invalid/get.php?password=' + $script:Plain) -AsPlainText -Force }
}

AfterAll {
    Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Source secret store' {
    It 'round-trips a secret and the file text never contains it' {
        $saved = Save-ChannelForgeSourceSecret -Secret (New-FakeSecret) -CredentialRoot $script:Root
        $saved.Success | Should -BeTrue
        $text = Get-Content -LiteralPath (Join-Path $script:Root ($saved.RefId + '.cred')) -Raw
        $text | Should -Not -BeLike '*demo-not-real*'
        $text | Should -Not -BeLike '*example.invalid*'

        $read = Read-ChannelForgeSourceSecret -RefId $saved.RefId -CredentialRoot $script:Root
        $read.Success | Should -BeTrue
        [System.Net.NetworkCredential]::new('', $read.Secret).Password | Should -Be ('https://example.invalid/get.php?password=' + $script:Plain)
    }

    It 'gives 32 lowercase hex ref ids that differ on every call' {
        $a = Save-ChannelForgeSourceSecret -Secret (New-FakeSecret) -CredentialRoot $script:Root
        $b = Save-ChannelForgeSourceSecret -Secret (New-FakeSecret) -CredentialRoot $script:Root
        $a.RefId | Should -Match '^[0-9a-f]{32}$'
        $b.RefId | Should -Not -Be $a.RefId
    }

    It 'leaves no temp file and limits the folder to the current user' {
        Get-ChildItem -LiteralPath $script:Root -Filter '*.tmp' | Should -BeNullOrEmpty
        $acl = Get-Acl -LiteralPath $script:Root
        $acl.AreAccessRulesProtected | Should -BeTrue
        @($acl.Access).Count | Should -Be 1
        $acl.Access[0].IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value |
            Should -Be ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    }

    It 'reports Missing for an unknown ref id' {
        (Read-ChannelForgeSourceSecret -RefId ('0' * 32) -CredentialRoot $script:Root).Category | Should -Be 'Missing'
    }

    It 'reports Corrupt for garbage and Undecryptable for a bad blob' {
        $garbage = 'a' * 32
        Set-Content -LiteralPath (Join-Path $script:Root "$garbage.cred") -Value 'not json'
        $r = Read-ChannelForgeSourceSecret -RefId $garbage -CredentialRoot $script:Root
        $r.Category | Should -Be 'Corrupt'
        $r.Secret | Should -BeNullOrEmpty

        $badBlob = 'b' * 32
        Set-Content -LiteralPath (Join-Path $script:Root "$badBlob.cred") -Value '{"FormatVersion":1,"Secret":"0102ab"}'
        (Read-ChannelForgeSourceSecret -RefId $badBlob -CredentialRoot $script:Root).Category | Should -Be 'Undecryptable'
    }

    It 'deletes only the named file' {
        $a = Save-ChannelForgeSourceSecret -Secret (New-FakeSecret) -CredentialRoot $script:Root
        $b = Save-ChannelForgeSourceSecret -Secret (New-FakeSecret) -CredentialRoot $script:Root
        (Remove-ChannelForgeSourceSecret -RefId $a.RefId -CredentialRoot $script:Root).Success | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Root ($a.RefId + '.cred')) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Root ($b.RefId + '.cred')) | Should -BeTrue
        (Remove-ChannelForgeSourceSecret -RefId $a.RefId -CredentialRoot $script:Root).Category | Should -Be 'Missing'
    }

    It 'never writes the secret to any output stream' {
        $all = & {
            $s = Save-ChannelForgeSourceSecret -Secret (New-FakeSecret) -CredentialRoot $script:Root
            $r = Read-ChannelForgeSourceSecret -RefId $s.RefId -CredentialRoot $script:Root
            $m = Read-ChannelForgeSourceSecret -RefId ('c' * 32) -CredentialRoot $script:Root
            $s; $r; $m
            Remove-ChannelForgeSourceSecret -RefId $s.RefId -CredentialRoot $script:Root
        } *>&1 | Out-String
        $all | Should -Not -BeLike '*demo-not-real*'
    }
}
