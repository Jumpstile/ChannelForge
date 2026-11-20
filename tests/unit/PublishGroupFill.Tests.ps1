BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force 3>$null
    $script:M = Get-Module ChannelForge
    $script:V8 = 'blocker-2-contract/v8'
    $script:V10 = 'blocker-2-contract/v10'

    function New-FillChannel([string]$Name, [string]$TvgId, [string]$Group) {
        New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName $Name -DisplayName $Name -TvgId $TvgId -Url "https://$TvgId.example.invalid/s" -Group $Group
    }

    # Exports the channels as playlist bytes and builds the candidate manifest the same way a build does.
    function Build-Fill($Channels, [string]$Version, [switch]$Fill, [hashtable]$Pin = @{}) {
        $sourceId = & $script:M { Get-ChannelForgeLogicalSourceId -ProviderName 'p' -SourceName 'l' -SourceKind 'M3U' -SourceOrdinal 0 }
        $raw = @(& $script:M { param($c, $id, $v) Get-ChannelForgeRawM3UProjection -Channel $c -LogicalSourceId $id -CandidateContractVersion $v } $Channels $sourceId $Version | Sort-Object EntryId)
        $path = Join-Path $TestDrive ('fill-' + [guid]::NewGuid().ToString('N') + '.m3u')
        @($raw | ForEach-Object Channel) | Export-ChannelForgeM3UPlaylist -Path $path -FillEmptyGroups:$Fill -GroupPin $Pin
        $bytes = [IO.File]::ReadAllBytes($path)
        $plainPath = Join-Path $TestDrive ('plain-' + [guid]::NewGuid().ToString('N') + '.m3u')
        @($raw | ForEach-Object Channel) | Export-ChannelForgeM3UPlaylist -Path $plainPath
        $order = @($raw | ForEach-Object EntryId)
        $result = & $script:M { param($r, $b, $o, $v, $p) ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $r -M3UBytes $b -SerializedM3UEntryOrder $o -CandidateContractVersion $v -GroupPin $p } $raw $bytes $order $Version $Pin
        [pscustomobject]@{ Bytes = $bytes; PlainBytes = [IO.File]::ReadAllBytes($plainPath); Text = [Text.Encoding]::UTF8.GetString($bytes); Result = $result; Entries = @($result.Manifest.Entries) }
    }

    function Get-FillEntry($Build, [string]$Name) { @($Build.Entries | Where-Object { $_.DisplayName -ceq $Name })[0] }

    $script:Channels = @(
        New-FillChannel 'Example Hockey Night' 'hockey.invalid' ''
        New-FillChannel 'Example Hockey Show' 'kept.invalid' 'My Sports'
        New-FillChannel 'Example Golf Hour' 'golf.invalid' ''
        New-FillChannel 'Example Hockey Baseball Special' 'two.invalid' ''
        New-FillChannel 'Example Plain Channel' 'plain.invalid' ''
    )
    $script:Pin = @{ 'golf.invalid' = 'Pinned Group' }
}

Describe 'Fill empty playlist groups (candidate v10)' {
    It 'fills an empty group when exactly one category matches' {
        $b = Build-Fill $script:Channels $script:V10 -Fill -Pin $script:Pin
        $b.Text | Should -Match 'group-title="Hockey",Example Hockey Night'
        $e = Get-FillEntry $b 'Example Hockey Night'
        $e.GroupTitle | Should -BeExactly 'Hockey'
        $e.RawGroup | Should -BeExactly ''
        $e.GroupSource | Should -Be 'CategoryList'
        (Get-FillEntry $b 'Example Plain Channel').GroupSource | Should -Be 'None'
        $b.Result.GroupFilledCount | Should -Be 2
    }

    It 'never overwrites a group the provider set' {
        $b = Build-Fill $script:Channels $script:V10 -Fill -Pin @{ 'kept.invalid' = 'Pinned Group' }
        $b.Text | Should -Match 'group-title="My Sports",Example Hockey Show'
        $e = Get-FillEntry $b 'Example Hockey Show'
        $e.GroupTitle | Should -BeExactly 'My Sports'
        $e.GroupSource | Should -Be 'Provider'
    }

    It 'lets a pinned group win over the category list' {
        $b = Build-Fill $script:Channels $script:V10 -Fill -Pin $script:Pin
        $b.Text | Should -Match 'group-title="Pinned Group",Example Golf Hour'
        $e = Get-FillEntry $b 'Example Golf Hour'
        $e.GroupTitle | Should -BeExactly 'Pinned Group'
        $e.GroupSource | Should -Be 'Pin'
    }

    It 'leaves a two-match channel empty, publishes it, and writes one review line' {
        $b = Build-Fill $script:Channels $script:V10 -Fill -Pin $script:Pin
        $b.Text | Should -Match 'tvg-id="two.invalid",Example Hockey Baseball Special'
        (Get-FillEntry $b 'Example Hockey Baseball Special').GroupSource | Should -Be 'None'
        @($b.Result.GroupReviewLines).Count | Should -Be 1
        $b.Result.GroupReviewLines[0] | Should -BeExactly 'Channel Example Hockey Baseball Special could match Baseball and Hockey. Pick one group for it.'
    }

    It 'keeps v8 bytes and raw groups unchanged' {
        $b = Build-Fill $script:Channels $script:V8
        $b.Text | Should -Not -Match 'group-title="Hockey"'
        $b.Entries.Count | Should -Be 5
        (Get-FillEntry $b 'Example Hockey Night').GroupTitle | Should -BeExactly ''
        @($b.Result.GroupReviewLines).Count | Should -Be 0
        # Same bytes as an export with no fill options at all.
        [Convert]::ToBase64String($b.Bytes) | Should -Be ([Convert]::ToBase64String($b.PlainBytes))
    }

    It 'gives v10 slices that hash to their entry content and cover the whole file' {
        $b = Build-Fill $script:Channels $script:V10 -Fill -Pin $script:Pin
        $header = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n").Length
        $cursor = $header
        foreach ($e in @($b.Entries | Sort-Object { [uint64]$_.EntryOutputSlice.ByteOffset })) {
            $s = $e.EntryOutputSlice
            [uint64]$s.ByteOffset | Should -Be $cursor
            $slice = [byte[]]::new([int]$s.ByteLength)
            [Array]::Copy($b.Bytes, [int]$s.ByteOffset, $slice, 0, [int]$s.ByteLength)
            $hash = & $script:M { param($x) Get-ChannelForgeDomainHash -Domain 'candidate-entry-content/v1' -Bytes $x } $slice
            $hash | Should -Be $s.EntryContentHash
            $cursor += [int]$s.ByteLength
        }
        $cursor | Should -Be $b.Bytes.Length
    }

    It 'fails closed when the filled group is changed after the build' {
        $b = Build-Fill $script:Channels $script:V10 -Fill -Pin $script:Pin
        $tampered = [byte[]]$b.Bytes.Clone()
        $text = [Text.Encoding]::UTF8.GetString($tampered).Replace('group-title="Hockey"', 'group-title="Hockez"')
        $tamperedBytes = [Text.Encoding]::UTF8.GetBytes($text)
        $sourceId = & $script:M { Get-ChannelForgeLogicalSourceId -ProviderName 'p' -SourceName 'l' -SourceKind 'M3U' -SourceOrdinal 0 }
        $raw = @(& $script:M { param($c, $id, $v) Get-ChannelForgeRawM3UProjection -Channel $c -LogicalSourceId $id -CandidateContractVersion $v } $script:Channels $sourceId $script:V10 | Sort-Object EntryId)
        $order = @($raw | ForEach-Object EntryId)
        { & $script:M { param($r, $x, $o, $v, $p) ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $r -M3UBytes $x -SerializedM3UEntryOrder $o -CandidateContractVersion $v -GroupPin $p } $raw $tamperedBytes $order $script:V10 $script:Pin } | Should -Throw '*FAIL_CLOSED*'

        # An accepted file that was changed after acceptance is also refused.
        $descriptor = [pscustomobject]@{ RelativePath = 'merged.m3u'; ByteLength = $b.Bytes.Length; ContentHash = (& $script:M { param($x) Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $x } $b.Bytes) }
        $entry = Get-FillEntry $b 'Example Hockey Night'
        { & $script:M { param($d, $x, $e) Get-ChannelForgeKeepAcceptedEntry -PriorM3UDescriptor $d -PriorM3UBytes $x -PriorAcceptedEntrySlice $e } $descriptor $tamperedBytes ([pscustomobject]@{ EntryId = $entry.EntryId; EntryOutputSlice = [pscustomobject]$entry.EntryOutputSlice }) } | Should -Throw '*FAIL_CLOSED*'
    }

    It 'gives v10 the same entry hashes as v8 when nothing is filled' {
        $nothing = @($script:Channels[1], $script:Channels[4])
        $v8 = Build-Fill $nothing $script:V8
        $v10 = Build-Fill $nothing $script:V10 -Fill
        [Convert]::ToBase64String($v10.Bytes) | Should -Be ([Convert]::ToBase64String($v10.PlainBytes))
        # Entry ids change with the version, so compare per channel, not by position.
        $perChannel = { param($b) @($b.Entries | ForEach-Object { "$($_.DisplayName) $($_.EntryOutputSlice.EntryContentHash)" } | Sort-Object) }
        & $perChannel $v10 | Should -Be (& $perChannel $v8)
    }
}
