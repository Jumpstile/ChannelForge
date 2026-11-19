function Get-ChannelForgeWebSourceRemoveResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$BodyBytes,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [string]$ContentType = 'application/json'
    )

    if ([string]::IsNullOrWhiteSpace($ContentType) -or $ContentType.Split(';', 2)[0].Trim().ToLowerInvariant() -ne 'application/json') {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 415 -ErrorCode 'unsupported-content-type' -Message 'The remove request must use application/json.' -Headers $Headers
    }
    $label = $null; $kind = $null
    try {
        $request = [Text.UTF8Encoding]::new($false, $true).GetString($BodyBytes) | ConvertFrom-Json -ErrorAction Stop
        $names = @($request.PSObject.Properties.Name)
        if ($names.Count -ne 2 -or 'Label' -notin $names -or 'Kind' -notin $names) { throw 'invalid-request' }
        $label = $request.Label; $kind = $request.Kind
        if ($label -isnot [string] -or [string]::IsNullOrWhiteSpace($label) -or $kind -isnot [string] -or $kind -cnotin @('M3U', 'XMLTV')) { throw 'invalid-request' }
    }
    catch { return New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'invalid-request' -Message 'The remove request is invalid.' -Headers $Headers }

    try {
        $removed = Remove-ChannelForgeSourceSetSource -Label $label -Kind $kind -RepositoryRoot $RepositoryRoot -WarningAction SilentlyContinue
    }
    catch {
        # Fixed text only. The engine message can carry paths, so it is never sent to the browser.
        $text = [string]$_.Exception.Message
        if ($text -like '*last playlist*') {
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 409 -ErrorCode 'last-playlist' -Message 'This is your only playlist, so it cannot be removed. Nothing was changed.' -Headers $Headers
        }
        if ($text -like '*no saved source matches*' -or $text -like '*more than one saved source*') {
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 409 -ErrorCode 'source-not-found' -Message 'That source could not be found. Nothing was changed.' -Headers $Headers
        }
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 422 -ErrorCode 'remove-failed' -Message 'The source could not be removed. Your saved sources were not changed.' -Headers $Headers
    }
    $body = [ordered]@{ Version = 'source-remove/v1'; Status = 'REMOVED'; Kind = [string]$removed.Kind; Label = [string]$removed.Label } | ConvertTo-Json -Compress
    return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body $body -Headers $Headers
}
