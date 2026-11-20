function Get-ChannelForgeCategoryFromText {
    # Text in, one decision out. One category matches: Category is its name.
    # None match: Category is null. Two or more match: Category is null, Review is
    # true and Candidates lists the names. A name that is already set always wins.
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text = '',
        [AllowEmptyString()][string]$Existing = '',
        [string]$DataPath = (Join-Path $PSScriptRoot '..\..\..\data\rules\categories.json')
    )

    function New-Result([object]$Category, [bool]$Review, [string[]]$Candidates) {
        [pscustomobject][ordered]@{ Category = $Category; Review = $Review; Candidates = @($Candidates) }
    }

    if (-not [string]::IsNullOrWhiteSpace($Existing)) { return New-Result $Existing $false @() }

    $document = [System.IO.File]::ReadAllText($DataPath) | ConvertFrom-Json
    $registry = @($document.categories | ForEach-Object {
            [pscustomobject]@{ Key = [string]$_.name; Aliases = @($_.match) }
        })
    $hits = @(Find-ChannelForgeCategoryWord -Text $Text -Registry $registry -Property Aliases | ForEach-Object { $_.Key })
    if ($hits.Count -eq 1) { return New-Result $hits[0] $false @($hits) }
    if ($hits.Count -gt 1) { return New-Result $null $true @($hits) }
    return New-Result $null $false @()
}
