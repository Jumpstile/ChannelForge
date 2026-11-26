# Run the server at Windows start-up. Logic lives here; the scripts are thin.
# Every call that touches the system is a small wrapper function so tests can replace it.
# Nothing here writes or logs a password or a setup code.

$script:ServerTaskPath = '\ChannelForge\'
$script:ServerTaskName = 'ChannelForgeServer'
$script:ServerTaskMarker = 'ChannelForge server at start-up'
$script:ServerRecordName = 'server-install.json'

function Get-ChannelForgeServerAclPlan {
    # Administrators and SYSTEM: full control. LOCAL SERVICE: modify. Nobody else.
    @(
        @{ Sid = 'S-1-5-32-544'; Rights = 2032127 },
        @{ Sid = 'S-1-5-18'; Rights = 2032127 },
        @{ Sid = 'S-1-5-19'; Rights = 197055 }
    )
}

function Assert-ChannelForgeServerDataAccess {
    # Fails closed: throws when the folder is open to anyone beyond the plan, or inherits access.
    param([Parameter(Mandatory)][object[]]$Entry)
    $plan = @(Get-ChannelForgeServerAclPlan)
    $tooBroad = 'The data folder permissions are broader than ChannelForge allows. Nothing was installed. Fix the folder permissions or pick another -DataRoot.'
    foreach ($e in @($Entry | Where-Object { $_.Type -eq 'Allow' })) {
        $rule = $plan | Where-Object { $_.Sid -eq $e.Sid }
        if ($e.Inherited -or $null -eq $rule -or ([int]$e.Rights -band (-bnot [int]$rule.Rights)) -ne 0) { throw $tooBroad }
    }
    foreach ($rule in $plan) {
        $have = @($Entry | Where-Object { $_.Type -eq 'Allow' -and $_.Sid -eq $rule.Sid })
        if ($have.Count -eq 0 -or ([int]$have[0].Rights -band $rule.Rights) -ne $rule.Rights) { throw $tooBroad }
    }
}

function Assert-ChannelForgeServerProgramFolder {
    # The start-up account runs the ChannelForge scripts, so ordinary users must not be able to change them.
    param([Parameter(Mandatory)][object[]]$Entry)
    $writeBits = 852310
    $everyone = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')
    foreach ($e in @($Entry | Where-Object { $_.Type -eq 'Allow' -and $_.Sid -in $everyone })) {
        if (([int]$e.Rights -band $writeBits) -ne 0) {
            throw 'Ordinary users can change the files in the ChannelForge folder. The start-up account would run whatever they put there. Move the ChannelForge folder into the Program Files folder (or lock down its permissions) and run this again.'
        }
    }
}

function Get-ChannelForgeServerFirewallSpec {
    param([Parameter(Mandatory)][int]$Port)
    @{ DisplayName = "ChannelForge Server (TCP $Port)"; Port = $Port; Profile = 'Private,Domain' }
}

function Get-ChannelForgeServerTaskXml {
    param([string]$Root, [string]$Runtime, [string]$DataRoot, [int]$Port, [string]$BindAddress, [string]$AllowedHost)
    $launcher = Join-Path $Root 'scripts\Start-ChannelForgeServer.ps1'
    $arguments = "-NoProfile -File `"$launcher`" -ConfigRoot `"$DataRoot`" -Port $Port -BindAddress $BindAddress"
    if ($AllowedHost) { $arguments += " -AllowedHost $AllowedHost" }
    $esc = { param($v) [Security.SecurityElement]::Escape([string]$v) }
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>$script:ServerTaskMarker</Description></RegistrationInfo>
  <Triggers><BootTrigger><Enabled>true</Enabled></BootTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-19</UserId><LogonType>ServiceAccount</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>$(& $esc $Runtime)</Command><Arguments>$(& $esc $arguments)</Arguments><WorkingDirectory>$(& $esc $Root)</WorkingDirectory></Exec></Actions>
</Task>
"@
}

# ---- Wrappers around system calls (replaced in tests) ----
function Get-ChannelForgeServerRuntimePath { $c = Get-Command pwsh -ErrorAction SilentlyContinue; if ($c) { $c.Source } }
function Set-ChannelForgeServerDataAcl {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in (Get-ChannelForgeServerAclPlan)) {
        $sid = [Security.Principal.SecurityIdentifier]::new($r.Sid)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, [Security.AccessControl.FileSystemRights]$r.Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Get-ChannelForgeServerDataAccess {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($a in (Get-Acl -LiteralPath $Path).Access) {
        [pscustomobject]@{ Sid = $a.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value; Rights = [int]$a.FileSystemRights; Type = [string]$a.AccessControlType; Inherited = [bool]$a.IsInherited }
    }
}
function Get-ChannelForgeServerTaskInfo {
    $t = Get-ScheduledTask -TaskPath $script:ServerTaskPath -TaskName $script:ServerTaskName -ErrorAction SilentlyContinue
    if ($t) { [pscustomobject]@{ Description = [string]$t.Description } }
}
function Register-ChannelForgeServerTask { param([string]$Xml) Register-ScheduledTask -TaskPath $script:ServerTaskPath -TaskName $script:ServerTaskName -Xml $Xml -Force -ErrorAction Stop | Out-Null }
function Unregister-ChannelForgeServerTask {
    Stop-ScheduledTask -TaskPath $script:ServerTaskPath -TaskName $script:ServerTaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath $script:ServerTaskPath -TaskName $script:ServerTaskName -Confirm:$false -ErrorAction Stop
}
function Start-ChannelForgeServerTask { Start-ScheduledTask -TaskPath $script:ServerTaskPath -TaskName $script:ServerTaskName -ErrorAction Stop }
function Invoke-ChannelForgeNetsh {
    param([string[]]$Argument)
    $out = & netsh @Argument 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
}
function Add-ChannelForgeServerFirewallRule {
    param([hashtable]$Spec)
    New-NetFirewallRule -DisplayName $Spec.DisplayName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Spec.Port -Profile $Spec.Profile -ErrorAction Stop | Out-Null
}
function Remove-ChannelForgeServerFirewallRule {
    param([string]$DisplayName)
    Remove-NetFirewallRule -DisplayName $DisplayName -ErrorAction Stop
}
function Invoke-ChannelForgeServerFirstRun {
    # Runs the launcher in this window so the person sees the setup code. Enter stops it.
    param([string]$Runtime, [string]$Root, [string]$DataRoot, [int]$Port)
    $launcher = Join-Path $Root 'scripts\Start-ChannelForgeServer.ps1'
    $p = Start-Process -FilePath $Runtime -ArgumentList @('-NoProfile', '-File', "`"$launcher`"", '-ConfigRoot', "`"$DataRoot`"", '-Port', $Port) -NoNewWindow -PassThru
    try { Read-Host 'Open the first-run page, set your password, then press Enter here' | Out-Null }
    finally { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
}

function Get-ChannelForgeServerUrlAcl {
    param([string]$BindAddress, [int]$Port)
    $h = if ($BindAddress -in @('0.0.0.0', '::', '[::]')) { '+' } elseif ($BindAddress.Contains(':') -and -not $BindAddress.StartsWith('[')) { "[$BindAddress]" } else { $BindAddress }
    "http://${h}:$Port/"
}

function Remove-ChannelForgeServerNetwork {
    # Removes only what a record says install added.
    param([Parameter(Mandatory)][object]$Record)
    if ($Record.UrlAcl) {
        $r = Invoke-ChannelForgeNetsh -Argument @('http', 'delete', 'urlacl', "url=$($Record.UrlAcl)")
        if ($r.ExitCode -ne 0) { Write-Warning "The address reservation $($Record.UrlAcl) was not removed (it may already be gone)." }
    }
    if ($Record.FirewallRule) {
        try { Remove-ChannelForgeServerFirewallRule -DisplayName (Get-ChannelForgeServerFirewallSpec -Port $Record.Port).DisplayName }
        catch { Write-Warning 'The firewall rule was not removed (it may already be gone).' }
    }
}

function Read-ChannelForgeServerRecord {
    param([Parameter(Mandatory)][string]$DataRoot)
    $path = Join-Path $DataRoot $script:ServerRecordName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $r = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ([int]$r.Schema -ne 1 -or [int]$r.Port -lt 1024 -or [int]$r.Port -gt 65535) { return $null }
    if ($r.UrlAcl -and [string]$r.UrlAcl -notmatch '^http://[A-Za-z0-9.:\[\]+-]+/$') { return $null }
    $r
}

function Install-ChannelForgeServerTask {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidateRange(1024, 65535)][int]$Port = 47850,
        [string]$BindAddress = '127.0.0.1',
        [string]$AllowedHost = '',
        [Parameter(Mandatory)][string]$DataRoot
    )
    if (-not (Test-ChannelForgeElevated)) { throw 'This needs an administrator window. Open PowerShell as administrator and run it again.' }
    if ($BindAddress -notmatch '^[A-Za-z0-9.:\[\]-]+$' -or ($AllowedHost -and $AllowedHost -notmatch '^[A-Za-z0-9.:\[\]-]+$')) { throw 'The address or allowed host has characters that are not allowed.' }
    if ($Root -match '^[A-Za-z]:\\Users\\') { throw 'ChannelForge is in a user folder, which the start-up account cannot read. Move the ChannelForge folder into the Program Files folder and run this again.' }
    Assert-ChannelForgeServerProgramFolder -Entry @(Get-ChannelForgeServerDataAccess -Path $Root)
    $runtime = Get-ChannelForgeServerRuntimePath
    if (-not $runtime) { throw 'PowerShell 7 (pwsh) was not found. Install PowerShell 7 and run this again.' }
    if ($runtime -match '^[A-Za-z]:\\Users\\') { throw 'PowerShell 7 is installed in a user folder, which the start-up account cannot run. Install PowerShell 7 for all users and run this again.' }
    $ip = $null
    $bindHost = $BindAddress.Trim('[', ']')
    $network = -not ($bindHost -eq 'localhost' -or ([Net.IPAddress]::TryParse($bindHost, [ref]$ip) -and [Net.IPAddress]::IsLoopback($ip)))
    if ($network) {
        if (-not $AllowedHost) { throw 'Network access needs -AllowedHost, the name or address you will type in the browser.' }
        if ((Get-ChannelForgeStartGuard -Address $BindAddress -ConfigRoot $DataRoot).State -ne 'Ready') { throw 'Network access needs sign-in set up first. Install without -BindAddress, finish first-time setup, then run this again with -BindAddress.' }
    }
    $existing = Get-ChannelForgeServerTaskInfo
    if ($existing -and $existing.Description -ne $script:ServerTaskMarker) { throw 'A task with this name already exists and was not made by ChannelForge. Nothing was changed.' }
    if (-not $PSCmdlet.ShouldProcess($DataRoot, 'Install the ChannelForge server start-up task')) { return [pscustomobject]@{ Status = 'WhatIf' } }

    Set-ChannelForgeServerDataAcl -Path $DataRoot
    Assert-ChannelForgeServerDataAccess -Entry @(Get-ChannelForgeServerDataAccess -Path $DataRoot)
    if ((Read-ChannelForgeAdminPasswordFile -ConfigRoot $DataRoot).Status -eq 'Missing') {
        Invoke-ChannelForgeServerFirstRun -Runtime $runtime -Root $Root -DataRoot $DataRoot -Port $Port
    }
    if ((Read-ChannelForgeAdminPasswordFile -ConfigRoot $DataRoot).Status -ne 'Ok') { throw 'Sign-in is not set up, so the start-up task was not registered. Run this again and finish first-time setup.' }

    $old = Read-ChannelForgeServerRecord -DataRoot $DataRoot
    if ($old) { Remove-ChannelForgeServerNetwork -Record $old }
    $record = [ordered]@{ Schema = 1; Port = $Port; UrlAcl = $null; FirewallRule = $false }
    if ($network) {
        $acl = Get-ChannelForgeServerUrlAcl -BindAddress $BindAddress -Port $Port
        $r = Invoke-ChannelForgeNetsh -Argument @('http', 'add', 'urlacl', "url=$acl", 'user=NT AUTHORITY\LOCAL SERVICE')
        if ($r.ExitCode -ne 0) { throw 'The address could not be reserved for the start-up account. Nothing else was installed.' }
        $record.UrlAcl = $acl
        Add-ChannelForgeServerFirewallRule -Spec (Get-ChannelForgeServerFirewallSpec -Port $Port)
        $record.FirewallRule = $true
        Write-Warning 'This server speaks plain HTTP. Anyone on the network can read what you type. Put a reverse proxy with HTTPS in front of it.'
    }
    [IO.File]::WriteAllText((Join-Path $DataRoot $script:ServerRecordName), ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Register-ChannelForgeServerTask -Xml (Get-ChannelForgeServerTaskXml -Root $Root -Runtime $runtime -DataRoot $DataRoot -Port $Port -BindAddress $BindAddress -AllowedHost $AllowedHost)
    Start-ChannelForgeServerTask
    [pscustomobject]@{ Status = 'Installed'; Port = $Port; BindAddress = $BindAddress; DataRoot = $DataRoot }
}

function Uninstall-ChannelForgeServerTask {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$DataRoot, [switch]$RemoveData, [switch]$Force)
    if (-not (Test-ChannelForgeElevated)) { throw 'This needs an administrator window. Open PowerShell as administrator and run it again.' }
    $record = Read-ChannelForgeServerRecord -DataRoot $DataRoot
    if ($RemoveData -and -not $record) { throw 'This folder has no ChannelForge install record, so it will not be deleted. Nothing was changed.' }
    $existing = Get-ChannelForgeServerTaskInfo
    if ($existing -and $existing.Description -ne $script:ServerTaskMarker) { throw 'A task with this name exists but was not made by ChannelForge. Nothing was changed.' }
    if ($RemoveData -and -not $Force -and (Read-Host "Type DELETE to erase $DataRoot, including your password and settings") -cne 'DELETE') { throw 'Not confirmed. Nothing was changed.' }
    if (-not $PSCmdlet.ShouldProcess($DataRoot, 'Remove the ChannelForge server start-up task')) { return [pscustomobject]@{ Status = 'WhatIf' } }
    if ($existing) { Unregister-ChannelForgeServerTask }
    if ($record) { Remove-ChannelForgeServerNetwork -Record $record }
    if ($record -and -not $RemoveData) { Remove-Item -LiteralPath (Join-Path $DataRoot $script:ServerRecordName) -Force }
    if ($RemoveData) { Remove-Item -LiteralPath $DataRoot -Recurse -Force }
    [pscustomobject]@{ Status = 'Uninstalled'; DataKept = (-not $RemoveData) }
}
