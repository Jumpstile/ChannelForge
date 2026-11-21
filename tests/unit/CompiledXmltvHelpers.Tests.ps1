BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Module = Get-Module ChannelForge
    # Loads the compiled types once; both helpers add them on first use.
    & $script:Module { $null = Get-ChannelForgeRecordComparer -Key 'string:A'; $null = Get-ChannelForgeRawXmltvProjection -Programme @() }

    # Small value pools make many records tie on the leading keys, so the tie order is exercised too.
    $script:Seed = 12345
    function Get-NextNumber {
        param([int]$Limit)
        $script:Seed = ($script:Seed * 1103515245 + 12345) % 2147483648
        return [int]($script:Seed % $Limit)
    }
    $script:Words = @('', 'a', 'A', 'b', "tab`there", "line`nbreak", [string][char]0x00E9, 'sur' + [char]::ConvertFromUtf32(0x1F600), 'zz')

    # The comparison script blocks the guide merge and the guide writer used before the compiled comparer.
    $script:OldMerge = [System.Comparison[object]] {
        param($left, $right)
        $c = [System.StringComparer]::Ordinal.Compare([string]$left.Binding.BindingKey, [string]$right.Binding.BindingKey)
        if ($c -ne 0) { return $c }
        $c = if ($left.StartTicks -lt $right.StartTicks) { -1 } elseif ($left.StartTicks -gt $right.StartTicks) { 1 } else { 0 }
        if ($c -ne 0) { return $c }
        $c = if ($left.EndTicks -lt $right.EndTicks) { -1 } elseif ($left.EndTicks -gt $right.EndTicks) { 1 } else { 0 }
        if ($c -ne 0) { return $c }
        $c = [System.StringComparer]::Ordinal.Compare([string]$left.ContentKey, [string]$right.ContentKey)
        if ($c -ne 0) { return $c }
        return [System.StringComparer]::Ordinal.Compare([string]$left.EvidenceKey, [string]$right.EvidenceKey)
    }
    $script:OldExport = [System.Comparison[object]] {
        param($left, $right)
        $c = [System.StringComparer]::Ordinal.Compare($left.BindingKey, $right.BindingKey)
        if ($c -ne 0) { return $c }
        $c = if ($left.StartTicks -lt $right.StartTicks) { -1 } elseif ($left.StartTicks -gt $right.StartTicks) { 1 } else { 0 }
        if ($c -ne 0) { return $c }
        $c = if ($left.EndTicks -lt $right.EndTicks) { -1 } elseif ($left.EndTicks -gt $right.EndTicks) { 1 } else { 0 }
        if ($c -ne 0) { return $c }
        foreach ($name in 'Title', 'Subtitle', 'Description', 'CategoryKey', 'EpisodeNumber') {
            $c = [System.StringComparer]::Ordinal.Compare($left.$name, $right.$name)
            if ($c -ne 0) { return $c }
        }
        $c = [int]$left.IsNew - [int]$right.IsNew
        if ($c -ne 0) { return $c }
        $c = [int]$left.IsLive - [int]$right.IsLive
        if ($c -ne 0) { return $c }
        return [int]$left.IsPremiere - [int]$right.IsPremiere
    }

    # The two small helpers the projection used before the compiled ones.
    function Get-OldPropertyValue {
        param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Default = $null)
        $property = if ($null -ne $Object) { $Object.PSObject.Properties[$Name] }
        if ($null -ne $property) { return $property.Value }
        return $Default
    }
    function Get-OldArrayValue {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return @() }
        return @($Value)
    }
}

Describe 'Compiled record comparer' {
    It 'sorts merge records exactly like the old script block, ties included' {
        $records = foreach ($id in 1..400) {
            $key = $script:Words[(Get-NextNumber 3)]
            [pscustomobject]@{
                Id          = $id
                Binding     = [pscustomobject]@{ BindingKey = $key }
                BindingKey  = [string]$key
                StartTicks  = [long](Get-NextNumber 3)
                EndTicks    = [long](Get-NextNumber 2)
                ContentKey  = $(if ((Get-NextNumber 6) -eq 0) { $null } else { $script:Words[(Get-NextNumber 4)] })
                EvidenceKey = $script:Words[(Get-NextNumber 9)]
            }
        }
        $old = [System.Collections.Generic.List[object]]::new($records)
        $new = [System.Collections.Generic.List[object]]::new($records)
        $old.Sort($script:OldMerge)
        $new.Sort((& $script:Module { Get-ChannelForgeRecordComparer -Key 'string:BindingKey', 'long:StartTicks', 'long:EndTicks', 'string:ContentKey', 'string:EvidenceKey' }))
        ($new.Id -join ',') | Should -BeExactly ($old.Id -join ',')
    }

    It 'sorts guide writer records exactly like the old script block, ties included' {
        $records = foreach ($id in 1..400) {
            [pscustomobject]@{
                Id            = $id
                BindingKey    = $script:Words[(Get-NextNumber 2)]
                StartTicks    = [long](Get-NextNumber 2)
                EndTicks      = [long](Get-NextNumber 2)
                Title         = $script:Words[(Get-NextNumber 3)]
                Subtitle      = $script:Words[(Get-NextNumber 3)]
                Description   = $script:Words[(Get-NextNumber 3)]
                CategoryKey   = $script:Words[(Get-NextNumber 3)]
                EpisodeNumber = $script:Words[(Get-NextNumber 2)]
                IsNew         = [bool](Get-NextNumber 2)
                IsLive        = [bool](Get-NextNumber 2)
                IsPremiere    = [bool](Get-NextNumber 2)
            }
        }
        $old = [System.Collections.Generic.List[object]]::new($records)
        $new = [System.Collections.Generic.List[object]]::new($records)
        $old.Sort($script:OldExport)
        $new.Sort((& $script:Module { Get-ChannelForgeRecordComparer -Key 'string:BindingKey', 'long:StartTicks', 'long:EndTicks', 'string:Title', 'string:Subtitle', 'string:Description', 'string:CategoryKey', 'string:EpisodeNumber', 'bool:IsNew', 'bool:IsLive', 'bool:IsPremiere' }))
        ($new.Id -join ',') | Should -BeExactly ($old.Id -join ',')
    }
}

Describe 'Compiled raw XMLTV projection helpers' {
    BeforeAll {
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        $script:Shapes = @(
            @{ Missing = $true }
            @{ Value = $null }
            @{ Value = 'x' }
            @{ Value = '' }
            @{ Value = @() }
            @{ Value = @('one') }
            @{ Value = @('a', 'b') }
            @{ Value = @($null) }
            @{ Value = @(, @('n1', 'n2')) }
            @{ Value = @(, @('only')) }
            @{ Value = [pscustomobject]@{ lang = 'en'; text = "q`"uote $emoji" } }
            @{ Value = @([pscustomobject]@{ lang = 'en'; text = 'one' }) }
            @{ Value = @([pscustomobject]@{ text = 'a' }, [pscustomobject]@{ text = 'b' }) }
            @{ Value = [ordered]@{ k = 'v' } }
            @{ Value = 5 }
            @{ Value = $true }
            @{ Value = [System.Collections.Generic.List[string]]::new([string[]]('l1', 'l2')) }
            @{ Value = "escapes \ `t $emoji" }
        )
        $script:Names = 'StartRaw', 'TitleNodes', 'Rating', 'PreviouslyShown', 'Credits', 'IconNodes'
    }

    It 'reads properties and arrays exactly as the old helper functions left them' {
        $checked = 0
        foreach ($shape in $script:Shapes) {
            foreach ($asHashtable in $false, $true) {
                $bag = [ordered]@{}
                foreach ($name in $script:Names) { if (-not $shape.Missing) { $bag[$name] = $shape.Value } }
                $occurrence = if ($asHashtable) { $bag } else { [pscustomobject]$bag }
                foreach ($name in $script:Names) {
                    foreach ($default in $null, $false, '') {
                        $old = [pscustomobject][ordered]@{ A = Get-OldPropertyValue $occurrence $name $default }
                        $new = [pscustomobject][ordered]@{ A = [ChannelForge.RawXmltvHelper]::Property($occurrence, $name, $default) }
                        [ChannelForge.CanonicalJsonWriter]::Write(@($new.A)) | Should -BeExactly ([ChannelForge.CanonicalJsonWriter]::Write(@($old.A)))
                        [ChannelForge.CanonicalJsonWriter]::Write($new) | Should -BeExactly ([ChannelForge.CanonicalJsonWriter]::Write($old))
                        $checked++
                    }
                    $old = [pscustomobject][ordered]@{ A = Get-OldArrayValue (Get-OldPropertyValue $occurrence $name @()) }
                    $new = [pscustomobject][ordered]@{ A = [ChannelForge.RawXmltvHelper]::ArrayValue($occurrence, $name) }
                    [ChannelForge.CanonicalJsonWriter]::Write(@($new.A)) | Should -BeExactly ([ChannelForge.CanonicalJsonWriter]::Write(@($old.A)))
                    [ChannelForge.CanonicalJsonWriter]::Write($new) | Should -BeExactly ([ChannelForge.CanonicalJsonWriter]::Write($old))
                    $checked++
                }
            }
        }
        $checked | Should -BeGreaterThan 200
    }

    It 'returns the default for a missing occurrence' {
        $old = [pscustomobject][ordered]@{ A = Get-OldPropertyValue $null 'x' 'fallback' }
        $new = [pscustomobject][ordered]@{ A = [ChannelForge.RawXmltvHelper]::Property($null, 'x', 'fallback') }
        $new.A | Should -BeExactly $old.A
    }

    It 'hashes a projection exactly like the domain hash of its properties' {
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        $projections = foreach ($shape in $script:Shapes) {
            if ($shape.Missing) { continue }
            [pscustomobject][ordered]@{
                Version                     = 'blocker-2-contract/v7'
                StructuralOccurrenceOrdinal = 7
                RawProgrammeChannelId       = "chan $emoji"
                TitleNodes                  = $shape.Value
                Credits                     = $shape.Value
                RawProgrammeDigest          = 'ignored'
                RawXMLTVOccurrenceDigest    = 'ignored'
            }
        }
        foreach ($projection in $projections) {
            $inputObject = [ordered]@{}
            foreach ($property in @($projection.PSObject.Properties)) {
                if ($property.Name -notin @('StructuralOccurrenceOrdinal', 'RawXMLTVOccurrenceDigest', 'RawProgrammeDigest')) { $inputObject[$property.Name] = $property.Value }
            }
            $expected = & $script:Module { param($d, $i) Get-ChannelForgeDomainHash -Domain $d -InputObject $i } 'raw-programme/v2' $inputObject
            [ChannelForge.RawXmltvHelper]::Compute([psobject]$projection, 'raw-programme/v2') | Should -BeExactly $expected
        }
    }
}
