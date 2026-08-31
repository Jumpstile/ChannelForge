BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'source refresh plan' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path (Join-Path $Project 'data/providers'), (Join-Path $Project 'data/epg'), (Join-Path $Project 'cache'), (Join-Path $Project 'reports') | Out-Null
        $script:ProviderPath = Join-Path $Project 'data/providers/provider.json'
        $script:EpgPath = Join-Path $Project 'data/epg/epg.json'
        $script:Provider = [ordered]@{ provider='demo'; sources=@() }
        $script:Epg = [ordered]@{ epg_sources=@() }
        $script:Evaluation = [datetimeoffset]'2026-01-01T00:00:00Z'
        function Save-Configs { $Provider | ConvertTo-Json -Depth 8 | Set-Content $ProviderPath; $Epg | ConvertTo-Json -Depth 8 | Set-Content $EpgPath }
        function Run-Plan { Save-Configs; @(Get-ChannelForgeSourceRefreshPlan -ProviderConfigPath $ProviderPath -EpgConfigPath $EpgPath -CacheRoot (Join-Path $Project 'cache') -EvaluationTimeUtc $Evaluation) }
        function Add-M3U([string]$Name,[bool]$Enabled=$true,[string]$Local='') { $Provider.sources += [pscustomobject]@{name=$Name;url="https://example.invalid/$Name.m3u";enabled=$Enabled;local_playlist=$Local} }
        function Add-Epg([string]$Name,[bool]$Enabled=$true,[string]$Path='') { $o=[ordered]@{name=$Name;priority=10;enabled=$Enabled};if($Path){$o.path=$Path}else{$o.url="https://example.invalid/$Name.xml"};$Epg.epg_sources += [pscustomobject]$o }
        function Mock-M3U($valid,$fresh,$conditional,$etag='',$modified='',$reason=$null) { $script:MockM3U=[pscustomobject]@{MetadataValid=$valid;PayloadValid=$valid;IsFresh=$fresh;CanConditional=$conditional;InvalidReason=$reason;Metadata=[pscustomobject]@{ValidatedAtUtc='2025-12-31T00:00:00Z';ETag=$etag;LastModified=$modified}}; Mock Read-ChannelForgeRemoteM3UFetchCache -ModuleName ChannelForge -MockWith { $script:MockM3U } }
        function Mock-Epg($valid,$fresh,$conditional,$etag='',$modified='',$reason=$null) { $script:MockEpg=[pscustomobject]@{MetadataValid=$valid;PayloadValid=$valid;IsFresh=$fresh;CanConditional=$conditional;InvalidReason=$reason;Metadata=[pscustomobject]@{ValidatedAtUtc='2025-12-31T00:00:00Z';ETag=$etag;LastModified=$modified}}; Mock Read-ChannelForgeRemoteXmltvFetchCache -ModuleName ChannelForge -MockWith { $script:MockEpg } }
    }
    It 'uses a fresh valid remote cache' { Add-M3U 'Fresh';Mock-M3U $true $true $true '"a"';$p=Run-Plan;$p[0].RecommendedAction|Should -Be 'USE_VALID_CACHE';$p[0].CacheState|Should -Be 'FRESH' }
    It 'uses conditional refresh for expired validator cache' { Add-M3U 'Expired';Mock-M3U $true $false $true '"a"';(Run-Plan)[0].RecommendedAction|Should -Be 'CONDITIONAL_REFRESH' }
    It 'uses full refresh for expired cache without validator' { Add-M3U 'Expired';Mock-M3U $true $false $false;(Run-Plan)[0].RecommendedAction|Should -Be 'FULL_REFRESH' }
    It 'plans a missing cache as full refresh' { Add-M3U 'Missing';Mock-M3U $false $false $false -reason MissingMetadata;$p=Run-Plan;$p[0].CacheState|Should -Be 'MISSING';$p[0].RecommendedAction|Should -Be 'FULL_REFRESH' }
    It 'reviews invalid cache metadata' { Add-M3U 'Invalid';Mock-M3U $false $false $false -reason MalformedMetadata;(Run-Plan)[0].CacheState|Should -Be 'INVALID' }
    It 'reports ETag only' { Add-M3U 'Etag';Mock-M3U $true $false $true '"a"';(Run-Plan)[0].Validator|Should -Be 'ETAG' }
    It 'reports Last-Modified only' { Add-M3U 'Modified';Mock-M3U $true $false $true '' '2025-12-31T00:00:00Z';(Run-Plan)[0].Validator|Should -Be 'LAST_MODIFIED' }
    It 'reports both validators' { Add-M3U 'Both';Mock-M3U $true $false $true '"a"' '2025-12-31T00:00:00Z';(Run-Plan)[0].Validator|Should -Be 'ETAG_AND_LAST_MODIFIED' }
    It 'reports local M3U as non-network' { Add-M3U 'Local' $true 'data/playlists/local.m3u';$p=Run-Plan;$p[0].Kind|Should -Be 'local';$p[0].CacheState|Should -Be 'NOT_APPLICABLE_LOCAL' }
    It 'reports local EPG as non-network' { Add-Epg 'LocalGuide' $true 'guide.xml';$p=Run-Plan;$p[0].Kind|Should -Be 'local';$p[0].CacheState|Should -Be 'NOT_APPLICABLE_LOCAL' }
    It 'marks disabled sources excluded' { Add-M3U 'Disabled' $false;$p=Run-Plan;$p[0].CacheState|Should -Be 'DISABLED';$p[0].RecommendedAction|Should -Be 'REVIEW' }
    It 'sorts source rows deterministically' { Add-M3U 'Zulu';Add-M3U 'Alpha';Add-Epg 'Guide';$p=Run-Plan;@($p.SourceId)|Should -Be (@($p.SourceId|Sort-Object)) }
    It 'is deterministic at a fixed evaluation time' { Add-M3U 'Stable';Mock-M3U $true $true $true '"a"';$a=(Run-Plan|ConvertTo-Json -Depth 8);$b=(Run-Plan|ConvertTo-Json -Depth 8);$a|Should -Be $b }
    It 'does not expose URL or credential-shaped data' { Add-M3U 'Secret';$p=Run-Plan;$raw=$p|ConvertTo-Json -Depth 8;$raw|Should -Not -Match 'https://|TOKEN|PASSWORD|ACCOUNT_ID' }
    It 'does not create accepted state or generation output' { Add-M3U 'Reports';$null=Run-Plan;Test-Path (Join-Path $Project 'output')|Should -BeFalse }
    It 'does not acquire remotely or mutate accepted state' { Add-M3U 'NoFetch'; Save-Configs; Mock Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge; Mock Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge; $before = @(Get-ChildItem $Project -Recurse -File | ForEach-Object FullName); $null = Run-Plan; $after = @(Get-ChildItem $Project -Recurse -File | ForEach-Object FullName); @($after | Where-Object { $_ -notin $before }) | Should -BeNullOrEmpty; Should -Invoke Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -Times 0; Should -Invoke Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -Times 0 }
    It 'writes deterministic JSON and Markdown reports without secrets' {
        Add-M3U 'ScriptSource'
        Save-Configs
        $command = Join-Path $script:Root 'scripts/Get-ChannelForgeSourceRefreshPlan.ps1'
        & $command -Root $script:Root -ProviderConfigPath $ProviderPath -EpgConfigPath $EpgPath -CacheRoot (Join-Path $Project 'cache') -OutputRoot (Join-Path $Project 'reports') -EvaluationTimeUtc $Evaluation | Out-Null
        $jsonPath = Join-Path $Project 'reports/source-refresh-plan.json'
        $mdPath = Join-Path $Project 'reports/source-refresh-plan.md'
        Test-Path $jsonPath | Should -BeTrue
        Test-Path $mdPath | Should -BeTrue
        "$((Get-Content $jsonPath -Raw))$((Get-Content $mdPath -Raw))" | Should -Not -Match 'https://|TOKEN|PASSWORD|ACCOUNT_ID'
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jsonPath))
        & $command -Root $Project -ProviderConfigPath $ProviderPath -EpgConfigPath $EpgPath -CacheRoot (Join-Path $Project 'cache') -OutputRoot (Join-Path $Project 'reports') -EvaluationTimeUtc $Evaluation | Out-Null
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($jsonPath)) | Should -Be $before
        Test-Path (Join-Path $Project 'output') | Should -BeFalse
    }
}
