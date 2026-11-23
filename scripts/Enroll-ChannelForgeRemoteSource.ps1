[CmdletBinding()]
param(
    [ValidateSet('M3U', 'XMLTV')][string]$Kind = 'M3U',
    [string]$Label,
    [switch]$DryRun,
    [switch]$SkipProbe,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$CredentialRoot
)

# Enrolls one remote source whose link carries a login. The link is typed at a no-echo prompt (never a parameter),
# stored encrypted by the secret store, and only the random ref and the host go into the source set.
# Everything printed or thrown here names the host only. Do not run this under Start-Transcript.
$ErrorActionPreference = 'Stop'
if (-not (Get-Module ChannelForge)) { Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/ChannelForge/ChannelForge.psd1') }
$module = Get-Module ChannelForge
$rootArgs = @{}
if ($PSBoundParameters.ContainsKey('CredentialRoot')) { $rootArgs.CredentialRoot = $CredentialRoot }

function ConvertTo-LinkText {
    # The only place the secure string becomes text. The unmanaged copy is cleared in finally.
    param([Parameter(Mandatory)][securestring]$Secure)
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally { if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }
}

function Invoke-LoginProbe {
    # One bounded probe through the existing reachability check. Observed holds a category only, never the link.
    param([Parameter(Mandatory)][string]$Link)
    $finding = & $module {
        param($Name, $Kind, $Url, $Root)
        Get-ChannelForgeSourceReachabilityFinding -Name $Name -Kind $Kind -Url $Url -RepositoryRoot $Root
    } $(if ($Label) { $Label } else { 'remote source' }) $Kind $Link $RepositoryRoot
    return [pscustomobject]@{ Passed = ($finding.Status -eq 'Pass'); Observed = [string]$finding.Observed }
}

function Remove-NewSecret {
    param([Parameter(Mandatory)][string]$RefId)
    $removed = & $module { param($RefId, $Args2) Remove-ChannelForgeSourceSecret -RefId $RefId @Args2 } $RefId $rootArgs
    return [bool]$removed.Success
}

$secure = Read-Host -Prompt 'Paste the full link (nothing will show)' -AsSecureString
$split = & $module { param($Link) Split-ChannelForgeSecretSourceLink -Link $Link } (ConvertTo-LinkText -Secure $secure)
if (-not $split.Succeeded) { throw "Link refused ($($split.FailureCategory)): $($split.Message) Nothing was saved." }
$displayHost = $split.DisplayHost

if ($DryRun) {
    $probe = Invoke-LoginProbe -Link $split.SecretLink
    Write-Host "Source: $displayHost/..."
    if ($probe.Passed) { Write-Host 'Login test: PASS. The provider answered and the first 4096 bytes were readable.' }
    else { Write-Host "Login test: FAIL. $($probe.Observed)" }
    Write-Host 'Not tested: the full download, and whether the whole account is active.'
    Write-Host 'Dry run: nothing was saved.'
    return
}

if ($SkipProbe) {
    Write-Warning "The login for $displayHost was not tested (-SkipProbe)."
}
else {
    $probe = Invoke-LoginProbe -Link $split.SecretLink
    if (-not $probe.Passed) { throw "Login test failed for $displayHost. $($probe.Observed) Nothing was saved." }
}

$saved = & $module { param($Secret, $Args2) Save-ChannelForgeSourceSecret -Secret $Secret @Args2 } $secure $rootArgs
if (-not $saved.Success) { throw "The login for $displayHost could not be saved ($($saved.Category)). Nothing was saved." }
$refId = [string]$saved.RefId

$check = & $module { param($RefId, $Args2) Read-ChannelForgeSourceSecret -RefId $RefId @Args2 } $refId $rootArgs
if (-not $check.Success) {
    $cleaned = Remove-NewSecret -RefId $refId
    throw "The saved login for $displayHost could not be read back ($($check.Category)). $(if ($cleaned) { 'The new login file was removed.' } else { 'The new login file could not be removed.' }) Nothing was enrolled."
}

try {
    & $module {
        param($Kind, $Ref, $DisplayHost, $Label, $Root)
        Add-ChannelForgeCredentialedSourceSetSource -Kind $Kind -CredentialRef $Ref -DisplayHost $DisplayHost -Label $Label -RepositoryRoot $Root
    } $Kind $refId $displayHost $Label $RepositoryRoot
}
catch {
    $cleaned = Remove-NewSecret -RefId $refId
    throw "The source record for $displayHost could not be written. $(if ($cleaned) { 'The new login file was removed.' } else { 'The new login file could not be removed.' }) Nothing was enrolled."
}

Write-Host "Enrolled $Kind source at $displayHost. The login is saved encrypted for this Windows user only."
