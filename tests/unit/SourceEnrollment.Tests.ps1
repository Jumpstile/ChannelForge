BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
}

Describe 'durable source enrollment' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path $script:Project | Out-Null
        $script:M3U = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=one,One`nhttps://example.invalid/one`n")
        $script:XMLTV = [Text.Encoding]::UTF8.GetBytes('<tv><channel id="one" /></tv>')
        function Save-Enrollment {
            param([byte[]]$M3UBytes = $script:M3U, [byte[]]$XMLTVBytes = $null)
            & (Get-Module ChannelForge) {
                param($Root, $Playlist, $Guide)
                Write-ChannelForgeSourceEnrollment -RepositoryRoot $Root -M3UBytes $Playlist -XMLTVBytes $Guide | Out-Null
            } $script:Project $M3UBytes $XMLTVBytes
        }
    }

    It 'persists an M3U-only enrollment across a fresh module import' {
        Save-Enrollment
        Remove-Module ChannelForge -Force
        Import-Module (Join-Path $script:Root 'src/ChannelForge/ChannelForge.psd1') -Force
        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $input = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project
        Test-Json -Path (Join-Path $script:Project 'state/source-enrollment.json') -SchemaFile (Join-Path $script:Root 'schemas/source-enrollment.schema.json') | Should -BeTrue

        $status.EnrollmentStatus | Should -Be 'saved'
        $status.M3UStatus | Should -Be 'ready'
        $status.XMLTVStatus | Should -Be 'no-guide'
        Test-Path -LiteralPath $input.M3UPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Project 'state/source-enrollment.json') -PathType Leaf | Should -BeTrue
    }

    It 'persists an optional XMLTV guide without exposing source bytes in status' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $raw = $status | ConvertTo-Json -Depth 8

        $status.XMLTVStatus | Should -Be 'ready'
        $raw | Should -Not -Match '#EXTM3U|<tv>|example.invalid'
        $raw | Should -Not -Match 'state[\\/]managed-sources|ContentHash|EnrollmentId'
    }

    It 'fails closed for enrollment record tampering' {
        Save-Enrollment
        $path = Join-Path $script:Project 'state/source-enrollment.json'
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $record.Status = 'Tampered'
        [IO.File]::WriteAllText($path, ($record | ConvertTo-Json -Depth 8 -Compress), [Text.UTF8Encoding]::new($false))

        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'needs-attention'
        $status.CanRefresh | Should -BeFalse
    }

    It 'detects changed managed bytes before any candidate refresh' {
        Save-Enrollment
        $input = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project
        [IO.File]::WriteAllBytes($input.M3UPath, [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1 tvg-id=two,Two`nhttps://example.invalid/two`n"))

        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'changes-found'
        $status.M3UStatus | Should -Be 'changes-found'
        $status.CanRefresh | Should -BeTrue
    }

    It 'reports missing managed bytes as source unavailable' {
        Save-Enrollment
        $input = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $script:Project
        Remove-Item -LiteralPath $input.M3UPath -Force

        $status = Get-ChannelForgeSourceEnrollment -RepositoryRoot $script:Project
        $status.EnrollmentStatus | Should -Be 'source-unavailable'
        $status.CanRefresh | Should -BeFalse
    }

    It 'rejects traversal and reparse-point managed paths' {
        Save-Enrollment
        $module = Get-Module ChannelForge
        { & $module { param($path,$root) Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $root } (Join-Path $script:Project 'state/../outside') (Join-Path $script:Project 'state') } | Should -Throw '*FAIL_CLOSED*'

        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Force -Path $outside | Out-Null
        $link = Join-Path $script:Project 'state/link'
        $symlinkCreated = $false
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
            $symlinkCreated = $true
        }
        catch {
            $symlinkCreated = $false
        }
        if ($symlinkCreated) {
            { & $module { param($path,$root) Assert-ChannelForgeSourceEnrollmentPath -Path $path -AllowedRoot $root } (Join-Path $link 'file.m3u') (Join-Path $script:Project 'state') } | Should -Throw '*FAIL_CLOSED*'
        }
    }

    It 'leaves no enrollment temporary files after atomic persistence' {
        Save-Enrollment -XMLTVBytes $script:XMLTV
        @(Get-ChildItem -LiteralPath (Join-Path $script:Project 'state') -Recurse -Force -File | Where-Object Name -like '*.tmp').Count | Should -Be 0
    }
}
