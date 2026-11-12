function Resolve-ChannelForgeGuideChoices {
    # Pure decision step for channels whose guide match needs a choice.
    # Held: objects with EntryId, Key (Get-ChannelForgeChannelKey), Name, GroupId (the shared guide ID).
    # Decision: records from channel-decisions.json. GuideId: guide IDs that exist exactly once in the guide.
    # Returns one outcome per held entry. Resolved=$false means no usable decision: a strict run
    # stops on it, a normal run keeps the channel without a guide (the default).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Held,
        [AllowEmptyCollection()][object[]]$Decision = @(),
        [AllowEmptyCollection()][string[]]$GuideId = @()
    )

    $byKey = @{}
    foreach ($record in @($Decision)) { $byKey[[string]$record.key] = $record }
    $exists = [System.Collections.Generic.HashSet[string]]::new([string[]]@($GuideId), [System.StringComparer]::Ordinal)
    $outcomes = [System.Collections.Generic.List[object]]::new()

    foreach ($group in @($Held | Group-Object -Property GroupId -CaseSensitive)) {
        # A shared ID is published only when every channel in the group has a ShareOnPurpose record.
        $shared = $true
        foreach ($key in @($group.Group | ForEach-Object { [string]$_.Key } | Select-Object -Unique)) {
            $record = $byKey[$key]
            if ($null -eq $record -or [string]$record.choice -cne 'ShareOnPurpose' -or [string]$record.guideId -cne [string]$group.Name) { $shared = $false }
        }

        foreach ($member in @($group.Group)) {
            $record = $byKey[[string]$member.Key]
            $choice = 'KeepWithoutGuide'; $guide = $null; $reason = $null; $resolved = $true
            if ($shared) {
                if ($exists.Contains([string]$group.Name)) { $choice = 'ShareOnPurpose'; $guide = [string]$group.Name }
                else { $resolved = $false; $reason = 'the shared guide ID is not in the guide' }
            }
            elseif ($null -eq $record) { $resolved = $false; $reason = 'no saved choice' }
            elseif ([string]$record.choice -ceq 'OwnPlaceholder') {
                $choice = 'OwnPlaceholder'; $guide = 'ChannelForge-' + ([string]$member.Key).Substring(0, 32)
            }
            elseif ([string]$record.choice -ceq 'BindTrueMatch') {
                if ($exists.Contains([string]$record.guideId)) { $choice = 'BindTrueMatch'; $guide = [string]$record.guideId }
                else { $resolved = $false; $reason = 'the guide ID named in the decisions file is not in the guide' }
            }
            elseif ([string]$record.choice -ceq 'ShareOnPurpose') {
                $resolved = $false; $reason = 'a shared guide needs a ShareOnPurpose record for every channel in its group'
            }
            [void]$outcomes.Add([pscustomobject][ordered]@{
                    EntryId   = [string]$member.EntryId
                    Key       = [string]$member.Key
                    Name      = [string]$member.Name
                    GroupId   = [string]$group.Name
                    Choice    = $choice
                    Guide     = $guide
                    Resolved  = $resolved
                    HasRecord = ($null -ne $record)
                    Reason    = $reason
                })
        }
    }
    return [pscustomobject][ordered]@{ Outcomes = @($outcomes.ToArray()) }
}
