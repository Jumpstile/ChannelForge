function New-ChannelForgeBuildContext {
    [CmdletBinding()]
    param(
        [string]$SourceDirectory = (Get-Location).Path
    )

    # BuildContext is the central state object for a ChannelForge build.
    # Every engine receives this object and adds its results to it.
    $context = [BuildContext]::new()
    $context.SourceDirectory = $SourceDirectory

    return $context
}