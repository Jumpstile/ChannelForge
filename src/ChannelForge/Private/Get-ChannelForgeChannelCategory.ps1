function Find-ChannelForgeCategoryWord {
    # One hit per registry entry whose words (Aliases or NameTokens) appear in the text
    # as whole words, ignoring case. Entries without the property are skipped.
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text = '',
        [Parameter(Mandatory)][object[]]$Registry,
        [Parameter(Mandatory)][ValidateSet('Aliases', 'NameTokens')][string]$Property
    )

    foreach ($entry in $Registry) {
        $words = $entry.PSObject.Properties[$Property]
        if ($null -eq $words) { continue }
        foreach ($word in @($words.Value)) {
            if ($Text -match ('(?i)(?<![\p{L}\p{N}])' + [regex]::Escape([string]$word) + '(?![\p{L}\p{N}])')) {
                [pscustomobject][ordered]@{ Key = [string]$entry.Key; Word = [string]$word }
                break
            }
        }
    }
}

function Get-ChannelForgeChannelCategory {
    # One channel in, one decision out. No file access. The rules and their order are
    # in docs\planning\CATEGORY-QUALITY-DESIGN-NOTE.md. Nothing here guesses.
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Name = '',
        [AllowEmptyString()][string]$ProviderGroup = '',
        [Parameter(Mandatory)][string]$Key,
        [hashtable]$Override = @{},
        [object[]]$Registry = @(Get-ChannelForgeOneGuideCategoryRegistry)
    )

    function New-Decision([object]$Category, [string]$Confidence, [string]$Decision, [string]$Reason) {
        [pscustomobject][ordered]@{ Category = $Category; Confidence = $Confidence; Decision = $Decision; Reason = $Reason }
    }

    if ($Override.ContainsKey($Key)) {
        return New-Decision ([string]$Override[$Key]) 'high' 'override' 'Set by you with Set-ChannelForgeCategoryOverride.'
    }

    $nameHits = @(Find-ChannelForgeCategoryWord -Text $Name -Registry $Registry -Property NameTokens)
    $groupHits = @(Find-ChannelForgeCategoryWord -Text $ProviderGroup -Registry $Registry -Property Aliases)
    $groupSpecific = @($groupHits | Where-Object { $_.Key -ne 'other-sports' })
    $isGeneric = $groupHits.Count -gt $groupSpecific.Count
    $keys = @(@($nameHits) + $groupSpecific | ForEach-Object { $_.Key } | Select-Object -Unique)

    if ($keys.Count -gt 1) {
        $parts = @($nameHits | ForEach-Object { "name has `"$($_.Word)`" ($($_.Key))" }) +
            @($groupSpecific | ForEach-Object { "provider group has `"$($_.Word)`" ($($_.Key))" })
        return New-Decision $null 'none' 'conflict' ("Evidence points to more than one category: $($parts -join '; ').")
    }
    if ($keys.Count -eq 1) {
        $category = $keys[0]
        $nameHit = @($nameHits | Where-Object { $_.Key -eq $category }) | Select-Object -First 1
        $groupHit = @($groupSpecific | Where-Object { $_.Key -eq $category }) | Select-Object -First 1
        if ($nameHit -and ($groupHit -or $isGeneric)) {
            $groupText = if ($groupHit) { "provider group `"$ProviderGroup`" agrees" } else { "provider group `"$ProviderGroup`" is generic" }
            return New-Decision $category 'high' 'name-and-group' "Name contains `"$($nameHit.Word)`"; $groupText."
        }
        if ($nameHit) {
            return New-Decision $category 'medium' 'name' "Name contains `"$($nameHit.Word)`"; the provider group adds nothing."
        }
        return New-Decision $category 'medium' 'group' "Provider group `"$ProviderGroup`" means $category; the name adds nothing."
    }
    if ($isGeneric) {
        return New-Decision 'other-sports' 'medium' 'group' "Provider group `"$ProviderGroup`" is generic; the name names no sport."
    }
    return New-Decision $null 'none' 'no-rule' 'No category word in the name or the provider group.'
}
