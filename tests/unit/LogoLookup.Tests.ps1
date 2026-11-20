BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Own = 'https://img.example.com/own.png'
    $script:Pinned = 'https://img.example.com/pinned.png'
    $script:ById = 'https://img.example.com/by-id.png'
    $script:ByName = 'https://img.example.com/by-name.png'
    $script:Default = 'https://img.example.com/default.png'

    function New-TestChannel {
        param([string]$Name, [string]$Logo = '', [string]$TvgId = "$Name.us")
        New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName $Name -DisplayName $Name -TvgId $TvgId -Url "https://stream.example.com/$Name" -Group 'Sports' -Logo $Logo
    }
    function New-Lookup {
        param([hashtable]$ById = @{}, [hashtable]$ByName = @{}, [string[]]$Ambiguous = @())
        $map = @{
            Status    = 'Ok'
            ById      = [hashtable]::new([System.StringComparer]::Ordinal)
            ByName    = [hashtable]::new([System.StringComparer]::Ordinal)
            Ambiguous = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            Ignored   = [System.Collections.Generic.List[string]]::new()
        }
        foreach ($k in $ById.Keys) { $map.ById[$k] = $ById[$k] }
        foreach ($k in $ByName.Keys) { $map.ByName[$k] = $ByName[$k] }
        foreach ($k in $Ambiguous) { [void]$map.Ambiguous.Add($k) }
        $map
    }
    function Get-Published {
        param([object[]]$Channel, [hashtable]$Lookup, [hashtable]$Pin = @{}, [hashtable]$Default = @{})
        & (Get-Module ChannelForge) {
            param($ch, $lookup, $pin, $default)
            if ($lookup) { @(Get-ChannelForgePublishLogo -Channel @($ch) -LogoPin $pin -GroupDefaultLogo $default -LogoLookup $lookup) }
            else { @(Get-ChannelForgePublishLogo -Channel @($ch) -LogoPin $pin -GroupDefaultLogo $default) }
        } $Channel $Lookup $Pin $Default
    }
    function Get-M3U {
        param([object[]]$Channel, [hashtable]$Lookup)
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.m3u')
        if ($Lookup) { $Channel | Export-ChannelForgeM3UPlaylist -Path $path -LogoLookup $Lookup -WarningAction SilentlyContinue }
        else { $Channel | Export-ChannelForgeM3UPlaylist -Path $path -WarningAction SilentlyContinue }
        [IO.File]::ReadAllBytes($path)
    }
    function New-Root {
        $r = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $r 'data') | Out-Null
        $r
    }
    function Read-Lookup {
        param([string]$Root)
        & (Get-Module ChannelForge) { param($r) Get-ChannelForgeLogoLookupMap -RepositoryRoot $r } $Root
    }
}

Describe 'Logo lookup: no file or no match leaves output as it is today' {
    It 'writes the same M3U bytes with no lookup, an empty lookup, and a lookup that matches nothing' {
        $channels = @((New-TestChannel 'A' ''), (New-TestChannel 'B' $script:Own), (New-TestChannel 'C' 'http://x.example.com/c.png'))
        $none = Get-M3U $channels
        $empty = Get-M3U $channels (New-Lookup)
        $miss = Get-M3U $channels (New-Lookup -ById @{ 'Z.us' = $script:ById } -ByName @{ 'zzz' = $script:ByName })
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($empty)) | Should -Be ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($none)))
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($miss)) | Should -Be ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($none)))
    }

    It 'reports status None and no lookup warning without a lookup' {
        $r = & (Get-Module ChannelForge) { Get-ChannelForgeLogoReport -Channel @(Get-ChannelForgePublishLogo -Channel @()) }
        $r.LookupStatus | Should -Be 'None'
        $r.LookedUp | Should -Be 0
        $r.Warning | Should -BeNullOrEmpty
    }
}

Describe 'Logo lookup: rule 3, exact guide id' {
    It 'fills a channel that has no usable logo and counts it apart from the group default' {
        $p = Get-Published @((New-TestChannel 'A' '')) (New-Lookup -ById @{ 'A.us' = $script:ById }) -Default @{ Sports = $script:Default }
        $p[0].Logo | Should -Be $script:ById
        $p[0].LookedUp | Should -BeTrue
        $p[0].Replaced | Should -BeFalse
    }

    It 'never beats a pin or a public provider logo' {
        $lookup = New-Lookup -ById @{ 'A.us' = $script:ById; 'B.us' = $script:ById }
        $p = Get-Published @((New-TestChannel 'A' ''), (New-TestChannel 'B' $script:Own)) $lookup -Pin @{ 'A.us' = $script:Pinned }
        $p[0].Logo | Should -Be $script:Pinned
        $p[1].Logo | Should -Be $script:Own
        $p.LookedUp | Should -Not -Contain $true
    }

    It 'is case-sensitive on the id and falls back to the group default on a miss' {
        $p = Get-Published @((New-TestChannel 'A' '' 'a.us')) (New-Lookup -ById @{ 'A.us' = $script:ById }) -Default @{ Sports = $script:Default }
        $p[0].Logo | Should -Be $script:Default
        $p[0].Replaced | Should -BeTrue
    }
}

Describe 'Logo lookup: rule 4, exact normalized name' {
    It 'matches ignoring case and quality tags, with or without a guide id' {
        $lookup = New-Lookup -ByName @{ 'espn' = $script:ByName }
        (Get-Published @((New-TestChannel 'ESPN HD' '' 'x.us')) $lookup)[0].Logo | Should -Be $script:ByName
        (Get-Published @((New-TestChannel 'Espn' '' '')) $lookup)[0].Logo | Should -Be $script:ByName
    }

    It 'does no partial match' {
        $p = Get-Published @((New-TestChannel 'ESPN2' '')) (New-Lookup -ByName @{ 'espn' = $script:ByName })
        $p[0].Logo | Should -Be ''
    }

    It 'prefers the id match over the name match' {
        $lookup = New-Lookup -ById @{ 'A.us' = $script:ById } -ByName @{ 'a' = $script:ByName }
        (Get-Published @((New-TestChannel 'A' '')) $lookup)[0].Logo | Should -Be $script:ById
    }

    It 'picks no link when two guide ids share a name, and lists it' {
        $lookup = New-Lookup -ByName @{ 'espn' = $script:ByName }
        $p = Get-Published @((New-TestChannel 'ESPN' '' 'a.us'), (New-TestChannel 'espn HD' '' 'b.us')) $lookup -Default @{ Sports = $script:Default }
        $p.Logo | Should -Be @($script:Default, $script:Default)
        $p.LookupAmbiguous | Should -Not -Contain $false
        $r = & (Get-Module ChannelForge) { param($x, $l) Get-ChannelForgeLogoReport -Channel $x -LogoLookup $l } $p $lookup
        @($r.LookupAmbiguous).Count | Should -Be 2
        $r.Warning | Should -Match 'Logo lookup: 2 ambiguous \(ESPN, espn HD\)\.'
    }

    It 'treats the same name with the same guide id as one channel, not ambiguous' {
        $lookup = New-Lookup -ByName @{ 'espn' = $script:ByName }
        $p = Get-Published @((New-TestChannel 'ESPN' '' 'a.us'), (New-TestChannel 'ESPN' '' 'a.us')) $lookup
        $p.Logo | Should -Be @($script:ByName, $script:ByName)
    }

    It 'picks no link when the file has more than one link for a name' {
        $p = Get-Published @((New-TestChannel 'ESPN' '')) (New-Lookup -ByName @{ 'espn' = $script:ByName } -Ambiguous @('espn'))
        $p[0].Logo | Should -Be ''
        $p[0].LookupAmbiguous | Should -BeTrue
    }
}

Describe 'Logo lookup: reading data\logo-lookup.json' {
    It 'gives empty maps and status None when the file is missing' {
        $m = Read-Lookup (New-Root)
        $m.Status | Should -Be 'None'
        $m.ById.Count | Should -Be 0
    }

    It 'reads the shipped skeleton as Ok with nothing in it' {
        $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $m = Read-Lookup $repo
        $m.Status | Should -Be 'Ok'
        $m.ById.Count + $m.ByName.Count | Should -Be 0
    }

    It 'warns loudly and applies nothing when the file is corrupt' {
        $root = New-Root
        [IO.File]::WriteAllText((Join-Path $root 'data\logo-lookup.json'), '{ not json')
        $m = Read-Lookup $root 3>&1
        ($m | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Message | Should -Match 'Logo lookup unreadable'
        ($m | Where-Object { $_ -is [hashtable] }).Status | Should -Be 'Corrupt'
    }

    It 'ignores a bad link or key with a warning and keeps the good ones' {
        $root = New-Root
        $doc = '{"Version":"logo-lookup/v1","ById":{"A.us":"https://img.example.com/a.png","B.us":"http://img.example.com/b.png"},"ByName":{"Espn":"https://img.example.com/e.png","cnn":"https://img.example.com/c.png"}}'
        [IO.File]::WriteAllText((Join-Path $root 'data\logo-lookup.json'), $doc)
        $out = Read-Lookup $root 3>&1
        $m = $out | Where-Object { $_ -is [hashtable] }
        $m.Status | Should -Be 'Ok'
        @($m.ById.Keys) | Should -Be @('A.us')
        @($m.ByName.Keys) | Should -Be @('cnn')
        @($m.Ignored).Count | Should -Be 2
        ($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Message | Should -Match '2 entries ignored'
    }
}

Describe 'Logo lookup: report' {
    It 'counts looked-up channels and says so in one warning line' {
        $lookup = New-Lookup -ById @{ 'A.us' = $script:ById }
        $p = Get-Published @((New-TestChannel 'A' ''), (New-TestChannel 'B' $script:Own)) $lookup
        $r = & (Get-Module ChannelForge) { param($x, $l) Get-ChannelForgeLogoReport -Channel $x -LogoLookup $l } $p $lookup
        $r.LookedUp | Should -Be 1
        $r.LookupStatus | Should -Be 'Ok'
        $r.Replaced | Should -Be 0
        $r.Warning | Should -Be 'Logo lookup: 1 channel got a looked-up logo.'
    }
}
