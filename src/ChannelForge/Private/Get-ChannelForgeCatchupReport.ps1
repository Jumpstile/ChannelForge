function Get-ChannelForgeCatchupReport {
    <#
    .SYNOPSIS
    Report-only catch-up summary, one row per candidate stream.

    .DESCRIPTION
    Rows come from Get-ChannelForgeCatchupShape. Nothing is written into M3U or
    XMLTV output. XMLTV history never proves catch-up works, so every row says so.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.TextReader]$Reader
    )

    foreach ($row in @(Get-ChannelForgeCatchupShape -Reader $Reader)) {
        [pscustomobject][ordered]@{
            Ordinal            = $row.Ordinal
            Shape              = $row.Shape
            Family             = $row.Family
            DeclaredDays       = $row.DeclaredDays
            EvidenceSource     = if ($row.Shape -eq 'none') { 'none' } else { 'm3u-attributes' }
            XmltvHistoryIsProof = $false
        }
    }
}
