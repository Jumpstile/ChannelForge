BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    function New-Root { $r = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $r | Out-Null; $r }
    function Get-LookupFile($Root) { Join-Path $Root 'data\logo-lookup.json' }
    function Read-Lookup($Root) { Get-Content -LiteralPath (Get-LookupFile $Root) -Raw | ConvertFrom-Json -AsHashtable }
    function Use-List($Entries) { $json = ConvertTo-Json -InputObject @($Entries) -Compress; Mock -ModuleName ChannelForge Get-ChannelForgeLogoListDownload { $json }.GetNewClosure() }
    function New-Entry($Id, $Name, $Url) { [ordered]@{ channel = $Id; name = $Name; url = $Url } }
    $script:ImgHost = 'img.example.com'
}

Describe 'Update-ChannelForgeLogoLookup' {
    It 'keeps one link per ID and name, and skips unsafe, unapproved, repeated and ambiguous entries' {
        $r = New-Root
        Use-List @(
            (New-Entry 'One.us' 'One HD' 'https://img.example.com/one.png'),
            (New-Entry 'Two.us' 'Two' 'https://img.example.com/two.png'),
            (New-Entry 'Two.us' 'Two' 'https://img.example.com/two-b.png'),
            (New-Entry 'Three.us' 'Shared' 'https://img.example.com/three.png'),
            (New-Entry 'Four.us' 'shared' 'https://img.example.com/four.png'),
            (New-Entry 'four.us' 'Four Lower' 'https://img.example.com/four-lower.png'),
            (New-Entry 'Http.us' 'Http' 'http://img.example.com/h.png'),
            (New-Entry 'Lan.us' 'Lan' 'https://192.168.1.9/l.png'),
            (New-Entry 'User.us' 'User' 'https://u:p@img.example.com/u.png'),
            (New-Entry 'Other.us' 'Other' 'https://cdn.example.net/o.png'),
            @{ channel = 'NoUrl.us' }
        )
        $result = Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost
        $file = Read-Lookup $r
        $file.Version | Should -Be 'logo-lookup/v1'
        $file.ById.Count | Should -Be 4
        $file.ById.Keys | Should -Contain 'four.us'
        $file.ById.Keys | Should -Contain 'Four.us'
        $file.ById['One.us'] | Should -Be 'https://img.example.com/one.png'
        @($file.ByName.Keys | Sort-Object) | Should -Be @('four lower', 'one')
        $result.SkippedIds | Should -Be @('Two.us')
        $result.AmbiguousNames | Should -Be @('shared', 'two')
        $result.HostsSeen.Keys | Should -Contain 'cdn.example.net'
        $result.ById.Added | Should -Be 4
        Get-ChildItem (Split-Path (Get-LookupFile $r)) -Force | Should -HaveCount 1
    }

    It 'writes nothing with -WhatIf' {
        $r = New-Root
        Use-List @((New-Entry 'One.us' 'One' 'https://img.example.com/one.png'))
        $result = Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost -WhatIf
        $result.Written | Should -BeFalse
        Test-Path (Get-LookupFile $r) | Should -BeFalse
    }

    It 'refuses with an empty allow-list, names the hosts it saw, and writes nothing' {
        $r = New-Root
        Use-List @((New-Entry 'One.us' 'One' 'https://img.example.com/one.png'))
        $out = & { try { Update-ChannelForgeLogoLookup -RepositoryRoot $r } catch { $_.Exception.Message } } 6>&1
        "$out" | Should -Match 'img\.example\.com'
        "$out" | Should -Match 'no usable links'
        Test-Path (Get-LookupFile $r) | Should -BeFalse
    }

    It 'reports added, changed and removed against the old file on a second run' {
        $r = New-Root
        Use-List @((New-Entry 'A.us' 'A' 'https://img.example.com/a.png'), (New-Entry 'B.us' 'B' 'https://img.example.com/b.png'), (New-Entry 'C.us' 'C' 'https://img.example.com/c.png'))
        Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost | Out-Null
        Use-List @((New-Entry 'A.us' 'A' 'https://img.example.com/a2.png'), (New-Entry 'B.us' 'B' 'https://img.example.com/b.png'), (New-Entry 'D.us' 'D' 'https://img.example.com/d.png'))
        $result = Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost
        ($result.ById.Added, $result.ById.Changed, $result.ById.Removed) | Should -Be @(1, 1, 1)
        (Read-Lookup $r).ById['A.us'] | Should -Be 'https://img.example.com/a2.png'
    }

    It 'keeps the old file when the list shrinks by more than half' {
        $r = New-Root
        Use-List @(1..4 | ForEach-Object { New-Entry "C$_.us" "C$_" "https://img.example.com/$_.png" })
        Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost | Out-Null
        $before = (Get-FileHash -LiteralPath (Get-LookupFile $r)).Hash
        Use-List @((New-Entry 'C1.us' 'C1' 'https://img.example.com/1.png'))
        { Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost } | Should -Throw '*more than half*'
        (Get-FileHash -LiteralPath (Get-LookupFile $r)).Hash | Should -Be $before
    }

    It 'never overwrites an existing file it cannot read' {
        $r = New-Root
        New-Item -ItemType Directory -Path (Join-Path $r 'data') | Out-Null
        [IO.File]::WriteAllText((Get-LookupFile $r), 'not json')
        Use-List @((New-Entry 'One.us' 'One' 'https://img.example.com/one.png'))
        { Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost } | Should -Throw '*unreadable*'
        [IO.File]::ReadAllText((Get-LookupFile $r)) | Should -Be 'not json'
    }

    It 'refuses a list that is not an array and keeps the old file' {
        $r = New-Root
        Mock -ModuleName ChannelForge Get-ChannelForgeLogoListDownload { '{"channels":[]}' }
        { Update-ChannelForgeLogoLookup -RepositoryRoot $r -AllowedHost $script:ImgHost } | Should -Throw '*not a JSON array*'
        Test-Path (Get-LookupFile $r) | Should -BeFalse
    }
}
