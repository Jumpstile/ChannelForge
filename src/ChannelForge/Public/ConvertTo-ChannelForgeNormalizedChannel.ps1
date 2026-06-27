function ConvertTo-ChannelForgeNormalizedChannel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Channel]$Channel
    )

    process {
        # Normalize the channel name without changing the original provider value.
        # OriginalName remains untouched for audit/debugging.
        $Channel.NormalizedName = Normalize-ChannelForgeName -Name $Channel.OriginalName
        return $Channel
    }
}