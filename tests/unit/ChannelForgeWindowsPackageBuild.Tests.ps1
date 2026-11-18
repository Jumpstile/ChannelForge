BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScript = Join-Path $script:RepoRoot 'scripts\Build-ChannelForgeWindowsPackage.ps1'
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('cf-build-test-' + [guid]::NewGuid().ToString('N'))
    $script:Source = Join-Path $script:Work 'source'
    New-Item -ItemType Directory -Force -Path $script:Source | Out-Null

    # Fake runtime ZIP: a copy of the running pwsh, so the build's "runtime executes" check passes.
    $script:RuntimeZip = Join-Path $script:Work 'runtime.zip'
    Compress-Archive -Path (Join-Path $PSHOME '*') -DestinationPath $script:RuntimeZip -CompressionLevel NoCompression
    $script:RuntimeHash = (Get-FileHash -LiteralPath $script:RuntimeZip -Algorithm SHA256).Hash.ToLowerInvariant()

    # Temp copy of the files the build reads, as its own git repo. The real repo is never changed.
    foreach ($path in @('src\ChannelForge', 'schemas', 'tools', 'scripts', 'docs\user', 'data\rules\aliases.json',
            'data\lineup\numbering_blocks.json', 'README.md', 'LICENSE', 'VERSION') + @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.cmd' | ForEach-Object Name)) {
        $target = Join-Path $script:Source $path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot $path) -Destination $target -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Source 'gui\dist') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Source 'gui\dist\index.html') -Value '<html></html>'
    & git -C $script:Source init -q 2>$null
    & git -C $script:Source add -A 2>$null
    & git -C $script:Source -c user.name=test -c user.email=test@example.invalid commit -q -m test 2>$null

    function script:Invoke-TestBuild([string]$Name) {
        $out = Join-Path $script:Work $Name
        $text = & pwsh -NoProfile -File $script:BuildScript -Root $script:Source -OutputRoot $out `
            -PowerShellRuntimeZipPath $script:RuntimeZip -PowerShellRuntimeSha256 $script:RuntimeHash -AllowDirty *>&1 | Out-String
        $zip = @(Get-ChildItem -LiteralPath $out -Filter '*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1)
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $text; Zip = if ($zip) { $zip[0].FullName } else { $null }; Out = $out }
    }
    function script:Expand-TestPackage([string]$Zip, [string]$Name) {
        $dest = Join-Path $script:Work $Name
        Expand-Archive -LiteralPath $Zip -DestinationPath $dest -Force
        $dest
    }
    function script:Get-TextFiles([string]$PackageRoot) {
        $runtime = Join-Path $PackageRoot 'runtime'
        $ext = @('.ps1', '.psm1', '.psd1', '.json', '.md', '.cmd', '.txt', '.html', '.js', '.css', '.map')
        @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Force | Where-Object { $_.FullName -notlike "$runtime*" -and $ext -contains $_.Extension.ToLowerInvariant() })
    }
    function script:Get-ImageLinks([string]$MarkdownPath) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $MarkdownPath -Raw), '!\[[^\]]*\]\(([^)\s]+)\)')) {
            if ($m.Groups[1].Value -notmatch '^[a-z][a-z0-9+.-]*:') {
                [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MarkdownPath) $m.Groups[1].Value))
            }
        }
    }

    # Decoys that must never ship, plus an unreferenced screenshot.
    foreach ($decoy in @('state\x.json', 'config\local.json', 'config\enrollment.json', 'output\x.txt', 'cache\x.txt', 'logs\x.txt',
            'test-results\x.xml', 'node_modules\x\index.js', '.worktrees\x\y.txt', 'data\providers\local.json', 'docs\user\assets\unreferenced.png')) {
        $target = Join-Path $script:Source $decoy
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Set-Content -LiteralPath $target -Value 'decoy'
    }
    $script:BuildA = Invoke-TestBuild 'out-a'
    $script:BuildB = Invoke-TestBuild 'out-b'
    if ($script:BuildA.Zip) { $script:PackageA = Expand-TestPackage $script:BuildA.Zip 'pkg-a' }
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Build-ChannelForgeWindowsPackage' {
    It 'builds a package from the temp source' {
        $script:BuildA.ExitCode | Should -Be 0 -Because $script:BuildA.Output
        $script:BuildA.Zip | Should -Not -BeNullOrEmpty
    }

    It 'ships no state, config, output, cache, log, test-result, git or node_modules files, and no local data files' {
        $entries = @(Get-ChildItem -LiteralPath $script:PackageA -Recurse -Force | Where-Object { $_.FullName -notlike (Join-Path $script:PackageA 'runtime*') } |
            ForEach-Object { [IO.Path]::GetRelativePath($script:PackageA, $_.FullName).Replace('\', '/') })
        $forbidden = @('.git', '.worktrees', 'state', 'config', 'output', 'cache', 'logs', 'test-results', 'node_modules', 'target')
        @($entries | Where-Object { @($_ -split '/' | Where-Object { $forbidden -contains $_ }).Count -gt 0 }) | Should -BeNullOrEmpty
        $entries | Should -Not -Contain 'data/providers/local.json'
        $entries | Should -Not -Contain 'docs/user/assets/unreferenced.png'
        $top = @($entries | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)
        @($top | Where-Object { @('src', 'gui', 'schemas', 'tools', 'scripts', 'data', 'docs', 'runtime', 'package-manifest.json', 'README.md', 'LICENSE', 'VERSION') -notcontains $_ -and $_ -notlike '*.cmd' }) | Should -BeNullOrEmpty
        @($entries | Where-Object { $_ -like 'data/*' }) | Where-Object { $_ -notmatch '^data(/rules(/aliases\.json)?|/lineup(/numbering_blocks\.json)?)?$' } | Should -BeNullOrEmpty
    }

    It 'fails closed when a forbidden folder sits inside a copied source folder' {
        $decoy = Join-Path $script:Source 'src\ChannelForge\state'
        New-Item -ItemType Directory -Force -Path $decoy | Out-Null
        try {
            $bad = Invoke-TestBuild 'out-forbidden'
            $bad.ExitCode | Should -Not -Be 0
            $bad.Zip | Should -BeNullOrEmpty
            $bad.Output | Should -BeLike '*forbidden path component*'
        } finally { Remove-Item -LiteralPath $decoy -Recurse -Force }
    }

    It 'produces the same manifest in two builds from the same source' {
        $script:BuildB.ExitCode | Should -Be 0 -Because $script:BuildB.Output
        $a = Get-Content -LiteralPath (Join-Path $script:PackageA 'package-manifest.json') -Raw
        $b = Get-Content -LiteralPath (Join-Path (Expand-TestPackage $script:BuildB.Zip 'pkg-b') 'package-manifest.json') -Raw
        $b | Should -BeExactly $a
        # Path, ByteLength and Sha256 are part of the manifest text compared above.
        $manifest = $a | ConvertFrom-Json
        @($manifest.Files).Count | Should -BeGreaterThan 0
        Write-Host ('ZIP bytes identical across builds: ' + ((Get-FileHash $script:BuildA.Zip).Hash -eq (Get-FileHash $script:BuildB.Zip).Hash))
    }

    It 'has no build-machine path in shipped text files or the manifest' {
        $roots = @($script:Source, $script:Work, $env:TEMP, $env:USERPROFILE, $script:RepoRoot) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\', '/') }
        $needles = @($roots | ForEach-Object { $_; $_.Replace('\', '/') } | Sort-Object -Unique)
        # Documented example paths and path-handling comments, not build-machine paths.
        $example = '^[A-Za-z]:[\\/](private[\\/]|foo[\\/]|\.\.\.|"|\\)'
        foreach ($file in @(Get-TextFiles $script:PackageA)) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($needle in $needles) { $text.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) | Should -Be -1 -Because "$($file.Name) has $needle" }
            $drive = @([regex]::Matches($text, '(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s`''")]*') | Where-Object { $_.Value -notmatch $example -and $_.Value -notmatch '^[A-Za-z]:[\\/]$' } | ForEach-Object Value)
            $drive | Should -BeNullOrEmpty -Because $file.FullName
        }
    }

    It 'ships exactly the screenshots the shipped docs reference' {
        $docs = @(Get-ChildItem -LiteralPath $script:PackageA -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notlike (Join-Path $script:PackageA 'runtime*') })
        $referenced = @($docs | ForEach-Object { Get-ImageLinks $_.FullName } | ForEach-Object { [IO.Path]::GetRelativePath($script:PackageA, $_).Replace('\', '/') } | Sort-Object -Unique)
        $shipped = @(Get-ChildItem -LiteralPath (Join-Path $script:PackageA 'docs\user\assets') -Recurse -File | ForEach-Object { 'docs/user/assets/' + [IO.Path]::GetRelativePath((Join-Path $script:PackageA 'docs\user\assets'), $_.FullName).Replace('\', '/') } | Sort-Object)
        $referenced.Count | Should -BeGreaterThan 0
        ($shipped -join "`n") | Should -BeExactly ($referenced -join "`n")
    }

    It 'fails the build when a staged file holds a credential URL' {
        $decoy = Join-Path $script:Source 'schemas\decoy.json'
        Set-Content -LiteralPath $decoy -Value '{"u":"https://admin:hunter2@example.com/x"}'
        try {
            $bad = Invoke-TestBuild 'out-secret'
            $bad.ExitCode | Should -Not -Be 0
            $bad.Zip | Should -BeNullOrEmpty
            $bad.Output | Should -BeLike '*likely secret*'
        } finally { Remove-Item -LiteralPath $decoy -Force }
    }
}
