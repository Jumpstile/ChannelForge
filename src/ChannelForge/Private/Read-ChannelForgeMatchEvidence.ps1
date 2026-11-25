function Read-ChannelForgeMatchEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$GenerationId,
        [Parameter(Mandatory)][string]$AcceptedStateHash,
        [Parameter(Mandatory)][string]$AcceptedOutputManifestHash
    )

    # Reads state\accepted-evidence\<GenerationId>.json. Never writes, never throws.
    # Status is Missing, Ok or Corrupt (Corrupt includes "not for this lineup").
    $result = { param($status, $entries) [pscustomobject][ordered]@{ Status = $status; Entries = @($entries) } }
    try {
        if ($GenerationId -cnotmatch '^[0-9a-f]{64}$') { return & $result 'Corrupt' @() }
        $path = Join-Path (Join-Path (Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot).StateRoot 'accepted-evidence') "$GenerationId.json"
        if (-not [System.IO.File]::Exists($path)) { return & $result 'Missing' @() }
        if (([System.IO.FileInfo]::new($path)).Length -gt 32MB) { return & $result 'Corrupt' @() }
        $document = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($path)) | ConvertFrom-Json -ErrorAction Stop
        $entries = @($document.entries)
        if ($document.schemaVersion -cne 'match-evidence/v1' -or $document.generationId -cne $GenerationId -or
            $document.acceptedStateHash -cne $AcceptedStateHash -or $document.acceptedOutputManifestHash -cne $AcceptedOutputManifestHash -or
            $document.entryCount -ne $entries.Count) { return & $result 'Corrupt' @() }
        foreach ($entry in $entries) {
            foreach ($property in $entry.PSObject.Properties) {
                if ($property.Value -is [string] -and $property.Value.Length -gt 256) { return & $result 'Corrupt' @() }
            }
        }
        $projection = [ordered]@{}
        foreach ($property in $document.PSObject.Properties) { if ($property.Name -cne 'evidenceHash') { $projection[$property.Name] = $property.Value } }
        if ($document.evidenceHash -cne (Get-ChannelForgeDomainHash -Domain 'match-evidence/v1' -InputObject $projection)) { return & $result 'Corrupt' @() }
        return & $result 'Ok' $entries
    }
    catch { return & $result 'Corrupt' @() }
}
