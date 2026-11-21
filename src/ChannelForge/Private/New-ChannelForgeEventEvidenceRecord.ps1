function New-ChannelForgeEventEvidenceRecord {
    # The one evidence record every event source adapter returns. Facts only; Time is $null when the source has no start time.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('game', 'session', 'race', 'card', 'episode', 'special')][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Date,
        [string]$Time,
        [string]$Venue,
        [string]$City,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$License,
        [Parameter(Mandatory)][string]$Attribution,
        [Parameter(Mandatory)][string]$FetchedAt,
        [Parameter(Mandatory)][string]$Id,
        [string]$Revision
    )

    $orNull = { param([string]$Text) if ([string]::IsNullOrWhiteSpace($Text)) { $null } else { $Text } }
    [pscustomobject]@{
        Id = $Id; Kind = $Kind; Name = $Name; Date = $Date; Time = (& $orNull $Time); Venue = (& $orNull $Venue); City = (& $orNull $City)
        Source = $Source; License = $License; Attribution = $Attribution; FetchedAt = $FetchedAt; Revision = (& $orNull $Revision)
    }
}
