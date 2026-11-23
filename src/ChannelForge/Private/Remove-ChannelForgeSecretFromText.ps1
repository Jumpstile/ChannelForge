function Remove-ChannelForgeSecretFromText {
    # Scrubs error or exception text before it is shown or saved. Removes every known secret value, then replaces
    # any remaining web link with its host-only form. Use it wherever text from a credentialed source can reach a person.
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Text,
        [string[]]$Secret = @()
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $clean = $Text
    foreach ($value in @($Secret | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object Length -Descending)) {
        $clean = $clean.Replace($value, '[removed]')
    }
    return [regex]::Replace($clean, 'https?://[^\s''"<>]+', { param($m) Get-ChannelForgeRedactedSourceHost -Url $m.Value })
}
