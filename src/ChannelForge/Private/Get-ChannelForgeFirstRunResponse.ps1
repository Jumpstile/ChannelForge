function Get-ChannelForgeFirstRunPage {
    param([switch]$ShowNetworkWarning)
    $warning = if ($ShowNetworkWarning) {
        '<p class="warn"><b>Warning:</b> you opened this page from another computer over plain HTTP. Anyone on the network could read the password you type. Stop here, and set up HTTPS first.</p>'
    }
    else { '' }
    $minutes = [int](Get-ChannelForgeSetupCodeLifetime).TotalMinutes
    $page = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ChannelForge first-time setup</title>
<style>
body{font-family:sans-serif;max-width:40em;margin:2em auto;padding:0 1em;line-height:1.5}
.warn{border:2px solid #b00020;padding:.5em;background:#fdecea}
label{display:block;margin:.8em 0 .2em}
input{font-size:1em;padding:.3em;width:100%;box-sizing:border-box}
button{font-size:1em;margin-top:1em;padding:.4em 1em}
#msg{color:#b00020;font-weight:bold}
</style>
</head>
<body>
<h1>ChannelForge first-time setup</h1>
{{WARNING}}
<p>This is a server. Other people on your network may be able to reach it. A password keeps them from using ChannelForge or changing your channels.</p>
<p>Next step: type the setup code, then choose a password.</p>
<h2>The setup code</h2>
<p>The setup code was printed on the server console, the window where ChannelForge is running. It proves that you have access to the server. It works once and stops working after {{MINUTES}} minutes. If it stops working, start the server again to get a new one.</p>
<h2>Your password</h2>
<p>Pick a strong password of at least 12 characters. There is no email reset. If you forget it, a reset needs access to the server machine.</p>
<p>This connection is plain HTTP unless you put HTTPS in front of it. With plain HTTP, passwords can be read on the network. We recommend a reverse proxy with HTTPS.</p>
<form id="f">
<label for="code">Setup code</label>
<input id="code" autocomplete="off" required>
<label for="pw">New password</label>
<input id="pw" type="password" autocomplete="new-password" required>
<label for="pw2">New password again</label>
<input id="pw2" type="password" autocomplete="new-password" required>
<button type="submit">Set password</button>
</form>
<p id="msg" role="alert"></p>
<script>
document.getElementById('f').addEventListener('submit',function(e){
e.preventDefault();
var m=document.getElementById('msg');m.textContent='';
var pw=document.getElementById('pw').value;
if(pw!==document.getElementById('pw2').value){m.textContent='The two passwords are not the same.';return;}
fetch('/first-run/submit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:document.getElementById('code').value,password:pw})})
.then(function(r){return r.json().then(function(j){return {ok:r.ok,j:j};});})
.then(function(x){if(x.ok){location.href='/';}else{m.textContent=x.j.Message||'Something went wrong.';}})
.catch(function(){m.textContent='Could not reach the server.';});
});
</script>
</body>
</html>
'@
    return $page.Replace('{{WARNING}}', $warning).Replace('{{MINUTES}}', [string]$minutes)
}

function Invoke-ChannelForgeFirstRunSubmit {
    <#
    .SYNOPSIS
        Checks the setup code and the new password, saves the password file, and signs the browser in.
    .DESCRIPTION
        A bad code gets one uniform message. A bad password keeps the code usable. A failed save keeps the code
        unused and leaves no password file behind. Nothing secret is echoed or logged.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [Parameter(Mandatory)][hashtable]$Setup,
        [System.IO.Stream]$BodyStream = $null,
        [long]$ContentLength = -1,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][string]$CookieFormat,
        [hashtable]$Limiter = $null,
        [string]$SourceAddress = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    $waitResponse = Get-ChannelForgeSignInWaitResponse -Limiter $Limiter -Address $SourceAddress -Now $Now
    if ($null -ne $waitResponse) { return $waitResponse }
    $code = $null
    $password = $null
    try {
        $bytes = Read-ChannelForgeWebRequestBody -Stream $BodyStream -ContentLength $ContentLength -MaxBytes 4096
        $body = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
        $code = [string]$body.code
        $password = [string]$body.password
    }
    catch { $code = $null }

    if (-not (Test-ChannelForgeSetupCode -Setup $Setup -Code $code -Now $Now)) {
        if ($null -ne $Limiter) { Register-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress -Now $Now }
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 401 -Body @{ Error = 'setup-code-failed'; Message = 'That setup code did not work.' }
    }
    if ($null -ne $Limiter) { Clear-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress }
    $rule = Test-ChannelForgeAdminPasswordRule -Password $password
    if (-not $rule.Ok) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 400 -Body @{ Error = 'password-rule'; Message = $rule.Reason }
    }
    $saved = Write-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot -Record (New-ChannelForgeAdminPasswordRecord -Password $password)
    if (-not $saved.Success) {
        # The file did not exist a moment ago, so a file left by a failed permission step is ours to remove.
        if ($saved.Category -eq 'PermissionFailed') { Remove-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot | Out-Null }
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 500 -Body @{ Error = 'password-not-saved'; Message = 'The password could not be saved. Check that ChannelForge can write to its settings folder. The setup code was not used, so you can try again.' }
    }
    $Setup.Used = $true
    $token = New-ChannelForgeWebSession -Store $Store -Now $Now
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ SignedIn = $true } -ExtraHeaders @{ 'Set-Cookie' = ($CookieFormat -f $token) }
}

function Get-ChannelForgeFirstRunResponse {
    <#
    .SYNOPSIS
        Serves GET /first-run (the page) and POST /first-run/submit while the server is in setup state.
    #>
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][hashtable]$Store,
        [Parameter(Mandatory)][hashtable]$Setup,
        [System.IO.Stream]$BodyStream = $null,
        [long]$ContentLength = -1,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][string]$CookieFormat,
        [string]$RequestHost = '',
        [hashtable]$Limiter = $null,
        [string]$SourceAddress = '',
        [switch]$Secure,
        [datetime]$Now = [datetime]::UtcNow
    )
    $methodName = $Method.ToUpperInvariant()
    if ($RequestPath -eq '/first-run/submit') {
        if ($methodName -ne 'POST') { return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'Only POST requests are supported.' } -ExtraHeaders @{ Allow = 'POST' } }
        return Invoke-ChannelForgeFirstRunSubmit -Store $Store -Setup $Setup -BodyStream $BodyStream -ContentLength $ContentLength -ConfigRoot $ConfigRoot -CookieFormat $CookieFormat -Limiter $Limiter -SourceAddress $SourceAddress -Now $Now
    }
    if ($methodName -ne 'GET') { return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'Only GET requests are supported.' } -ExtraHeaders @{ Allow = 'GET' } }
    # The start guard calls a loopback address Ready; anything else in setup state is a network address.
    $remote = -not $Secure -and -not [string]::IsNullOrWhiteSpace($RequestHost) -and (Get-ChannelForgeStartGuard -Address $RequestHost -ConfigRoot $ConfigRoot -AllowSetupMode).State -ne 'Ready'
    $headers = [ordered]@{ 'Cache-Control' = 'no-store'; 'X-Content-Type-Options' = 'nosniff' }
    return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'text/html; charset=utf-8' -Body (Get-ChannelForgeFirstRunPage -ShowNetworkWarning:$remote) -Headers $headers
}
