function Export-ChannelForgeXmltv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$MergeResult,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$AllowedRoot
    )

    try {
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        throw "XMLTV output path is invalid: $Path"
    }

    Assert-ChannelForgeWritePath -Path $resolvedPath -AllowedRoot $AllowedRoot
    Assert-ChannelForgePathExists -Path $AllowedRoot -PathType Container -Description 'XMLTV output root'

    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        throw "XMLTV output path is a directory: $resolvedPath"
    }

    $parent = Split-Path -Parent $resolvedPath
    Assert-ChannelForgePathExists -Path $parent -PathType Container -Description 'XMLTV output parent directory'

    $bytes = ConvertTo-ChannelForgeXmltvBytes -MergeResult $MergeResult
    [System.IO.File]::WriteAllBytes($resolvedPath, [byte[]]$bytes)
}
