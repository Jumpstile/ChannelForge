param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$WorkDir)
# Builds a fixture lineup and returns the M3U bytes, v8 and v7 candidate values
# as one object. Used to record values from unchanged code and compare later.
Import-Module (Join-Path $Root 'src/ChannelForge/ChannelForge.psd1') -Force
$channels = @(
    New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Example One' -DisplayName 'Example One' -TvgId 'one.invalid' -Url 'https://one.example.invalid/s' -Group 'My Sports' -Logo 'https://img.example.invalid/one.png'
    New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Example Two' -DisplayName 'Example Two' -TvgId 'two.invalid' -Url 'https://two.example.invalid/s' -Group '' -Logo 'https://img.example.invalid/two.png'
    New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Example Three' -DisplayName 'Example Three' -TvgId 'three.invalid' -Url 'https://three.example.invalid/s' -Group 'News' -Logo ''
    New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Example Four' -DisplayName 'Example Four' -TvgId '' -Url 'https://four.example.invalid/s' -Group '' -Logo ''
)
$sourceId = & (Get-Module ChannelForge) { Get-ChannelForgeLogicalSourceId -ProviderName 'p' -SourceName 'l' -SourceKind 'M3U' -SourceOrdinal 0 }
$result = [ordered]@{}
foreach ($version in 'blocker-2-contract/v8', 'blocker-2-contract/v7') {
    $raw = @(& (Get-Module ChannelForge) {
            param($c, $id, $v) Get-ChannelForgeRawM3UProjection -Channel $c -LogicalSourceId $id -CandidateContractVersion $v
        } $channels $sourceId $version | Sort-Object EntryId)
    $ordered = @($raw | ForEach-Object Channel)
    $path = Join-Path $WorkDir ('probe-' + ($version -replace '\W', '') + '.m3u')
    $ordered | Export-ChannelForgeM3UPlaylist -Path $path
    $bytes = [IO.File]::ReadAllBytes($path)
    $order = @($raw | ForEach-Object EntryId)
    $m = & (Get-Module ChannelForge) {
        param($r, $b, $o, $v)
        if ($v -eq 'blocker-2-contract/v8') { ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $r -M3UBytes $b -SerializedM3UEntryOrder $o -CandidateContractVersion $v }
        else { ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $r -CandidateContractVersion $v }
    } $raw $bytes $order $version
    $result[$version] = [ordered]@{
        M3UBase64 = [Convert]::ToBase64String($bytes)
        Entries   = @($m.Manifest.Entries | ForEach-Object {
                [ordered]@{
                    EntryId = $_.EntryId; GroupTitle = $_.GroupTitle; PresentationFingerprint = $_.PresentationFingerprint
                    ByteOffset = $_.EntryOutputSlice.ByteOffset; ByteLength = $_.EntryOutputSlice.ByteLength; EntryContentHash = $_.EntryOutputSlice.EntryContentHash
                }
            })
    }
}
$result | ConvertTo-Json -Depth 6
