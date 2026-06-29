function Get-FixtureWithAnalyzerError {
    param(
        [string]$PlainTextPassword
    )

    # Deliberately triggers PSAvoidUsingConvertToSecureStringWithPlainText
    # (Error severity) for Validate-ScriptAnalyzer.ps1's own test suite.
    $secure = ConvertTo-SecureString -String $PlainTextPassword -AsPlainText -Force
    return $secure
}
