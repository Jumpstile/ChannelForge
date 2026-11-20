BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # Export one guide with the given programmes. Each is @{ Title; Genre } (Genre empty = none set).
    function Export-GenreGuide {
        param([object[]]$Programme, [string]$Name, [object]$ReviewLine = $null)

        $rows = for ($i = 0; $i -lt $Programme.Count; $i++) {
            $genre = if ($Programme[$i].Genre) { "<category>$($Programme[$i].Genre)</category>" } else { '' }
            "<programme start=`"20260815$('{0:D2}' -f (8 + $i))0000 +0000`" stop=`"20260815$('{0:D2}' -f (9 + $i))0000 +0000`" channel=`"c1`"><title>$($Programme[$i].Title)</title>$genre</programme>"
        }
        $xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><tv><channel id=`"c1`"><display-name>C1</display-name></channel>$($rows -join '')</tv>"
        $input = Join-Path $TestDrive "$Name-in.xml"
        [System.IO.File]::WriteAllText($input, $xml)
        $source = [pscustomobject]@{ Name = $Name; Path = $input; Url = ''; Format = 'xmltv'; Supported = $true }
        $merge = Merge-ChannelForgeXmltvProgrammes -Programme @(Import-ChannelForgeConfiguredXmltvSource -Source $source)
        $out = Join-Path $TestDrive "$Name-out.xml"
        if ($null -ne $ReviewLine) { Export-ChannelForgeXmltv -MergeResult $merge -Path $out -AllowedRoot $TestDrive -GenreReviewLine $ReviewLine }
        else { Export-ChannelForgeXmltv -MergeResult $merge -Path $out -AllowedRoot $TestDrive }
        return $out
    }

    function Get-Genres([string]$Path) {
        $doc = [xml][System.IO.File]::ReadAllText($Path)
        , @($doc.tv.programme | ForEach-Object { (@($_.category | Where-Object { $_ } | ForEach-Object { [string]$_ })) -join "|" })
    }
}

Describe 'Guide genre fill' {
    It 'fills <Genre> for the title "<Title>"' -ForEach @(
        @{ Genre = 'Hockey'; Title = 'NHL Tonight' }
        @{ Genre = 'Basketball'; Title = 'NBA Finals Game 3' }
        @{ Genre = 'Auto Racing'; Title = 'Formula 1 Qualifying' }
        @{ Genre = 'NASCAR'; Title = 'NASCAR Cup Series' }
    ) {
        $path = Export-GenreGuide -Programme @(@{ Title = $Title; Genre = '' }) -Name "fill-$Genre"
        (Get-Genres $path)[0] | Should -Be $Genre
    }

    It 'never changes a genre that is already set' {
        $path = Export-GenreGuide -Programme @(@{ Title = 'NHL Tonight'; Genre = 'Sports' }) -Name 'keep'
        (Get-Genres $path)[0] | Should -Be 'Sports'
    }

    It 'leaves a programme with no matching category without a genre' {
        $path = Export-GenreGuide -Programme @(@{ Title = 'Cooking With Sam'; Genre = '' }) -Name 'none'
        (Get-Genres $path)[0] | Should -Be ""
    }

    It 'sets no genre and adds one review line when two categories fit' {
        $lines = [System.Collections.Generic.List[string]]::new()
        $path = Export-GenreGuide -Programme @(@{ Title = 'NHL vs NBA Special'; Genre = '' }) -Name 'two' -ReviewLine $lines
        (Get-Genres $path)[0] | Should -Be ""
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be 'Programme NHL vs NBA Special could match Basketball and Hockey. Pick one genre for it.'
    }

    It 'writes identical bytes when every programme already has a genre' {
        $programmes = @(@{ Title = 'NHL Tonight'; Genre = 'Sports' }, @{ Title = 'Cooking With Sam'; Genre = 'Food' })
        $path = Export-GenreGuide -Programme $programmes -Name 'same'
        $doc = [System.IO.File]::ReadAllText($path)
        $doc | Should -Match '<category>Sports</category>'
        $doc | Should -Match '<category>Food</category>'
        ([regex]::Matches($doc, '<category>')).Count | Should -Be 2
    }
}
