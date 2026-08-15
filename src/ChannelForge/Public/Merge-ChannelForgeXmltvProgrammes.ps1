function Merge-ChannelForgeXmltvProgrammes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object[]]$Programme
    )

    if (@($Programme).Count -eq 0) {
        throw 'At least one Programme domain object is required.'
    }

    function Get-ProgrammeContentKey {
        param(
            [Parameter(Mandatory)]
            [Programme]$Value
        )

        $categories = [System.Collections.Generic.List[string]]::new()
        foreach ($category in @($Value.Categories)) {
            if ($null -ne $category -and -not [string]::IsNullOrWhiteSpace([string]$category)) {
                $categories.Add(([string]$category).Trim())
            }
        }
        $categories.Sort([System.StringComparer]::Ordinal)

        $content = [ordered]@{
            StartUtcTicks = $Value.Start.ToUniversalTime().Ticks
            EndUtcTicks   = $Value.End.ToUniversalTime().Ticks
            Title         = $Value.Title
            Subtitle      = $Value.Subtitle
            Description   = $Value.Description
            Categories    = @($categories.ToArray())
            EpisodeNumber = $Value.EpisodeNumber
            IsNew         = $Value.IsNew
            IsLive        = $Value.IsLive
            IsPremiere    = $Value.IsPremiere
        }

        return (ConvertTo-Json -InputObject $content -Depth 5 -Compress)
    }

    function Get-ProgrammeEvidenceKey {
        param(
            [object]$Evidence
        )

        if ($null -eq $Evidence) {
            return ''
        }

        $propertyNames = [System.Collections.Generic.List[string]]::new()
        foreach ($property in @($Evidence.PSObject.Properties)) {
            $propertyNames.Add($property.Name)
        }
        $propertyNames.Sort([System.StringComparer]::Ordinal)

        $values = [ordered]@{}
        foreach ($propertyName in $propertyNames) {
            $values[$propertyName] = $Evidence.$propertyName
        }

        return (ConvertTo-Json -InputObject $values -Depth 10 -Compress)
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($value in @($Programme)) {
        $binding = Resolve-ChannelForgeProgrammeBinding -Programme $value
        $programmeValue = [Programme]$value
        $records.Add([pscustomobject]@{
            Programme   = $programmeValue
            Binding     = $binding
            ContentKey  = Get-ProgrammeContentKey -Value $programmeValue
            EvidenceKey = Get-ProgrammeEvidenceKey -Evidence $programmeValue.Evidence
            StartTicks  = $programmeValue.Start.ToUniversalTime().Ticks
            EndTicks    = $programmeValue.End.ToUniversalTime().Ticks
        })
    }

    $recordComparison = [System.Comparison[object]]{
        param($left, $right)

        $comparison = [System.StringComparer]::Ordinal.Compare(
            [string]$left.Binding.BindingKey,
            [string]$right.Binding.BindingKey)
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = if ($left.StartTicks -lt $right.StartTicks) { -1 } elseif ($left.StartTicks -gt $right.StartTicks) { 1 } else { 0 }
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = if ($left.EndTicks -lt $right.EndTicks) { -1 } elseif ($left.EndTicks -gt $right.EndTicks) { 1 } else { 0 }
        if ($comparison -ne 0) {
            return $comparison
        }

        $comparison = [System.StringComparer]::Ordinal.Compare(
            [string]$left.ContentKey,
            [string]$right.ContentKey)
        if ($comparison -ne 0) {
            return $comparison
        }

        return [System.StringComparer]::Ordinal.Compare(
            [string]$left.EvidenceKey,
            [string]$right.EvidenceKey)
    }
    $records.Sort($recordComparison)

    $orderedBindings = [System.Collections.Generic.List[ProgrammeChannelBinding]]::new()
    $seenBindingKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $intervalGroups = [System.Collections.Generic.List[object]]::new()
    $currentInterval = $null

    foreach ($record in $records) {
        if ($seenBindingKeys.Add($record.Binding.BindingKey)) {
            $orderedBindings.Add($record.Binding)
        }

        if ($null -eq $currentInterval -or
            -not [string]::Equals($currentInterval.BindingKey, $record.Binding.BindingKey, [System.StringComparison]::Ordinal) -or
            $currentInterval.StartTicks -ne $record.StartTicks -or
            $currentInterval.EndTicks -ne $record.EndTicks) {
            $currentInterval = [pscustomobject]@{
                BindingKey = $record.Binding.BindingKey
                Binding    = $record.Binding
                StartTicks = $record.StartTicks
                EndTicks   = $record.EndTicks
                Records    = [System.Collections.Generic.List[object]]::new()
            }
            $intervalGroups.Add($currentInterval)
        }

        $currentInterval.Records.Add($record)
    }

    $boundProgrammes = [System.Collections.Generic.List[object]]::new()
    $duplicates = [System.Collections.Generic.List[object]]::new()
    $conflicts = [System.Collections.Generic.List[object]]::new()

    foreach ($interval in $intervalGroups) {
        $exactGroups = [System.Collections.Generic.List[object]]::new()
        $currentExact = $null

        foreach ($record in $interval.Records) {
            if ($null -eq $currentExact -or
                -not [string]::Equals($currentExact.ContentKey, $record.ContentKey, [System.StringComparison]::Ordinal)) {
                $currentExact = [pscustomobject]@{
                    ContentKey = $record.ContentKey
                    Records    = [System.Collections.Generic.List[object]]::new()
                }
                $exactGroups.Add($currentExact)
            }

            $currentExact.Records.Add($record)
        }

        $alternatives = [System.Collections.Generic.List[object]]::new()
        foreach ($exact in $exactGroups) {
            $contributors = @($exact.Records | ForEach-Object { $_.Programme })
            $evidence = @($contributors | ForEach-Object { $_.Evidence } | Where-Object { $null -ne $_ })
            $status = if ($contributors.Count -gt 1) { 'DuplicateMerged' } else { 'Unique' }

            $alternative = [pscustomobject][ordered]@{
                Programme    = $contributors[0]
                Binding      = $interval.Binding
                Contributors = $contributors
                Evidence     = $evidence
                Status       = $status
                ConflictKey  = ''
            }
            $alternatives.Add($alternative)

            if ($contributors.Count -gt 1) {
                $duplicates.Add([pscustomobject][ordered]@{
                    Binding      = $interval.Binding
                    Programme    = $contributors[0]
                    Contributors = $contributors
                    Evidence     = $evidence
                    Status       = 'DuplicateMerged'
                })
            }
        }

        if ($alternatives.Count -gt 1) {
            $conflictKey = '{0}|{1}|{2}' -f $interval.BindingKey, $interval.StartTicks, $interval.EndTicks
            foreach ($alternative in $alternatives) {
                $alternative.Status = 'Conflict'
                $alternative.ConflictKey = $conflictKey
            }

            $conflictAlternatives = @(
                $alternatives | ForEach-Object {
                    [pscustomobject][ordered]@{
                        Programme    = $_.Programme
                        Contributors = $_.Contributors
                        Evidence     = $_.Evidence
                        Status       = 'Conflict'
                    }
                }
            )
            $conflicts.Add([pscustomobject][ordered]@{
                Binding      = $interval.Binding
                StartUtc     = $alternatives[0].Programme.Start.ToUniversalTime()
                EndUtc       = $alternatives[0].Programme.End.ToUniversalTime()
                Alternatives = $conflictAlternatives
                ConflictKey  = $conflictKey
                Reason       = 'Programme facts differ for the same source-scoped channel and time interval.'
                Status       = 'NeedsReview'
            })
        }

        foreach ($alternative in $alternatives) {
            $boundProgrammes.Add($alternative)
        }
    }

    $boundArray = @($boundProgrammes.ToArray())
    return [pscustomobject][ordered]@{
        Bindings            = @($orderedBindings.ToArray())
        Programmes          = $boundArray
        BoundProgrammes     = $boundArray
        Duplicates          = @($duplicates.ToArray())
        Conflicts           = @($conflicts.ToArray())
        ProgrammeCount      = $boundArray.Count
        DuplicateGroupCount = $duplicates.Count
        ConflictCount       = $conflicts.Count
        HasConflicts        = ($conflicts.Count -gt 0)
    }
}
