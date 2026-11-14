BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Good = 'https://img.example.com/a.png?v=2'
    function New-Root { $r = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $r | Out-Null; $r }
    function Get-PinFile($Root) { Join-Path $Root 'state\logo-pins.json' }
    function Write-PinFile($Root, $Text) { New-Item -ItemType Directory -Path (Join-Path $Root 'state') -Force | Out-Null; [IO.File]::WriteAllText((Get-PinFile $Root), $Text) }
}

Describe 'Logo pins' {
    It 'sets, replaces by exact TvgId, keeps others, and removes only the named pin' {
        $r = New-Root
        Set-ChannelForgeLogoPin -TvgId 'B.us' -Logo $script:Good -RepositoryRoot $r | Out-Null
        Set-ChannelForgeLogoPin -TvgId 'A.us' -Logo $script:Good -Note 'first' -RepositoryRoot $r | Out-Null
        Set-ChannelForgeLogoPin -TvgId 'a.us' -Logo $script:Good -RepositoryRoot $r | Out-Null
        $new = 'https://img.example.com/b.png'
        $stored = Set-ChannelForgeLogoPin -TvgId 'A.us' -Logo $new -RepositoryRoot $r
        $stored.Logo | Should -Be $new
        $pins = @(Get-ChannelForgeLogoPin -RepositoryRoot $r)
        $pins.TvgId | Should -Be @('A.us', 'B.us', 'a.us')
        $pins[0].Logo | Should -Be $new
        Set-ChannelForgeLogoPin -TvgId 'B.us' -Remove -RepositoryRoot $r
        (Get-ChannelForgeLogoPin -RepositoryRoot $r).TvgId | Should -Be @('A.us', 'a.us')
    }

    It 'says plainly when a pin to remove does not exist' {
        $r = New-Root
        Set-ChannelForgeLogoPin -TvgId 'Nope' -Remove -RepositoryRoot $r -InformationVariable info
        "$info" | Should -Match 'No pin exists'
        Test-Path (Get-PinFile $r) | Should -BeFalse
    }

    It 'refuses bad links and leaves the file bytes unchanged' -ForEach @(
        @{ Link = 'https://192.168.1.9/a.png' }, @{ Link = 'http://img.example.com/a.png' },
        @{ Link = '' }, @{ Link = 'https://user:pw@img.example.com/a.png' }
    ) {
        $r = New-Root
        Set-ChannelForgeLogoPin -TvgId 'A.us' -Logo $script:Good -RepositoryRoot $r | Out-Null
        $before = [IO.File]::ReadAllBytes((Get-PinFile $r))
        { Set-ChannelForgeLogoPin -TvgId 'B.us' -Logo $Link -RepositoryRoot $r } | Should -Throw
        [IO.File]::ReadAllBytes((Get-PinFile $r)) | Should -Be $before
    }

    It 'refuses to Set on a corrupt file, keeps its bytes, and Get warns' -ForEach @(
        @{ Text = '{ not json' }, @{ Text = '{"Version":"logo-identity/v9","Pins":[]}' }
    ) {
        $r = New-Root
        Write-PinFile $r $Text
        $before = [IO.File]::ReadAllBytes((Get-PinFile $r))
        { Set-ChannelForgeLogoPin -TvgId 'A.us' -Logo $script:Good -RepositoryRoot $r } | Should -Throw '*unreadable*'
        [IO.File]::ReadAllBytes((Get-PinFile $r)) | Should -Be $before
        $out = @(Get-ChannelForgeLogoPin -RepositoryRoot $r -WarningVariable w -WarningAction SilentlyContinue)
        $out.Count | Should -Be 0
        "$w" | Should -Match 'unreadable'
    }

    It 'returns nothing and creates nothing when the file is missing' {
        $r = New-Root
        @(Get-ChannelForgeLogoPin -RepositoryRoot $r).Count | Should -Be 0
        Test-Path (Join-Path $r 'state') | Should -BeFalse
    }

    It 'fails and keeps the old file when it is read-only' -Skip:(-not $IsWindows) {
        $r = New-Root
        Set-ChannelForgeLogoPin -TvgId 'A.us' -Logo $script:Good -RepositoryRoot $r | Out-Null
        $file = Get-PinFile $r
        $before = [IO.File]::ReadAllBytes($file)
        Set-ItemProperty -LiteralPath $file -Name IsReadOnly -Value $true
        try {
            { Set-ChannelForgeLogoPin -TvgId 'B.us' -Logo $script:Good -RepositoryRoot $r } | Should -Throw '*old file was left*'
            [IO.File]::ReadAllBytes($file) | Should -Be $before
        }
        finally { Set-ItemProperty -LiteralPath $file -Name IsReadOnly -Value $false }
    }
}
