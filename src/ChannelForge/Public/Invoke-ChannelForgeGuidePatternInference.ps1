function Invoke-ChannelForgeGuidePatternInference {
    [CmdletBinding(DefaultParameterSetName = 'Examples')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Examples', Position = 0)]
        [AllowEmptyString()]
        [ValidateCount(1, 50)]
        [string[]]$Examples,

        [Parameter(Mandatory, ParameterSetName = 'Evidence', Position = 0)]
        [AllowEmptyString()]
        [ValidateCount(1, 50)]
        [GuideEvidenceRecord[]]$Evidence,
        [Parameter(ParameterSetName = 'Examples')]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
        [string]$SourceId = 'beginner-examples',

        [Parameter(ParameterSetName = 'Examples')]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._ -]{0,63}$')]
        [string]$SourceFamily = 'beginner-examples',

        [Parameter(ParameterSetName = 'Examples')]
        [ValidateSet('Authoritative', 'Independent', 'Mirror', 'Unknown')]
        [string]$SourceRelationship = 'Unknown',

        [Parameter(ParameterSetName = 'Examples')]
        [string]$Group = '',

        [ValidateSet('Fight', 'PPV', 'TemporaryEvent', 'League', 'SingleTeam', 'StreamingEvent', 'Sports', 'Other', 'Unknown')]
        [string]$EventType = 'Unknown',

        [string]$League = '',
        [string]$Sport = '',

        [ValidateSet('DisplayName', 'TvgName', 'OriginalName')]
        [string]$InputField = 'DisplayName',

        [AllowNull()]
        [System.Collections.IDictionary]$TimezoneMap = @{},

        [AllowEmptyString()]
        [string]$DefaultTimezone = '',

        [AllowNull()]
        [Nullable[datetimeoffset]]$ReferenceInstantUtc,

        [ValidateSet('MonthFirst', 'DayFirst')]
        [string]$DateOrder = 'MonthFirst',

        [ValidateRange(2, 50)]
        [int]$MinimumExamples = 3,

        [AllowNull()]
        [object]$ExistingRule
    )

    $patternExamples = [System.Collections.Generic.List[GuidePatternExample]]::new()
    $safeDefaultTimezone = ConvertTo-ChannelForgeGuidePatternSafeText -Value $DefaultTimezone
    if ($PSCmdlet.ParameterSetName -eq 'Examples') {
        for ($index = 0; $index -lt $Examples.Count; $index++) {
            $example = New-ChannelForgeGuidePatternExample `
                -Ordinal ($index + 1) `
                -Text $Examples[$index] `
                -InputField $InputField `
                -SourceId $SourceId `
                -SourceFamily $SourceFamily `
                -SourceRelationship $SourceRelationship `
                -Group $Group `
                -EventType $EventType `
                -League $League `
                -Sport $Sport
            [void]$patternExamples.Add($example)
        }
    }
    else {
        for ($index = 0; $index -lt $Evidence.Count; $index++) {
            $record = $Evidence[$index]
            $text = ''
            switch ($InputField) {
                'DisplayName' {
                    $text = if (-not [string]::IsNullOrWhiteSpace($record.DisplayName)) { $record.DisplayName } else { $record.Title }
                }
                'TvgName' {
                    if ($null -ne $record.PSObject.Properties['TvgName']) { $text = [string]$record.TvgName }
                    if ([string]::IsNullOrWhiteSpace($text)) { $text = $record.DisplayName }
                    if ([string]::IsNullOrWhiteSpace($text)) { $text = $record.Title }
                }
                'OriginalName' {
                    if ($null -ne $record.PSObject.Properties['OriginalName']) { $text = [string]$record.OriginalName }
                    if ([string]::IsNullOrWhiteSpace($text)) { $text = $record.DisplayName }
                    if ([string]::IsNullOrWhiteSpace($text)) { $text = $record.Title }
                }
            }

            $recordEventType = if ($record.EventType -in @('Fight', 'PPV', 'TemporaryEvent', 'League', 'SingleTeam', 'StreamingEvent', 'Sports', 'Other', 'Unknown')) { $record.EventType } else { 'Unknown' }
            $recordEventStatus = if ($record.EventStatus -in @('Scheduled', 'Live', 'Postponed', 'Cancelled', 'Rescheduled', 'Delayed', 'Completed', 'Idle', 'Unknown')) { $record.EventStatus } else { 'Unknown' }
            $recordRelationship = if ($record.SourceRelationship -in @('Authoritative', 'Independent', 'Mirror', 'Unknown')) { $record.SourceRelationship } else { 'Unknown' }
            $example = New-ChannelForgeGuidePatternExample `
                -Ordinal ($index + 1) `
                -Text $text `
                -InputField $InputField `
                -SourceId ([string]$record.SourceId) `
                -SourceFamily ([string]$record.SourceFamily) `
                -EvidenceType ([string]$record.EvidenceType) `
                -SourceRelationship $recordRelationship `
                -Group ([string]$record.Group) `
                -EventType $recordEventType `
                -EventStatus $recordEventStatus `
                -EvidenceReasonCodes ([string[]]$record.ReasonCodes) `
                -League ([string]$record.League) `
                -Sport ([string]$record.Sport) `
                -FreshnessState ([string]$record.FreshnessState) `
                -ConfidenceState ([string]$record.ConfidenceState) `
                -EvidenceStartUtc ([string]$record.StartUtc) `
                -EvidenceEndUtc ([string]$record.EndUtc) `
                -SourceTimezone ([string]$record.SourceTimezone) `
                -ChannelReference ([string]$record.ChannelReference) `
                -EvidenceTitle ([string]$record.Title) `
                -EvidenceHomeParticipant ([string]$record.HomeParticipant) `
                -EvidenceAwayParticipant ([string]$record.AwayParticipant) `
                -VolatileFacts @($record.VolatileFacts)
            [void]$patternExamples.Add($example)
        }
    }

    return Invoke-ChannelForgeGuidePatternAnalysis `
        -Examples @($patternExamples.ToArray()) `
        -TimezoneMap $TimezoneMap `
        -DefaultTimezone $safeDefaultTimezone `
        -ReferenceInstantUtc $ReferenceInstantUtc `
        -DateOrder $DateOrder `
        -MinimumExamples $MinimumExamples `
        -ExplicitEventType $EventType `
        -ExplicitLeague $League `
        -ExplicitSport $Sport `
        -ScopeGroup $Group `
        -ExistingRule $ExistingRule
}
