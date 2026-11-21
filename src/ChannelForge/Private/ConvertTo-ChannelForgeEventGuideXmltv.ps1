function ConvertTo-ChannelForgeEventGuideXmltv {
    # Event guide delivery, slice 1. Turns the Channel rows of Get-ChannelForgeEventGuidePlan (Id, Name,
    # Blocks with UTC Start, Stop, Title) into a small XMLTV file that holds ONLY the event channels.
    # A separate output: it reads no lineup file and changes none (merged.xml, merged.m3u, manifest, hashes).
    # Returns UTF-8 bytes without a byte order mark (as one byte[] item). No event channel: an empty guide.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Channel
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $stampFormat = "yyyyMMddHHmmss '+0000'"
    $channelXml = [System.Text.StringBuilder]::new()
    $programmeXml = [System.Text.StringBuilder]::new()
    foreach ($item in @($Channel | Sort-Object { [string]$_.Id } -Unique)) {
        $id = [System.Security.SecurityElement]::Escape([string]$item.Id)
        $name = [System.Security.SecurityElement]::Escape((ConvertTo-ChannelForgeGuideSafeText -Value $item.Name -MaximumLength 200))
        [void]$channelXml.Append("  <channel id=`"$id`"><display-name>$name</display-name></channel>`n")
        foreach ($block in @($item.Blocks)) {
            $title = [System.Security.SecurityElement]::Escape([string]$block.Title)
            [void]$programmeXml.Append("  <programme start=`"$(([datetime]$block.Start).ToUniversalTime().ToString($stampFormat, $culture))`" stop=`"$(([datetime]$block.Stop).ToUniversalTime().ToString($stampFormat, $culture))`" channel=`"$id`"><title>$title</title></programme>`n")
        }
    }
    $text = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<tv>`n" + $channelXml.ToString() + $programmeXml.ToString() + "</tv>`n"
    return , [System.Text.UTF8Encoding]::new($false).GetBytes($text)
}
