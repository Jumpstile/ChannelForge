BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    Import-Module $script:ModulePath -Force
    $script:Port = 18881
    $script:Password = 'leak-check-password-one'
    $script:NewPassword = 'leak-check-password-two'
    $script:Base = "http://127.0.0.1:$($script:Port)"
    $script:Root = Join-Path $TestDrive 'root'
    $script:Config = Join-Path $TestDrive 'config'
    New-Item -ItemType Directory -Force -Path $script:Root, $script:Config | Out-Null
    $script:LogDir = Join-Path ([IO.Path]::GetTempPath()) ('cf-leak-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $script:LogPath = Join-Path $script:LogDir 'server.log'
    $script:Seen = [Collections.Generic.List[string]]::new()

    function Read-Log {
        # The server still holds its log open, so open it with sharing.
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '' }
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { return [IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    }

    function Invoke-Call {
        # Records every response (status, headers, body) so the secrets can be searched for afterwards.
        param([string]$Method = 'GET', [string]$Path, [hashtable]$Body = $null, [string]$Cookie = '')
        $headers = @{}
        if ($Method -eq 'POST') { $headers.Origin = $script:Base }
        if ($Cookie) { $headers.Cookie = $Cookie }
        $p = @{ Uri = "$($script:Base)$Path"; Method = $Method; Headers = $headers; SkipHttpErrorCheck = $true }
        if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Compress); $p.ContentType = 'application/json' }
        $r = Invoke-WebRequest @p
        $headerText = ($r.Headers.GetEnumerator() | Where-Object { $_.Key -ne 'Set-Cookie' } | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "`n"
        $script:Seen.Add("$headerText`n$($r.Content)")
        return $r
    }

    $launcher = Join-Path $script:Root 'server.ps1'
    @("Import-Module '$script:ModulePath' -Force", "Start-ChannelForgeWebServer -Port $($script:Port) -RepositoryRoot '$($script:Root)' -RequireSignIn -ConfigRoot '$($script:Config)'") | Set-Content -LiteralPath $launcher
    $script:Process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile', '-File', $launcher) -WorkingDirectory $script:RepoRoot -PassThru -RedirectStandardOutput $script:LogPath -RedirectStandardError "$($script:LogPath).err"
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        if ($script:Process.HasExited) { break }
        $tcp = [Net.Sockets.TcpClient]::new()
        try { $tcp.Connect('127.0.0.1', $script:Port); break } catch { Start-Sleep -Milliseconds 100 } finally { $tcp.Dispose() }
    }
    # The setup code is printed once on the console; the test reads it the way an admin would.
    $script:Code = $null
    for ($attempt = 0; $attempt -lt 50 -and -not $script:Code; $attempt++) {
        $text = Read-Log $script:LogPath
        if ($text -match 'setup code: (\S+)') { $script:Code = $Matches[1] } else { Start-Sleep -Milliseconds 100 }
    }
    if (-not $script:Code) { throw 'Test server did not print a setup code.' }

    # The walk: first-run, sign-in, wrong password, change password, sign-out.
    $first = Invoke-Call -Method POST -Path '/first-run/submit' -Body @{ code = $script:Code; password = $script:Password }
    $script:FirstCookie = (@($first.Headers['Set-Cookie'])[0] -split ';')[0]
    $script:Token = ($script:FirstCookie -split '=', 2)[1]
    $in = Invoke-Call -Method POST -Path '/api/auth/sign-in' -Body @{ password = $script:Password }
    $script:Cookie = (@($in.Headers['Set-Cookie'])[0] -split ';')[0]
    $script:Token2 = ($script:Cookie -split '=', 2)[1]
    $script:Wrong = Invoke-Call -Method POST -Path '/api/auth/sign-in' -Body @{ password = 'not-the-password-at-all' }
    $script:Change = Invoke-Call -Method POST -Path '/api/auth/change-password' -Cookie $script:Cookie -Body @{ currentPassword = $script:Password; newPassword = $script:NewPassword }
    $script:Cookie3 = (@($script:Change.Headers['Set-Cookie'])[0] -split ';')[0]
    Invoke-Call -Path '/api/status' -Cookie $script:Cookie3 | Out-Null
    Invoke-Call -Method POST -Path '/api/auth/sign-out' -Cookie $script:Cookie3 | Out-Null
    $script:Secrets = @($script:Password, $script:NewPassword, $script:Code, $script:Token, $script:Token2)
    if ($script:Cookie3) { $script:Secrets += ($script:Cookie3 -split '=', 2)[1] }
    $script:Secrets = @($script:Secrets | Where-Object { $_ })
}

AfterAll {
    if ($null -ne $script:Process) {
        if (-not $script:Process.HasExited) { $script:Process.Kill() }
        $script:Process.WaitForExit(10000) | Out-Null
        $script:Process.Dispose()
    }
    if ($script:LogDir -and (Test-Path -LiteralPath $script:LogDir)) {
        try { Remove-Item -LiteralPath $script:LogDir -Recurse -Force -ErrorAction Stop } catch { Write-Verbose 'Test log folder could not be removed yet.' }
    }
}

Describe 'Sign-in leak check' {
    It 'completed the whole walk' {
        $script:FirstCookie | Should -Match '^cf_session='
        $script:Wrong.StatusCode | Should -Be 401
        $script:Change.StatusCode | Should -Be 200
    }

    It 'keeps every secret out of the server console output, except the setup code printed on purpose' {
        $console = (Read-Log $script:LogPath) + (Read-Log "$($script:LogPath).err")
        $console = $console -replace 'setup code: \S+', 'setup code: (shown)'
        foreach ($secret in $script:Secrets) { $console.Contains($secret) | Should -BeFalse }
    }

    It 'keeps every secret out of response bodies and headers other than the cookie value' {
        $all = $script:Seen -join "`n"
        foreach ($secret in $script:Secrets) { $all.Contains($secret) | Should -BeFalse }
    }

    It 'keeps the passwords and the setup code out of the password file' {
        $text = [IO.File]::ReadAllText((Join-Path $script:Config 'admin-password.json'))
        foreach ($secret in @($script:Password, $script:NewPassword, $script:Code)) { $text.Contains($secret) | Should -BeFalse }
    }

    It 'answers a failed sign-in with one plain line and no secret' {
        $script:Wrong.Content | Should -Not -Match 'not-the-password-at-all'
        ($script:Wrong.Content | ConvertFrom-Json).Message | Should -Be 'That password did not work.'
        (Read-Log $script:LogPath) | Should -Not -Match 'not-the-password-at-all'
    }

    It 'keeps every secret out of Doctor output run against the same folders' {
        $doctor = Join-Path $script:RepoRoot 'scripts\Invoke-ChannelForgeDoctor.ps1'
        $out = (& pwsh -NoProfile -File $doctor -Root $script:Root -OutputPath (Join-Path $script:LogDir 'doctor.json') 2>&1 | Out-String)
        $out += (Get-Content -LiteralPath (Join-Path $script:LogDir 'doctor.json') -Raw -ErrorAction SilentlyContinue)
        foreach ($secret in $script:Secrets) { $out.Contains($secret) | Should -BeFalse }
    }
}
