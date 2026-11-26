BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function Get-TestStaticResponse {
        param([string]$Path, [string]$Root, [string]$StaticRoot = '')

        $module = Get-Module -Name ChannelForge
        return & $module {
            param($P, $R, $S)
            Get-ChannelForgeWebResponse -Method GET -Path $P -RepositoryRoot $R -StaticRoot $S
        } $Path $Root $StaticRoot
    }

    # Layout built with [IO.Path] helpers only, so it works on Windows and Linux.
    $script:Root = Join-Path $TestDrive 'repo'
    $script:Dist = [IO.Path]::Combine($script:Root, 'gui', 'dist')
    $script:Outside = Join-Path $TestDrive 'outside'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Dist 'assets'), $script:Outside | Out-Null
    [IO.File]::WriteAllText((Join-Path $script:Dist 'index.html'), 'safe index')
    [IO.File]::WriteAllText((Join-Path $script:Dist 'assets' | Join-Path -ChildPath 'app.js'), 'var ok = 1;')
    [IO.File]::WriteAllText((Join-Path $script:Outside 'secret.js'), 'private outside file')
}

Describe 'Web static file paths work on any operating system' {
    It 'builds the default static root from path parts' {
        $module = Get-Module -Name ChannelForge
        $root = & $module { param($R) Get-ChannelForgeWebDefaultStaticRoot -RepositoryRoot $R } $script:Root
        $root | Should -Be $script:Dist
    }

    It 'serves the index and a nested asset from the default root' {
        $index = Get-TestStaticResponse -Path '/' -Root $script:Root
        $index.StatusCode | Should -Be 200
        $index.Body | Should -Be 'safe index'
        $asset = Get-TestStaticResponse -Path '/assets/app.js' -Root $script:Root
        $asset.StatusCode | Should -Be 200
        $asset.ContentType | Should -Be 'text/javascript; charset=utf-8'
        $asset.Body | Should -Be 'var ok = 1;'
    }

    It 'refuses traversal, encoded traversal, backslash, colon and absolute paths' {
        $absolute = '/' + (Join-Path $script:Outside 'secret.js').Replace('\', '/')
        foreach ($path in @(
                '/../outside/secret.js', '/assets/../../../outside/secret.js',
                '/%2e%2e/outside/secret.js', '/assets/%2e%2e/%2e%2e/index.html',
                '/assets%5Capp.js', '/..%5Coutside%5Csecret.js', '/assets/app.js%00.js',
                '//etc/passwd', '/C:/Windows/win.ini', $absolute)) {
            (Get-TestStaticResponse -Path $path -Root $script:Root).StatusCode | Should -Be 404 -Because $path
        }
    }

    It 'refuses a static root outside gui/dist' {
        (Get-TestStaticResponse -Path '/secret.js' -Root $script:Root -StaticRoot $script:Outside).StatusCode | Should -Be 404
    }

    It 'treats a file name that differs only by case the way the operating system does' {
        $response = Get-TestStaticResponse -Path '/INDEX.HTML' -Root $script:Root
        $expected = if ([IO.Path]::DirectorySeparatorChar -eq [char]92) { 200 } else { 404 }
        $response.StatusCode | Should -Be $expected
    }

    It 'refuses a link that points outside the root' {
        $link = Join-Path $script:Dist 'linked.js'
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $script:Outside 'secret.js') -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'symbolic links are not allowed for this user'
            return
        }
        try {
            $response = Get-TestStaticResponse -Path '/linked.js' -Root $script:Root
            $response.StatusCode | Should -Be 404
            $response.Body | Should -Not -Match 'private outside file'
        }
        finally { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue }
    }
}
