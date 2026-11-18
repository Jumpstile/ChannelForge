BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'scripts/smoke/Invoke-ChannelForgeSmoke.ps1')

    # Copies the real .cmd into a folder whose name has a space. Only the runtime line changes: it
    # points at the pwsh running this test. The script the .cmd calls is a stub that prints each argument.
    function New-BundleCmdFixture([string]$CmdName, [string]$StubRelativePath) {
        $bundle = Join-Path $TestDrive 'my bundle'
        New-Item -ItemType Directory -Force -Path (Join-Path $bundle (Split-Path -Parent $StubRelativePath)) | Out-Null
        $pwsh = Join-Path $PSHOME 'pwsh.exe'
        $text = (Get-Content -LiteralPath (Join-Path $script:RepoRoot $CmdName) -Raw) -replace '(?m)^set "PW=.*$', ('set "PW=' + $pwsh + '"')
        [IO.File]::WriteAllText((Join-Path $bundle $CmdName), $text, [Text.Encoding]::ASCII)
        Set-Content -LiteralPath (Join-Path $bundle $StubRelativePath) -Value 'for ($i = 0; $i -lt $args.Count; $i++) { "ARG$i=[$($args[$i])]" }'
        return $bundle
    }
}

Describe 'Bundle .cmd files pass a folder path that parses' -Skip:(-not $IsWindows) {
    It 'Install ChannelForge.cmd gives PackageRoot without a stray quote and keeps the next argument separate' {
        $bundle = New-BundleCmdFixture 'Install ChannelForge.cmd' 'scripts\Install-ChannelForgeWindowsBundle.ps1'
        $run = Invoke-SmokeBundleCmd -BundleRoot $bundle -CmdName 'Install ChannelForge.cmd' -ArgumentList @('-SkipStart')
        $run.Output | Should -Match ([regex]::Escape('ARG0=[-PackageRoot]'))
        $run.Output | Should -Match ([regex]::Escape("ARG1=[$bundle]"))
        $run.Output | Should -Match ([regex]::Escape('ARG2=[-SkipStart]'))
    }

    It 'Update ChannelForge.cmd gives PackageRoot without a stray quote and keeps the next arguments separate' {
        $bundle = New-BundleCmdFixture 'Update ChannelForge.cmd' 'tools\Invoke-ChannelForgeAutoUpdate.ps1'
        $run = Invoke-SmokeBundleCmd -BundleRoot $bundle -CmdName 'Update ChannelForge.cmd'
        $run.Output | Should -Match ([regex]::Escape('ARG0=[-PackageRoot]'))
        $run.Output | Should -Match ([regex]::Escape("ARG1=[$bundle]"))
        $run.Output | Should -Match ([regex]::Escape('ARG2=[-InstallRoot]'))
        $run.Output | Should -Match ([regex]::Escape('ARG4=[-Apply]'))
    }

    It 'no .cmd in the repo has a quoted path that ends in a backslash' {
        $bad = @(Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -Filter '*.cmd' -File |
            Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git)[\\/]' } |
            Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '\\"|"%ROOT%"|"%~dp0"' } |
            ForEach-Object Name)
        $bad | Should -BeNullOrEmpty
    }
}
