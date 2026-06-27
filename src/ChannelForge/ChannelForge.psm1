# Load class definitions first.
# PowerShell classes must be loaded before functions that use them.
$Classes = @(Get-ChildItem -Path $PSScriptRoot\Classes\*.ps1 -ErrorAction SilentlyContinue)

foreach ($class in $Classes) {
    try {
        . $class.FullName
    }
    catch {
        throw "Failed to import class $($class.FullName): $_"
    }
}

# Load private helper functions before public functions.
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)

foreach ($import in @($Private + $Public)) {
    try {
        . $import.FullName
    }
    catch {
        throw "Failed to import function $($import.FullName): $_"
    }
}

Export-ModuleMember -Function $Public.BaseName