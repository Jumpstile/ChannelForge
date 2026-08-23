BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:HelperSourcePath = Join-Path $RepoRoot 'src\ChannelForge\Private\Transport\ChannelForgePinnedHttpTransport.cs'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:LoaderState = & (Get-Module -Name ChannelForge) {
        Initialize-ChannelForgePinnedHttpTransport
    }
    $script:Assembly = $script:LoaderState.Type.Assembly
    $script:ConditionalType = $script:Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpConditionalRequest',
        $true,
        $false)
    $script:OptionsType = $script:Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpAcquisitionOptions',
        $true,
        $false)
    $script:PolicyType = $script:Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpStatusPolicy',
        $true,
        $false)
}

Describe 'ChannelForge v5 conditional transport contract' {
    It 'loads the v5 contract and exposes a typed conditional request' {
        $script:LoaderState.ContractVersion | Should -Be 5
        $script:ConditionalType.FullName |
            Should -Be 'ChannelForge.Private.Transport.ChannelForgeHttpConditionalRequest'
        $script:ConditionalType.IsPublic | Should -BeTrue
        $script:ConditionalType.IsClass | Should -BeTrue
    }

    It 'normalizes typed ETag and Last-Modified validators' {
        $constructor=$script:ConditionalType.GetConstructor([type[]]@([string],[Nullable[datetimeoffset]]))
        $lastModified=[datetimeoffset]::Parse('2026-08-20T12:34:56-04:00')
        $request=$constructor.Invoke([object[]]@('  "fixture-v1"  ',[Nullable[datetimeoffset]]$lastModified))
        $request.IfNoneMatch | Should -Be '"fixture-v1"'
        $request.IfModifiedSince.ToUniversalTime() |
            Should -Be $lastModified.ToUniversalTime()
    }

    It 'rejects missing, malformed, control-character, and overlong validators' {
        $constructor=$script:ConditionalType.GetConstructor([type[]]@([string],[Nullable[datetimeoffset]]))
        { $constructor.Invoke([object[]]@('', $null)) } | Should -Throw
        { $constructor.Invoke([object[]]@('not-an-etag', $null)) } | Should -Throw
        $control=[string][char]13 + [string][char]10
        { $constructor.Invoke([object[]]@($control, $null)) } | Should -Throw
        $overlong='"' + ('a' * 1100) + '"'
        { $constructor.Invoke([object[]]@($overlong, $null)) } | Should -Throw
    }

    It 'carries the typed conditional request through the v5 acquisition options' {
        $requestConstructor=$script:ConditionalType.GetConstructor([type[]]@([string],[Nullable[datetimeoffset]]))
        $request=$requestConstructor.Invoke([object[]]@('"fixture-v1"',$null))
        $optionsConstructor=@(
            $script:OptionsType.GetConstructors([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::Public) |
                Where-Object { $_.GetParameters().Count -eq 6 }
        )[0]
        $policy=[Enum]::Parse($script:PolicyType,'Allow304MetadataOnly')
        $options=$optionsConstructor.Invoke([object[]]@(
            'source-id',
            [string[]]@('application/xml','text/xml'),
            $false,
            4096L,
            $policy,
            $request))
        $options.ConditionalRequest.IfNoneMatch | Should -Be '"fixture-v1"'
        $options.StatusPolicy.ToString() | Should -Be 'Allow304MetadataOnly'
        $options.MaxRawResponseBytes | Should -Be 4096
    }

    It 'retains the five-argument compatibility constructor without a conditional request' {
        $constructor=@(
            $script:OptionsType.GetConstructors([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::Public) |
                Where-Object { $_.GetParameters().Count -eq 5 }
        )[0]
        $policy=[Enum]::Parse($script:PolicyType,'Require200')
        $options=$constructor.Invoke([object[]]@(
            'source-id',
            [string[]]@('application/xml'),
            $false,
            4096L,
            $policy))
        $options.ConditionalRequest | Should -BeNullOrEmpty
        $options.StatusPolicy.ToString() | Should -Be 'Require200'
    }

    It 'uses only typed conditional headers and captures typed response validators' {
        $source=Get-Content -Raw -LiteralPath $script:HelperSourcePath
        $source | Should -Match 'request\.Headers\.IfNoneMatch\.ParseAdd'
        $source | Should -Match 'request\.Headers\.IfModifiedSince\s*='
        $source | Should -Match 'responseETag\s*=\s*response\.Headers\.ETag'
        $source | Should -Match 'responseLastModified\s*=\s*response\.Content\.Headers\.LastModified'
        $source | Should -Not -Match '(?i)DefaultRequestHeaders\.Add|request\.Headers\.Add'
    }
}
