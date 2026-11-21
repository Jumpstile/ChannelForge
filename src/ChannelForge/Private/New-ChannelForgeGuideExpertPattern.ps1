function New-ChannelForgeGuideExpertPattern {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Pattern
    )

    # Single compile path for expert regexes. Fails closed: any problem returns Valid = $false.
    $invalid = [pscustomobject][ordered]@{
        Valid = $false
        Regex = $null
        Hash = ''
        ReasonCodes = @('ExpertPatternInvalid')
    }
    if ([string]::IsNullOrWhiteSpace($Pattern) -or $Pattern.Length -gt 512) { return $invalid }

    try {
        $regex = [regex]::new(
            $Pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant,
            [TimeSpan]::FromMilliseconds(250))
    }
    catch {
        return $invalid
    }

    $allowedNames = @('identifier', 'ordinal', 'title', 'tz', 'date', 'time')
    $names = @($regex.GetGroupNames() | Where-Object { $_ -notmatch '^[0-9]+$' })
    if ($names -notcontains 'title') { return $invalid }
    if (@($names | Where-Object { $_ -cnotin $allowedNames }).Count -gt 0) { return $invalid }

    return [pscustomobject][ordered]@{
        Valid = $true
        Regex = $regex
        Hash = Get-ChannelForgeGuidePatternHash -Text $Pattern
        ReasonCodes = @()
    }
}
