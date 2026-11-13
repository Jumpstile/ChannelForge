function New-ChannelForgeKnowledgeChangePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [datetimeoffset]$CreatedAtUtc = ([datetimeoffset]::UtcNow)
    )

    $state = Read-ChannelForgeKnowledgeState -RepositoryRoot $RepositoryRoot
    $plan = New-ChannelForgeKnowledgeChangePlanInternal -State $state -Actions $Actions -CreatedAtUtc $CreatedAtUtc
    $schemaPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\schemas\knowledge_change_plan.schema.json'))
    if (-not (Test-Json -Json (ConvertTo-ChannelForgeCanonicalJson -InputObject $plan) -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'FAIL_CLOSED: knowledge change plan schema validation failed.' }
    return $plan
}
