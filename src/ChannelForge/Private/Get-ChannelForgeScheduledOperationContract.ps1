function Get-ChannelForgeScheduledOperationTaskContract {
    param(
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][object]$RootInfo,
        [Parameter(Mandatory)][string]$WrapperPath,
        [AllowNull()][string]$RuntimePath,
        [Parameter(Mandatory)][object]$PolicyInfo
    )
    $violations = [System.Collections.Generic.List[string]]::new()
    try {
        $document = [xml]$Xml
        $start = [string]$document.SelectSingleNode('//*[local-name()="CalendarTrigger"]/*[local-name()="StartBoundary"]').InnerText
        $trigger = $document.SelectSingleNode('//*[local-name()="CalendarTrigger"]')
        $action = $document.SelectSingleNode('//*[local-name()="Exec"]')
        $command = [string]$action.SelectSingleNode('./*[local-name()="Command"]').InnerText
        $arguments = [string]$action.SelectSingleNode('./*[local-name()="Arguments"]').InnerText
        $workingDirectory = [string]$action.SelectSingleNode('./*[local-name()="WorkingDirectory"]').InnerText
        $multipleInstances = [string]$document.SelectSingleNode('//*[local-name()="MultipleInstancesPolicy"]').InnerText
        $startWhenAvailable = [string]$document.SelectSingleNode('//*[local-name()="StartWhenAvailable"]').InnerText
        $logonType = [string]$document.SelectSingleNode('//*[local-name()="Principal"]/*[local-name()="LogonType"]').InnerText
        $runLevel = [string]$document.SelectSingleNode('//*[local-name()="Principal"]/*[local-name()="RunLevel"]').InnerText
        if ($start -notmatch 'Z$') { $violations.Add('StartBoundaryNotUtc') | Out-Null }
        if ($null -eq $trigger -or $null -eq $trigger.SelectSingleNode('./*[local-name()="ScheduleByDay"]/*[local-name()="DaysInterval"]') -or [string]$trigger.SelectSingleNode('./*[local-name()="ScheduleByDay"]/*[local-name()="DaysInterval"]').InnerText -ne '1') { $violations.Add('DailyTriggerInvalid') | Out-Null }
        if ($arguments -notmatch '-ScheduledInvocation' -or $arguments -notmatch [regex]::Escape($WrapperPath) -or $arguments -notmatch [regex]::Escape($RootInfo.FullPath)) { $violations.Add('ActionArgumentsInvalid') | Out-Null }
        if ($null -ne $RuntimePath -and $command -ne $RuntimePath) { $violations.Add('RuntimePathDrifted') | Out-Null }
        if ($workingDirectory -ne $RootInfo.FullPath) { $violations.Add('WorkingDirectoryDrifted') | Out-Null }
        if ($multipleInstances -ne 'IgnoreNew') { $violations.Add('MultipleInstancesPolicyInvalid') | Out-Null }
        if ($startWhenAvailable -ne 'false') { $violations.Add('StartWhenAvailableEnabled') | Out-Null }
        if ($logonType -ne 'InteractiveToken' -or $runLevel -ne 'LeastPrivilege') { $violations.Add('PrincipalInvalid') | Out-Null }
        foreach ($forbidden in @('RandomDelay', 'Repetition', 'RestartOnFailure', 'BootTrigger', 'LogonTrigger')) {
            if ($null -ne $document.SelectSingleNode(('//*[local-name()="' + $forbidden + '"]'))) { $violations.Add($forbidden + 'Present') | Out-Null }
        }
        if ($start -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { $violations.Add('StartBoundaryFormatInvalid') | Out-Null }
        else {
            $startTime = [datetimeoffset]::Parse($start, [Globalization.CultureInfo]::InvariantCulture)
            if ($startTime.Minute -ne ($PolicyInfo.AtMinutes % 60) -or $startTime.Hour -ne [Math]::Floor($PolicyInfo.AtMinutes / 60)) { $violations.Add('CadenceTimeDrifted') | Out-Null }
        }
        [pscustomobject][ordered]@{
            Compliant = $violations.Count -eq 0
            ViolationCodes = @($violations)
            StartBoundaryUtc = $start
            CommandName = [IO.Path]::GetFileName($command)
            WorkingDirectory = if ([string]::IsNullOrWhiteSpace($workingDirectory)) { $null } else { 'RepositoryRoot' }
            MultipleInstancesPolicy = $multipleInstances
            StartWhenAvailable = $startWhenAvailable
            PrincipalLogonType = $logonType
            PrincipalRunLevel = $runLevel
        }
    }
    catch {
        [pscustomobject][ordered]@{
            Compliant = $false
            ViolationCodes = @('TaskXmlInvalid')
            StartBoundaryUtc = $null
            CommandName = $null
            WorkingDirectory = $null
            MultipleInstancesPolicy = $null
            StartWhenAvailable = $null
            PrincipalLogonType = $null
            PrincipalRunLevel = $null
        }
    }
}
