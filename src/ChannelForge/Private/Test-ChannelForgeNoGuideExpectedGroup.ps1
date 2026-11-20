function Test-ChannelForgeNoGuideExpectedGroup {
    # True when a playlist group title is an adult or music group: no guide source exists for those channels.
    # A group that matches two categories (a review case) is not counted.
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Group = '')

    return (Get-ChannelForgeCategoryFromText -Text $Group).Category -in @('Adult', 'Music')
}
