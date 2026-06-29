param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

# Schemas are always loaded from this script's own location, never from
# -Root. -Root only redirects where data/ is read from (so tests can point
# it at fixture data); the schema contracts themselves are not a
# per-deployment concern.
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$schemasDir = Join-Path $ScriptRoot 'schemas'
$dataDir = Join-Path $Root 'data'

# Deterministic local validation entry point for every tracked
# source-of-truth JSON file against its schema (see issue #3). CI (issue #4)
# can wire this in directly, e.g. `pwsh -File scripts/Validate-ConfigSchemas.ps1`.
# An unhandled throw here makes pwsh exit non-zero, the same way every
# other script under scripts/ fails. Until #4 wires it in, run this manually
# or rely on tests/unit/ConfigSchemas.Tests.ps1, which exercises the same
# schemas with positive and negative fixtures.
#
# Add a new entry here whenever a new schema is added under schemas/.
$targets = @(
    @{ Path = Join-Path $dataDir 'providers\mybunny.json'; Schema = Join-Path $schemasDir 'provider.schema.json' }
    @{ Path = Join-Path $dataDir 'providers\provider.example.json'; Schema = Join-Path $schemasDir 'provider.schema.json' }
    @{ Path = Join-Path $dataDir 'epg\epg_sources.json'; Schema = Join-Path $schemasDir 'epg_sources.schema.json' }
    @{ Path = Join-Path $dataDir 'epg\epg_sources.example.json'; Schema = Join-Path $schemasDir 'epg_sources.schema.json' }
    @{ Path = Join-Path $dataDir 'lineup\locals.json'; Schema = Join-Path $schemasDir 'locals.schema.json' }
    @{ Path = Join-Path $dataDir 'lineup\numbering_blocks.json'; Schema = Join-Path $schemasDir 'numbering_blocks.schema.json' }
    @{ Path = Join-Path $dataDir 'lineup\categories.json'; Schema = Join-Path $schemasDir 'categories.schema.json' }
    @{ Path = Join-Path $dataDir 'rules\aliases.json'; Schema = Join-Path $schemasDir 'aliases.schema.json' }
)

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target.Path -PathType Leaf)) {
        $failures.Add("Missing tracked config file: $($target.Path)")
        Write-Host "FAIL  $($target.Path) (missing)" -ForegroundColor Red
        continue
    }

    try {
        Test-Json -Path $target.Path -SchemaFile $target.Schema -ErrorAction Stop | Out-Null
        Write-Host "PASS  $($target.Path)" -ForegroundColor Green
    }
    catch {
        $failures.Add("$($target.Path): $($_.Exception.Message)")
        Write-Host "FAIL  $($target.Path)" -ForegroundColor Red
    }
}

if ($failures.Count -gt 0) {
    $detail = ($failures | ForEach-Object { " - $_" }) -join "`n"
    throw "Schema validation failed for $($failures.Count) file(s):`n$detail"
}

Write-Host "All tracked source-of-truth config files passed schema validation." -ForegroundColor Green
