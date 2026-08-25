function ConvertTo-ChannelForgeCandidateJson {
    param([Parameter(Mandatory)][object]$InputObject)
    return ConvertTo-ChannelForgeCanonicalJson -InputObject $InputObject
}

function Get-ChannelForgeCandidateDomainHash {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][byte[]]$Bytes)
    $prefix = [System.Text.Encoding]::ASCII.GetBytes($Domain + [char]0)
    $payload = [byte[]]::new($prefix.Length + $Bytes.Length)
    [System.Buffer]::BlockCopy($prefix, 0, $payload, 0, $prefix.Length)
    [System.Buffer]::BlockCopy($Bytes, 0, $payload, $prefix.Length, $Bytes.Length)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

function Get-ChannelForgeCandidateCanonicalHash {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][object]$InputObject)
    $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes((ConvertTo-ChannelForgeCandidateJson -InputObject $InputObject))
    return Get-ChannelForgeCandidateDomainHash -Domain $Domain -Bytes $bytes
}

function Invoke-ChannelForgeCandidateHook {
    param([Parameter(Mandatory)][string]$HookName, [string]$FaultHook = '')
    if ([string]::Equals($FaultHook, $HookName, [System.StringComparison]::Ordinal)) {
        throw "ChannelForge.TestFaultInjected:$HookName"
    }
}

function Write-ChannelForgeCandidateArtifact {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][string]$HookPrefix, [string]$FaultHook = '')
    Invoke-ChannelForgeCandidateHook -HookName "${HookPrefix}.Write" -FaultHook $FaultHook
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        Invoke-ChannelForgeCandidateHook -HookName "${HookPrefix}.Flush" -FaultHook $FaultHook
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    Invoke-ChannelForgeCandidateHook -HookName "${HookPrefix}.ReopenHash" -FaultHook $FaultHook
    $actual = [System.IO.File]::ReadAllBytes($Path)
    if ($actual.Length -ne $Bytes.Length -or -not [System.Linq.Enumerable]::SequenceEqual($actual, $Bytes)) { throw "Candidate artifact verification failed: $Path" }
    return $actual.Length
}

function Test-ChannelForgeCandidateNamespace {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$ManifestHash)
    $path = Join-Path $Directory 'manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $raw = [System.IO.File]::ReadAllBytes($path)
    $manifest = [System.Text.UTF8Encoding]::new($false, $true).GetString([byte[]]$raw) | ConvertFrom-Json
    return [string]$manifest.CandidateManifestHash -eq $ManifestHash
}
