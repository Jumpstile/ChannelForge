# Clean-machine smoke for a ChannelForge Windows package.
# Runs INSIDE Windows Sandbox (Windows PowerShell 5.1 is fine). Do not run it on
# a real PC: it installs, then deletes %LOCALAPPDATA%\ChannelForge.
# Dot-sourcing this file only loads the functions (the tests use that).
[CmdletBinding()]
param(
    [string]$InputRoot = 'C:\Smoke\In',
    [string]$ResultsRoot = 'C:\Smoke\Results',
    [int]$Port = 8765,
    [int]$StepTimeoutSeconds = 120,
    [int]$OverallTimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:ValidStatuses = @('PASS', 'FAIL', 'NOT RUN')
$script:Steps = New-Object System.Collections.ArrayList
$script:ProgressPath = $null
$script:StepTimeoutSec = 120
$script:OverallMinutes = 20
$script:RunDeadline = $null

# Every step the run plans to do. A step that never ran is written as NOT RUN.
$script:StepPlan = @(
    @('package-hash', 'ZIP SHA-256 matches the evidence file'),
    @('unzip', 'ZIP unpacks and has package-manifest.json'),
    @('commit-match', 'Manifest source commit matches the evidence file'),
    @('install', 'Install script copies the app to LocalAppData'),
    @('start', 'Start script reports a healthy server'),
    @('web-page', 'Local web page answers with HTML'),
    @('status-empty', 'Fresh install reports no accepted lineup'),
    @('proposal', 'Fixture M3U and XMLTV analyze to a reviewable proposal'),
    @('accept', 'Accepting the proposal saves a lineup and sources'),
    @('status-accepted', 'Status reports an accepted lineup'),
    @('restart-state', 'Stop, start, and the accepted lineup is still there'),
    @('refresh', 'Refresh of the saved fixture sources answers 200'),
    @('update-check-local', 'Update check on the local package reports it valid'),
    @('update-same-version', 'Updating to the same version is refused, files unchanged'),
    @('update-check-github', 'Update check against the GitHub release'),
    @('uninstall-cancel', 'Uninstall with a wrong DELETE word removes nothing (the typed menu itself is NOT verified here)'),
    @('uninstall-keep', 'Uninstall with -Verbose removes the app and keeps the data'),
    @('uninstall-delete', 'Uninstall with -PurgeData -ConfirmPurge removes the install folder')
)

# One line per event in progress.txt: time, step number, id, STARTED or the result.
# The file is closed after every line, so the host can read it while the run goes on.
function Write-SmokeProgress {
    param([string]$Id, [string]$Status, [string]$Detail = '')
    if (-not $script:ProgressPath) { return }
    $index = 0
    for ($i = 0; $i -lt $script:StepPlan.Count; $i++) { if ($script:StepPlan[$i][0] -eq $Id) { $index = $i + 1 } }
    $number = if ($index -gt 0) { '{0:00}' -f $index } else { '--' }
    $line = (@([DateTime]::UtcNow.ToString('yyyy-MM-dd''T''HH:mm:ss''Z'''), $number, $Id, $Status) -join "`t")
    if ($Detail) { $line += " [$(($Detail -replace '\s+', ' '))]" }
    [IO.File]::AppendAllText($script:ProgressPath, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
}

# Seconds a process or wait may take now: the step limit, cut short by the overall limit.
function Get-SmokeLimitSeconds {
    $limit = $script:StepTimeoutSec
    if ($script:RunDeadline) {
        $left = [int][Math]::Ceiling(($script:RunDeadline - [DateTime]::UtcNow).TotalSeconds)
        if ($left -lt $limit) { $limit = $left }
    }
    return [Math]::Max(1, $limit)
}

function Add-SmokeStep {
    param([string]$Id, [string]$Name, [string]$Status, [string]$Detail = '')
    if ($script:ValidStatuses -cnotcontains $Status) { throw "Invalid step status: $Status" }
    [void]$script:Steps.Add([pscustomobject]@{ Id = $Id; Name = $Name; Status = $Status; Detail = $Detail })
    Write-SmokeProgress -Id $Id -Status $Status -Detail $Detail
}

# Runs one check. PASS only when the check returns $true; a throw or $false is FAIL.
# -Required: a FAIL stops the run (later steps are written as NOT RUN).
function Invoke-SmokeStep {
    param([string]$Id, [string]$Name, [scriptblock]$Check, [switch]$Required)
    if ($script:RunDeadline -and [DateTime]::UtcNow -gt $script:RunDeadline) {
        Add-SmokeStep -Id 'run' -Name 'Smoke run' -Status 'FAIL' -Detail "timed out: the overall limit of $($script:OverallMinutes) minutes was reached before step '$Id'."
        throw "smoke-halt: overall timeout before step '$Id'."
    }
    Write-SmokeProgress -Id $Id -Status 'STARTED'
    $status = 'FAIL'
    $detail = ''
    try {
        $result = & $Check
        if ($result -is [bool] -and $result) { $status = 'PASS' }
        elseif ($result -is [bool]) { $detail = 'The check returned false.' }
        else { $detail = 'The check did not return true or false.' }
    }
    catch { $detail = [string]$_.Exception.Message }
    Add-SmokeStep -Id $Id -Name $Name -Status $status -Detail $detail
    if ($Required -and $status -ne 'PASS') { throw "smoke-halt: required step '$Id' did not pass." }
}

function Skip-SmokeStep {
    param([string]$Id, [string]$Name, [string]$Reason)
    Add-SmokeStep -Id $Id -Name $Name -Status 'NOT RUN' -Detail $Reason
}

# PASS only when every step is PASS. Any FAIL is FAIL. Otherwise INCOMPLETE.
function Get-SmokeOverall {
    param([object[]]$Steps)
    if (@($Steps).Count -eq 0) { return 'INCOMPLETE' }
    if (@($Steps | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0) { return 'FAIL' }
    if (@($Steps | Where-Object { $_.Status -ne 'PASS' }).Count -gt 0) { return 'INCOMPLETE' }
    return 'PASS'
}

# Writes the plain-text and JSON records. Planned steps that never ran become NOT RUN.
function Write-SmokeEvidence {
    param(
        [object[]]$Steps, [string[]]$PlannedIds = @(), [string]$ResultsRoot,
        [string]$PackageFilename, [string]$PackageSha256, [string]$SourceCommitSha, [string]$StartedUtc
    )
    $all = New-Object System.Collections.ArrayList
    foreach ($step in @($Steps)) { [void]$all.Add($step) }
    foreach ($row in $script:StepPlan) {
        if ($PlannedIds -contains $row[0] -and @($all | Where-Object { $_.Id -eq $row[0] }).Count -eq 0) {
            [void]$all.Add([pscustomobject]@{ Id = $row[0]; Name = $row[1]; Status = 'NOT RUN'; Detail = 'Not reached.' })
        }
    }
    foreach ($step in $all) {
        if ($script:ValidStatuses -cnotcontains $step.Status) { throw "Invalid step status: $($step.Status)" }
    }
    $overall = Get-SmokeOverall -Steps @($all)
    $notCovered = @('Code signing', 'A real provider or real credentials', 'GUI screenshots or browser clicks', 'Windows Defender or SmartScreen prompts', 'The typed uninstall menu itself (choosing 1 or 2, typing DELETE): the sandbox does not deliver typed answers, so a person at a real console must check it')
    $record = [ordered]@{
        SchemaVersion = 'clean-machine-smoke/v1'
        Overall = $overall
        PackageFilename = $PackageFilename
        PackageSha256 = $PackageSha256
        SourceCommitSha = $SourceCommitSha
        StartedUtc = $StartedUtc
        FinishedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-dd''T''HH:mm:ss''Z''')
        PassCount = @($all | Where-Object { $_.Status -eq 'PASS' }).Count
        FailCount = @($all | Where-Object { $_.Status -eq 'FAIL' }).Count
        NotRunCount = @($all | Where-Object { $_.Status -eq 'NOT RUN' }).Count
        Steps = @($all | ForEach-Object { [ordered]@{ Id = $_.Id; Name = $_.Name; Status = $_.Status; Detail = $_.Detail } })
        NotCovered = $notCovered
    }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("ChannelForge clean-machine smoke: $overall")
    [void]$lines.Add("Package: $PackageFilename")
    [void]$lines.Add("Package SHA-256: $PackageSha256")
    [void]$lines.Add("Source commit: $SourceCommitSha")
    [void]$lines.Add("Started (UTC): $StartedUtc")
    [void]$lines.Add('')
    foreach ($step in $all) {
        $tag = $step.Status.PadRight(7)
        $text = "$tag $($step.Id) - $($step.Name)"
        if ($step.Detail) { $text += " [$($step.Detail)]" }
        [void]$lines.Add($text)
    }
    [void]$lines.Add('')
    [void]$lines.Add('Not covered: ' + ($notCovered -join '; '))
    New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null
    $textPath = Join-Path $ResultsRoot 'ChannelForge-smoke-evidence.txt'
    $jsonPath = Join-Path $ResultsRoot 'ChannelForge-smoke-evidence.json'
    $tmpPath = $jsonPath + '.tmp'
    [IO.File]::WriteAllText($textPath, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    # The JSON is written last and renamed into place: the host waits for this file.
    [IO.File]::WriteAllText($tmpPath, ($record | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmpPath -Destination $jsonPath -Force
    return [pscustomobject]@{ Overall = $overall; JsonPath = $jsonPath; TextPath = $textPath }
}

# Runs a program with input closed (or fed from -StdinText) so it can never wait for a
# key press. Past the time limit the process tree is stopped and this throws "timed out".
function Invoke-SmokeProcess {
    param([string]$Exe, [string[]]$Arguments, [string]$StdinText = '')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Exe
    $info.Arguments = (@($Arguments | ForEach-Object { if ($_ -match '\s' -and $_ -notmatch '^"') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    if ($StdinText) { $process.StandardInput.Write($StdinText) }
    $process.StandardInput.Close()
    $limit = Get-SmokeLimitSeconds
    if (-not $process.WaitForExit($limit * 1000)) {
        & taskkill.exe /T /F /PID $process.Id 2>&1 | Out-Null
        $process.Dispose()
        throw "timed out after $limit seconds: $([IO.Path]::GetFileName($Exe)) $($info.Arguments)"
    }
    $process.WaitForExit()
    $code = $process.ExitCode
    # A server the script left running may keep the pipes open; do not wait for them forever.
    $text = ''
    try {
        if ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($out, $err), 5000)) { $text = [string]$out.Result + [string]$err.Result }
    }
    catch { $text = '' }
    $process.Dispose()
    return [pscustomobject]@{ ExitCode = $code; Output = $text }
}

function Invoke-SmokeHttp {
    param([string]$Method, [string]$Url, [string]$Body = $null)
    $request = @{ Uri = $Url; Method = $Method; UseBasicParsing = $true; TimeoutSec = (Get-SmokeLimitSeconds) }
    if ($Method -eq 'POST') {
        $request.ContentType = 'application/json'
        if ($null -ne $Body) { $request.Body = [Text.Encoding]::UTF8.GetBytes($Body) }
    }
    try {
        $response = Invoke-WebRequest @request
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = [string]$response.Content }
    }
    catch {
        $failed = if ($_.Exception.PSObject.Properties['Response']) { $_.Exception.Response } else { $null }
        if ($null -eq $failed) {
            $why = [string]$_.Exception.Message
            if ($why -match 'time(d)?[ -]?out') { throw "timed out: $Method $Url" }
            return [pscustomobject]@{ Status = 0; Body = $why }
        }
        $reader = New-Object IO.StreamReader($failed.GetResponseStream())
        try { return [pscustomobject]@{ Status = [int]$failed.StatusCode; Body = $reader.ReadToEnd() } }
        finally { $reader.Dispose() }
    }
}

function Get-SmokeStatus {
    param([int]$Port)
    $reply = Invoke-SmokeHttp -Method GET -Url "http://127.0.0.1:$Port/api/status"
    if ($reply.Status -ne 200) { throw "GET /api/status answered $($reply.Status)." }
    return ($reply.Body | ConvertFrom-Json)
}

# First 300 characters of a process's output on one line, for a FAIL detail.
function Get-SmokeHead {
    param([string]$Text)
    $flat = ($Text -replace '\s+', ' ').Trim()
    if ($flat.Length -gt 300) { return $flat.Substring(0, 300) }
    return $flat
}

# Returns $true when $Ok; otherwise throws with the process exit code and output head.
function Assert-SmokeRun {
    param($Run, [string]$What, [bool]$Ok)
    if (-not $Ok) { throw "$What failed (exit code $($Run.ExitCode)). Output: $(Get-SmokeHead $Run.Output)" }
    return $true
}

# Runs the real Uninstall ChannelForge.cmd and returns the run (ExitCode, Output).
# -ArgumentList (for example -Verbose) skips the typed menu. -Answers are typed answers
# on stdin; input ends after them, so the closing "pause" returns at once.
function Invoke-SmokeUninstallCmd {
    param([string]$BundleRoot, [string[]]$Answers = @(), [string[]]$ArgumentList = @())
    $cmdPath = Join-Path $BundleRoot 'Uninstall ChannelForge.cmd'
    # The whole command is wrapped in one more pair of quotes: cmd /c keeps the quoted .cmd path intact.
    $line = '"' + (@('"' + $cmdPath + '"') + $ArgumentList -join ' ') + '"'
    $stdin = if ($Answers.Count -gt 0) { ($Answers -join "`r`n") + "`r`n" } else { '' }
    return Invoke-SmokeProcess $env:ComSpec @('/c', $line) -StdinText $stdin
}

# Up to $Max files left under $Root, as relative paths (folders only when no file is left).
function Get-SmokeLeftover {
    param([string]$Root, [int]$Max = 10)
    $items = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) { $items = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue) }
    $prefix = $Root.TrimEnd('\', '/').Length + 1
    return @($items | Select-Object -First $Max | ForEach-Object { $_.FullName.Substring($prefix) })
}

# The uninstaller finishes in a hidden helper, so wait for the root to go. PASS ($true)
# only when it is gone; otherwise throw and list what is left.
function Test-SmokeRootRemoved {
    param([string]$Root, $Run, [int]$WaitSeconds = 30)
    $until = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while ((Test-Path -LiteralPath $Root) -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-Path -LiteralPath $Root)) { return $true }
    $left = @(Get-SmokeLeftover -Root $Root)
    throw "Uninstall (delete data) failed: the install folder is still there after $WaitSeconds seconds (exit code $($Run.ExitCode)). Left: $($left -join '; '). Output: $(Get-SmokeHead $Run.Output)"
}

function Invoke-SmokeRun {
    param([string]$InputRoot, [string]$ResultsRoot, [int]$Port, [int]$StepTimeoutSeconds = 120, [int]$OverallTimeoutMinutes = 20)
    New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null
    $script:ProgressPath = Join-Path $ResultsRoot 'progress.txt'
    $script:StepTimeoutSec = $StepTimeoutSeconds
    $script:OverallMinutes = $OverallTimeoutMinutes
    $script:RunDeadline = [DateTime]::UtcNow.AddMinutes($OverallTimeoutMinutes)
    $started = [DateTime]::UtcNow.ToString('yyyy-MM-dd''T''HH:mm:ss''Z''')
    $evidenceFile = @(Get-ChildItem -LiteralPath $InputRoot -Filter '*.zip.evidence.json')
    if ($evidenceFile.Count -ne 1) { throw 'Expected exactly one *.zip.evidence.json in the input folder.' }
    $expected = Get-Content -LiteralPath $evidenceFile[0].FullName -Raw | ConvertFrom-Json
    $zipPath = Join-Path $InputRoot ([string]$expected.PackageFilename)
    $bundle = 'C:\Smoke\Work\bundle'
    $install = Join-Path $env:LOCALAPPDATA 'ChannelForge'
    $base = "http://127.0.0.1:$Port"
    $script:zipHash = ''
    $script:manifestCommit = ''
    $state = @{ Before = $null }
    $planned = @($script:StepPlan | ForEach-Object { $_[0] })
    try {
        Invoke-SmokeStep 'package-hash' $script:StepPlan[0][1] -Required {
            $script:zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($script:zipHash -cne ([string]$expected.PackageSha256).ToLowerInvariant()) { throw 'The ZIP hash differs from the evidence file.' }
            $true
        }
        Invoke-SmokeStep 'unzip' $script:StepPlan[1][1] -Required {
            New-Item -ItemType Directory -Force -Path $bundle | Out-Null
            Expand-Archive -LiteralPath $zipPath -DestinationPath $bundle -Force
            Test-Path -LiteralPath (Join-Path $bundle 'package-manifest.json') -PathType Leaf
        }
        Invoke-SmokeStep 'commit-match' $script:StepPlan[2][1] {
            $manifest = Get-Content -LiteralPath (Join-Path $bundle 'package-manifest.json') -Raw | ConvertFrom-Json
            $script:manifestCommit = [string]$manifest.SourceCommitSha
            $script:manifestCommit -ceq [string]$expected.PackageSourceCommitSha
        }
        $bundlePwsh = Join-Path $bundle 'runtime\pwsh\pwsh.exe'
        $installPwsh = Join-Path $install 'runtime\pwsh\pwsh.exe'
        $pwshArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File')
        Invoke-SmokeStep 'install' $script:StepPlan[3][1] -Required {
            $run = Invoke-SmokeProcess $bundlePwsh ($pwshArgs + @((Join-Path $bundle 'scripts\Install-ChannelForgeWindowsBundle.ps1'), '-PackageRoot', $bundle, '-SkipStart'))
            Assert-SmokeRun $run 'Install' ($run.ExitCode -eq 0) | Out-Null
            Test-Path -LiteralPath (Join-Path $install 'package-manifest.json') -PathType Leaf
        }
        Invoke-SmokeStep 'start' $script:StepPlan[4][1] -Required {
            $run = Invoke-SmokeProcess $installPwsh ($pwshArgs + @((Join-Path $install 'scripts\Start-ChannelForge.ps1'), '-NoBrowser', '-Port', [string]$Port))
            Assert-SmokeRun $run 'Start' ($run.ExitCode -eq 0) | Out-Null
            (Invoke-SmokeHttp GET "$base/health").Status -eq 200
        }
        Invoke-SmokeStep 'web-page' $script:StepPlan[5][1] {
            $page = Invoke-SmokeHttp GET "$base/"
            $page.Status -eq 200 -and $page.Body -match '<html'
        }
        Invoke-SmokeStep 'status-empty' $script:StepPlan[6][1] { (Get-SmokeStatus $Port).LineupStatus -ceq 'not-accepted' }

        $script:proposalId = $null
        Invoke-SmokeStep 'proposal' $script:StepPlan[7][1] {
            $m3u = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $InputRoot 'fixtures\smoke.m3u')))
            $xml = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $InputRoot 'fixtures\smoke.xml')))
            $body = @{ schemaVersion = 1; m3u = @{ contentBase64 = $m3u }; xmltv = @{ contentBase64 = $xml } } | ConvertTo-Json -Depth 4 -Compress
            $reply = Invoke-SmokeHttp POST "$base/api/guided-setup/proposal" $body
            if ($reply.Status -ne 200) { throw "Proposal answered $($reply.Status): $($reply.Body)" }
            $parsed = $reply.Body | ConvertFrom-Json
            $script:proposalId = [string]$parsed.Proposal.ProposalId
            $parsed.Status -ceq 'PROPOSAL_READY' -and [bool]$parsed.Proposal.CanAccept -and [int]$parsed.Proposal.ChannelCount -eq 2
        }
        Invoke-SmokeStep 'accept' $script:StepPlan[8][1] {
            if (-not $script:proposalId) { throw 'There is no proposal to accept.' }
            $body = @{ schemaVersion = 1; proposalId = $script:proposalId; acknowledged = $true } | ConvertTo-Json -Compress
            $reply = Invoke-SmokeHttp POST "$base/api/guided-setup/accept" $body
            if ($reply.Status -ne 200) { throw "Accept answered $($reply.Status): $($reply.Body)" }
            $parsed = $reply.Body | ConvertFrom-Json
            $parsed.Status -ceq 'ACCEPTED' -and $parsed.EnrollmentStatus -ceq 'SAVED'
        }
        Invoke-SmokeStep 'status-accepted' $script:StepPlan[9][1] {
            $status = Get-SmokeStatus $Port
            $state.Before = $status
            $status.LineupStatus -ceq 'accepted' -and $status.SourcesStatus -ceq 'saved'
        }
        Invoke-SmokeStep 'restart-state' $script:StepPlan[10][1] {
            $stopped = Invoke-SmokeProcess $installPwsh ($pwshArgs + @((Join-Path $install 'scripts\Stop-ChannelForge.ps1')))
            Assert-SmokeRun $stopped 'Stop' ($stopped.ExitCode -eq 0) | Out-Null
            if ((Invoke-SmokeHttp GET "$base/health").Status -eq 200) { throw 'The server still answers after Stop.' }
            $started = Invoke-SmokeProcess $installPwsh ($pwshArgs + @((Join-Path $install 'scripts\Start-ChannelForge.ps1'), '-NoBrowser', '-Port', [string]$Port))
            Assert-SmokeRun $started 'Start after restart' ($started.ExitCode -eq 0) | Out-Null
            $after = Get-SmokeStatus $Port
            $after.LineupStatus -ceq $state.Before.LineupStatus -and $after.SourcesStatus -ceq $state.Before.SourcesStatus -and $after.PlaylistStatus -ceq $state.Before.PlaylistStatus
        }
        Invoke-SmokeStep 'refresh' $script:StepPlan[11][1] {
            $reply = Invoke-SmokeHttp POST "$base/api/sources/refresh"
            if ($reply.Status -ne 200) { throw "Refresh answered $($reply.Status): $($reply.Body)" }
            ($reply.Body | ConvertFrom-Json).Status -cin @('UP_TO_DATE', 'CHANGES_FOUND')
        }
        $updater = Join-Path $install 'tools\Invoke-ChannelForgeAutoUpdate.ps1'
        Invoke-SmokeStep 'update-check-local' $script:StepPlan[12][1] {
            $run = Invoke-SmokeProcess $installPwsh ($pwshArgs + @($updater, '-PackageRoot', $bundle, '-InstallRoot', $install))
            Assert-SmokeRun $run 'Update check' ($run.ExitCode -eq 0 -and $run.Output -match 'Package valid')
        }
        Invoke-SmokeStep 'update-same-version' $script:StepPlan[13][1] {
            $before = (Get-FileHash -LiteralPath (Join-Path $install 'package-manifest.json') -Algorithm SHA256).Hash
            $run = Invoke-SmokeProcess $installPwsh ($pwshArgs + @($updater, '-Apply', '-PackageRoot', $bundle, '-InstallRoot', $install))
            $after = (Get-FileHash -LiteralPath (Join-Path $install 'package-manifest.json') -Algorithm SHA256).Hash
            Assert-SmokeRun $run 'Same-version update' ($run.ExitCode -ne 0 -and $run.Output -match 'not newer' -and $before -ceq $after)
        }
        Skip-SmokeStep 'update-check-github' $script:StepPlan[14][1] 'The sandbox has networking turned off on purpose, so a GitHub release check cannot run.'

        # The sandbox does not deliver typed menu answers, so only "the menu ran and cancelled" is proven here.
        Invoke-SmokeStep 'uninstall-cancel' $script:StepPlan[15][1] {
            $run = Invoke-SmokeUninstallCmd $bundle @('2', 'delete')
            $kept = (Test-Path -LiteralPath (Join-Path $install 'package-manifest.json')) -and (Test-Path -LiteralPath (Join-Path $install 'state') -PathType Container)
            Assert-SmokeRun $run 'Uninstall menu (cancel)' ($run.Output -match 'Cancelled' -and $kept)
        }
        Invoke-SmokeStep 'uninstall-keep' $script:StepPlan[16][1] {
            $run = Invoke-SmokeUninstallCmd $bundle -ArgumentList @('-Verbose')
            $appGone = -not (Test-Path -LiteralPath (Join-Path $install 'package-manifest.json')) -and -not (Test-Path -LiteralPath (Join-Path $install 'scripts'))
            $dataKept = Test-Path -LiteralPath (Join-Path $install 'state\source-enrollment.json') -PathType Leaf
            $stopped = (Invoke-SmokeHttp GET "$base/health").Status -ne 200
            Assert-SmokeRun $run 'Uninstall (keep data)' ($appGone -and $dataKept -and $stopped)
        }
        Invoke-SmokeStep 'uninstall-delete' $script:StepPlan[17][1] {
            $run = Invoke-SmokeUninstallCmd $bundle -ArgumentList @('-PurgeData', '-ConfirmPurge')
            Test-SmokeRootRemoved -Root $install -Run $run
        }
    }
    catch { if ([string]$_.Exception.Message -notlike 'smoke-halt:*') { Add-SmokeStep -Id 'run' -Name 'Smoke run' -Status 'FAIL' -Detail ([string]$_.Exception.Message) } }
    finally {
        $result = Write-SmokeEvidence -Steps @($script:Steps) -PlannedIds $planned -ResultsRoot $ResultsRoot -PackageFilename ([string]$expected.PackageFilename) -PackageSha256 $script:zipHash -SourceCommitSha $script:manifestCommit -StartedUtc $started
    }
    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    $outcome = Invoke-SmokeRun -InputRoot $InputRoot -ResultsRoot $ResultsRoot -Port $Port -StepTimeoutSeconds $StepTimeoutSeconds -OverallTimeoutMinutes $OverallTimeoutMinutes
    Write-Output "Smoke result: $($outcome.Overall). Evidence: $($outcome.JsonPath)"
}
