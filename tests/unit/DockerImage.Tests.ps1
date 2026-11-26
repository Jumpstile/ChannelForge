BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Dockerfile = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docker/Dockerfile') -Raw
    $script:Entrypoint = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docker/entrypoint.ps1') -Raw
    $script:EntrypointPath = Join-Path $script:RepoRoot 'docker/entrypoint.ps1'
}

Describe 'Docker image files' {
    It 'runs as a non-root user' {
        $script:Dockerfile | Should -Match '(?m)^USER channelforge\s*$'
    }
    It 'pins both base images to an exact version' {
        $script:Dockerfile | Should -Match '(?m)^FROM node:22\.?[\w.-]*\s+AS gui'
        $script:Dockerfile | Should -Match '(?m)^FROM mcr\.microsoft\.com/powershell:7\.6\.4-'
    }
    It 'exposes port 47850 only and keeps data in /data' {
        $script:Dockerfile | Should -Match '(?m)^EXPOSE 47850\s*$'
        $script:Dockerfile | Should -Not -Match '(?m)^EXPOSE (?!47850\s*$)'
        $script:Dockerfile | Should -Match '(?m)^VOLUME /data\s*$'
    }
    It 'has a health check on /health' {
        $script:Dockerfile | Should -Match '(?m)^HEALTHCHECK .*\\?\r?\n?.*47850/health'
    }
    It 'holds no secret-looking values' {
        $script:Dockerfile | Should -Not -Match '(?i)(password|secret|token|setup.?code)\s*[=:]'
        $script:Dockerfile | Should -Not -Match '(?m)^\s*(ENV|ARG)\s+\S*(PASSWORD|SECRET|TOKEN|CODE)'
    }
    It 'does not copy a local data or secrets folder into the image' {
        $script:Dockerfile | Should -Not -Match '(?m)^COPY\s+(data|state|output)\b'
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot '.dockerignore')) | Should -Contain 'data'
    }
}

Describe 'Docker entry point' {
    It 'starts the launcher with the config folder, all interfaces and port 47850' {
        $script:Entrypoint | Should -Match "ConfigRoot = \`$config"
        $script:Entrypoint | Should -Match "BindAddress = '0\.0\.0\.0'"
        $script:Entrypoint | Should -Match 'Port = 47850'
        $script:Entrypoint | Should -Match 'Start-ChannelForgeServer\.ps1'
        $script:Entrypoint | Should -Match 'CHANNELFORGE_ALLOWED_HOST'
    }
    It 'refuses to start and says why when the data folder cannot be written' {
        # A plain file where the data folder should be: the config folder cannot be created.
        $blocker = Join-Path $TestDrive 'not-a-folder'
        Set-Content -LiteralPath $blocker -Value 'x'
        $output = & (Get-Command pwsh).Source -NoProfile -File $script:EntrypointPath -DataRoot $blocker 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $output | Should -BeLike '*cannot write to*'
    }
}
