function ConvertTo-ChannelForgeM3UEntryBytes {
    param([Parameter(Mandatory)][Channel]$Channel)
    $fields = @(
        @{ Name = 'tvg-id'; Value = $Channel.TvgId }
        @{ Name = 'tvg-name'; Value = $Channel.TvgName }
        @{ Name = 'tvg-logo'; Value = $Channel.Logo }
        @{ Name = 'tvg-chno'; Value = $Channel.AssignedNumber }
        @{ Name = 'group-title'; Value = $Channel.Group }
    )
    $attributes = [System.Collections.Generic.List[string]]::new()
    foreach ($field in $fields) {
        $value = ConvertTo-ChannelForgeSafeM3UText -Text $field.Value
        if ($value) { [void]$attributes.Add("$($field.Name)=`"$value`"") }
    }
    $attributeText = if ($attributes.Count -gt 0) { ' ' + ($attributes -join ' ') } else { '' }
    $text = "#EXTINF:-1$attributeText,$(ConvertTo-ChannelForgeSafeM3UText -Text $Channel.DisplayName)`n$(ConvertTo-ChannelForgeSafeM3UText -Text $Channel.Url)`n"
    [System.Text.UTF8Encoding]::new($false, $true).GetBytes($text)
}
