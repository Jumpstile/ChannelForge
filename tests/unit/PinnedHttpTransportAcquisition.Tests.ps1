BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModuleSourceRoot = Join-Path $RepoRoot 'src\ChannelForge'
    $script:PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $script:PowerShellExecutable -PathType Leaf)) { $script:PowerShellExecutable = (Get-Command pwsh -ErrorAction Stop).Source }
    $script:ResultMarker = 'CHANNELFORGE_PINNED_ACQUISITION_RESULT:'
    $script:ChildScriptPath = Join-Path $TestDrive 'Invoke-PinnedHttpTransportAcquisitionSuiteChild.ps1'
    $script:ChildScript = @'
param([Parameter(Mandatory)][string]$ModulePath)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:ResultMarker = 'CHANNELFORGE_PINNED_ACQUISITION_RESULT:'
function Limit-Text {
    param([AllowNull()][object]$Value,[int]$Limit=4000)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($text.Length -le $Limit) { return $text }
    $text.Substring(0,$Limit) + '...<truncated>'
}
function Safe-Message {
    param([AllowNull()][object]$Value)
    [regex]::Replace((Limit-Text $Value),'(?i)\b(?:https?|ftp)://[^\s"]+','<redacted-url>')
}
function Write-Result {
    param([Parameter(Mandatory)][object]$Value)
    try {
        $json = $Value | ConvertTo-Json -Compress -Depth 20 -ErrorAction Stop
        [Console]::Out.WriteLine($script:ResultMarker + $json)
    } catch {
        $fallback = [ordered]@{Protocol='ChannelForge.PinnedHttpAcquisitionSuite.v1';Success=$false;HarnessFailure=$true;FailureCategory='SerializationFailure';FailurePhase='Serialization';Message=(Safe-Message $_.Exception.Message);Scenarios=@()}
        [Console]::Out.WriteLine($script:ResultMarker + ($fallback | ConvertTo-Json -Compress -Depth 10))
        exit 1
    }
}
function Get-Details {
    param([Parameter(Mandatory)][System.Exception]$Exception)
    $e = $Exception
    while ($null -ne $e.InnerException -and $null -eq $e.PSObject.Properties['Category']) { $e = $e.InnerException }
    [pscustomobject]@{Category=if($null -ne $e.PSObject.Properties['Category']){[string]$e.Category}else{$null};Phase=if($null -ne $e.PSObject.Properties['Phase']){[string]$e.Phase}else{$null};StatusCode=if($null -ne $e.PSObject.Properties['StatusCode']){$e.StatusCode}else{$null};Message=(Safe-Message $e.Message)}
}
function New-Milestones {
    [ordered]@{ListenerStarted=$false;HandlerCreated=$false;AcquisitionStarted=$false;ConnectionAccepted=$false;TlsHandshakeStarted=$false;TlsHandshakeCompleted=$false;RequestReceived=$false;ResponseSent=$false;PayloadAcquired=$false;BodyRead=$false;CleanupCompleted=$false}
}
function New-Actual {
    param([System.Collections.IDictionary]$Values,[System.Collections.IDictionary]$Milestones)
    $result=[ordered]@{};foreach($entry in $Values.GetEnumerator()){$result[$entry.Key]=$entry.Value};$result.Milestones=$Milestones;[pscustomobject]$result
}
function Get-HelperType {
    $module=Get-Module ChannelForge;if($null -eq $module){throw 'ChannelForge module was not imported'};$helper=& $module {Initialize-ChannelForgePinnedHttpTransport};if($null -eq $helper -or $null -eq $helper.Type){throw 'pinned HTTP transport helper did not load'};$helper.Type
}
function New-Endpoint {
    param([string]$Address)
    $type=$script:Helper.Assembly.GetType('ChannelForge.Private.Transport.ChannelForgeValidatedEndpoint',$true,$false);$constructor=@($type.GetConstructors([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic)|Where-Object{$_.GetParameters().Count -eq 5})[0];$ips=[Collections.Generic.List[Net.IPAddress]]::new();$ips.Add([Net.IPAddress]::Parse($Address))|Out-Null;$constructor.Invoke([object[]]@([Uri]'https://transport.test.invalid/acquisition-test','transport.test.invalid',443,$false,$ips))
}
function New-Options {
    param([long]$Max=64,[string]$Policy='Require200',[bool]$AllowMissing=$false,[string]$Source='acquisition-test')
    $optionsType=$script:Helper.Assembly.GetType('ChannelForge.Private.Transport.ChannelForgeHttpAcquisitionOptions',$true,$false);$policyType=$script:Helper.Assembly.GetType('ChannelForge.Private.Transport.ChannelForgeHttpStatusPolicy',$true,$false);$constructor=@($optionsType.GetConstructors([Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::Public)|Where-Object{$_.GetParameters().Count -eq 5})[0];$constructor.Invoke([object[]]@($Source,[string[]]@('application/octet-stream'),$AllowMissing,$Max,[Enum]::Parse($policyType,$Policy)))
}
function New-Handler { param($Endpoint) $method=$script:Helper.GetMethod('CreatePinnedHandlerForTest',[Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic);$method.Invoke($null,[object[]]@($Endpoint)) }
function Start-Acquisition { param($Endpoint,$Options,$Handler,[TimeSpan]$Header,[TimeSpan]$Body,[TimeSpan]$Total,[Threading.CancellationToken]$Token) $method=$script:Helper.GetMethod('AcquireGetForTestAsync',[Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic);$method.Invoke($null,[object[]]@($Endpoint,$Options,$Handler,$Header,$Body,$Total,$Token)) }
function New-Certificates {
    param([string]$Name)
    $notBefore=[DateTimeOffset]::UtcNow.AddMinutes(-5);$notAfter=[DateTimeOffset]::UtcNow.AddMinutes(30);$rootKey=[Security.Cryptography.RSA]::Create(2048);$rootRequest=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=ChannelForge Test Root',$rootKey,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1);$rootRequest.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))|Out-Null;$root=$rootRequest.CreateSelfSigned($notBefore,$notAfter);$serverKey=[Security.Cryptography.RSA]::Create(2048);$serverRequest=[Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=$Name",$serverKey,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1);$san=[Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new();$san.AddDnsName($Name)|Out-Null;$serverRequest.CertificateExtensions.Add($san.Build($false))|Out-Null;$unsigned=$serverRequest.Create($root,$notBefore,$notAfter,[byte[]](1,2,3,4));$pem="-----BEGIN CERTIFICATE-----"+[Environment]::NewLine+[Convert]::ToBase64String($unsigned.RawData,[Base64FormattingOptions]::InsertLineBreaks)+[Environment]::NewLine+"-----END CERTIFICATE-----";$server=[Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($pem,$serverKey.ExportPkcs8PrivateKeyPem());$password='ChannelForge-test';$pfx=$server.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,$password);$server.Dispose();$server=[Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx,$password,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet -bor [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet);[pscustomobject]@{Root=$root;Server=$server;RootKey=$rootKey;ServerKey=$serverKey;Unsigned=$unsigned}
}
function Send-Response {
    param([IO.Stream]$Stream,[int]$Code,[string]$Reason,[byte[]]$Body,[string[]]$Headers=@(),[switch]$Chunked,[switch]$HeadersOnly)
    $lines=[Collections.Generic.List[string]]::new();[void]$lines.Add("HTTP/1.1 $Code $Reason");[void]$lines.Add('Connection: close');foreach($header in $Headers){[void]$lines.Add($header)};if($Chunked){[void]$lines.Add('Transfer-Encoding: chunked')}elseif(-not $HeadersOnly){[void]$lines.Add("Content-Length: $($Body.Length)")};$headerBytes=[Text.Encoding]::ASCII.GetBytes(($lines -join [Environment]::NewLine)+[Environment]::NewLine+[Environment]::NewLine);[void]$Stream.Write($headerBytes,0,$headerBytes.Length);[void]$Stream.Flush();if($HeadersOnly){return};if($Chunked -and $Body.Length -gt 0){$chunkBytes=[Text.Encoding]::ASCII.GetBytes(("{0:X}{1}{2}" -f $Body.Length,[char]13,[char]10));[void]$Stream.Write($chunkBytes,0,$chunkBytes.Length);[void]$Stream.Write($Body,0,$Body.Length);$tail=[byte[]](13,10,48,13,10,13,10);[void]$Stream.Write($tail,0,$tail.Length)}elseif(-not $Chunked -and $Body.Length -gt 0){[void]$Stream.Write($Body,0,$Body.Length)};[void]$Stream.Flush()
}
function Read-Body { param($Payload,[System.Collections.IDictionary]$Milestones) $buffer=[byte[]]::new(128);$bytes=[Collections.Generic.List[byte]]::new();while(($read=$Payload.ResponseStream.Read($buffer,0,$buffer.Length)) -gt 0){for($index=0;$index -lt $read;$index++){$bytes.Add($buffer[$index])}};$Milestones.BodyRead=$true;[Text.Encoding]::UTF8.GetString($bytes.ToArray()) }
function New-Scenario { param([string]$Name,[string]$Address,[System.Collections.IDictionary]$Expected) [pscustomobject]@{Name=$Name;Address=$Address;Port=443;Expected=$Expected} }
function Get-Scenarios {
    $hostName='transport.test.invalid'
    @(
        (New-Scenario 'success' '127.0.0.2' ([ordered]@{Success=$true;Category=$null;Phase=$null;StatusCode=200;Disposition='Payload';ContentType='application/octet-stream';Encodings=@();HasPayload=$true;ResponseStreamNull=$false;Body='hello';Sni=$hostName;RequestLine='GET /acquisition-test HTTP/1.1'}))
        (New-Scenario '304-default' '127.0.0.3' ([ordered]@{Success=$false;Category='RedirectRejected';StatusCode=304;Phase='Headers'}))
        (New-Scenario '304-authorized' '127.0.0.4' ([ordered]@{Success=$true;Category=$null;Phase=$null;StatusCode=304;Disposition='MetadataOnly';ContentType=$null;Encodings=@();HasPayload=$false;ResponseStreamNull=$true;Body=$null;Sni=$hostName;RequestLine='GET /acquisition-test HTTP/1.1'}))
        (New-Scenario 'redirect' '127.0.0.5' ([ordered]@{Success=$false;Category='RedirectRejected';StatusCode=302;Phase='Headers'}))
        (New-Scenario 'status' '127.0.0.6' ([ordered]@{Success=$false;Category='NonSuccessHttpStatus';StatusCode=404;Phase='Headers'}))
        (New-Scenario 'content-type' '127.0.0.7' ([ordered]@{Success=$false;Category='UnsupportedContentType';StatusCode=$null;Phase='Headers'}))
        (New-Scenario 'missing-type' '127.0.0.8' ([ordered]@{Success=$true;Category=$null;Phase=$null;StatusCode=200;Disposition='Payload';ContentType=$null;Encodings=@();HasPayload=$true;ResponseStreamNull=$false;Body='hello';Sni=$hostName;RequestLine='GET /acquisition-test HTTP/1.1'}))
        (New-Scenario 'encoding' '127.0.0.9' ([ordered]@{Success=$true;Category=$null;Phase=$null;StatusCode=200;Disposition='Payload';ContentType='application/octet-stream';Encodings=@('gzip','br');HasPayload=$true;ResponseStreamNull=$false;Body='hello';Sni=$hostName;RequestLine='GET /acquisition-test HTTP/1.1'}))
        (New-Scenario 'header-limit' '127.0.0.10' ([ordered]@{Success=$false;Category='ResponseTooLarge';StatusCode=$null;Phase='Headers'}))
        (New-Scenario 'body-limit' '127.0.0.11' ([ordered]@{Success=$false;Category='ResponseTooLarge';StatusCode=$null;Phase='Body'}))
        (New-Scenario 'exact-limit' '127.0.0.12' ([ordered]@{Success=$true;Category=$null;Phase=$null;StatusCode=200;Disposition='Payload';ContentType='application/octet-stream';Encodings=@();HasPayload=$true;ResponseStreamNull=$false;Body='abcde';Sni=$hostName;RequestLine='GET /acquisition-test HTTP/1.1'}))
        (New-Scenario 'inactivity' '127.0.0.13' ([ordered]@{Success=$false;Category='Timeout';StatusCode=$null;Phase='BodyInactivity'}))
        (New-Scenario 'total' '127.0.0.14' ([ordered]@{Success=$false;Category='Timeout';StatusCode=$null;Phase='Total'}))
        (New-Scenario 'cancel' '127.0.0.15' ([ordered]@{Success=$false;Category='Cancelled';StatusCode=$null;Phase='Headers'}))
        (New-Scenario 'header-timeout' '127.0.0.16' ([ordered]@{Success=$false;Category='Timeout';StatusCode=$null;Phase='Headers'}))
        (New-Scenario 'tls-mismatch' '127.0.0.17' ([ordered]@{Success=$false;Category='TlsFailure';StatusCode=$null;Phase='Headers'}))
        (New-Scenario 'source-id' '127.0.0.18' ([ordered]@{Success=$true;Category=$null;Phase=$null;Rejected=$true;Message=[ordered]@{Matches='SourceId contains unsupported metadata characters\.'}}))
    )
}
function Run-Scenario {
    param($Definition)
    $name=[string]$Definition.Name;$certificateName=if($name -eq 'tls-mismatch'){'other.test.invalid'}else{'transport.test.invalid'};$milestones=New-Milestones;$chain=$null;$listener=$null;$accept=$null;$handler=$null;$payload=$null;$client=$null;$ssl=$null;$request=$null;$sni=[pscustomobject]@{Name=$null};$cancellation=[Threading.CancellationTokenSource]::new();$result=$null
    try {
        $chain=New-Certificates $certificateName;$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse([string]$Definition.Address),443);$listener.Start();$milestones.ListenerStarted=$true;$accept=$listener.AcceptTcpClientAsync();$endpoint=New-Endpoint ([string]$Definition.Address);$handler=New-Handler $endpoint;$milestones.HandlerCreated=$true;$policy=[Security.Cryptography.X509Certificates.X509ChainPolicy]::new();$policy.TrustMode=[Security.Cryptography.X509Certificates.X509ChainTrustMode]::CustomRootTrust;$policy.RevocationMode=[Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck;$policy.CustomTrustStore.Add($chain.Root)|Out-Null;$handler.SslOptions.CertificateChainPolicy=$policy
        if($name -eq 'source-id'){try{$null=New-Options -Source 'https://secret.invalid/token';$result=New-Actual ([ordered]@{Success=$false;UnexpectedSuccess=$true}) $milestones}catch{$result=New-Actual ([ordered]@{Success=$true;Rejected=$true;Message=(Safe-Message $_.Exception.Message)}) $milestones}}else{
            $options=if($name -eq '304-authorized'){New-Options -Policy Allow304MetadataOnly}elseif($name -in @('header-limit','body-limit','exact-limit')){New-Options -Max 5}elseif($name -eq 'missing-type'){New-Options -AllowMissing $true}else{New-Options};$headerTimeout=if($name -eq 'header-timeout'){[TimeSpan]::FromMilliseconds(100)}else{[TimeSpan]::FromSeconds(2)};$bodyTimeout=if($name -eq 'inactivity'){[TimeSpan]::FromMilliseconds(100)}else{[TimeSpan]::FromSeconds(2)};$totalTimeout=[TimeSpan]::FromSeconds(3);if($name -eq 'cancel'){$cancellation.CancelAfter(100)};$task=Start-Acquisition $endpoint $options $handler $headerTimeout $bodyTimeout $totalTimeout $cancellation.Token;$milestones.AcquisitionStarted=$true;if(-not $accept.Wait(5000)){throw 'local listener received no connection'};$client=$accept.GetAwaiter().GetResult();$milestones.ConnectionAccepted=$true;$ssl=[Net.Security.SslStream]::new($client.GetStream(),$false);$sslOptions=[Net.Security.SslServerAuthenticationOptions]::new();$tlsCallbacks=[ChannelForgePinnedAcquisitionTlsCallbacks]::new($chain.Server,'transport.test.invalid');$sslOptions.ServerCertificateSelectionCallback=$tlsCallbacks.CreateSelectionCallback();$milestones.TlsHandshakeStarted=$true
            try{$null=$ssl.AuthenticateAsServerAsync($sslOptions).GetAwaiter().GetResult();$sni.Name=[string]$tlsCallbacks.ServerName;$milestones.TlsHandshakeCompleted=$true}catch{$sni.Name=[string]$tlsCallbacks.ServerName;if($name -eq 'tls-mismatch'){$result=New-Actual ([ordered]@{Success=$false;Category='TlsFailure';Phase='Tls';Message=(Safe-Message $_.Exception.Message);Sni=$sni.Name}) $milestones}else{throw}}
            if($null -eq $result){if($name -eq 'header-timeout'){try{$null=$task.GetAwaiter().GetResult();$result=New-Actual ([ordered]@{Success=$false;UnexpectedSuccess=$true;Sni=$sni.Name}) $milestones}catch{$d=Get-Details $_.Exception;$result=New-Actual ([ordered]@{Success=$false;Category=$d.Category;Phase=$d.Phase;Sni=$sni.Name;Message=$d.Message}) $milestones}}else{
                $requestBytes=[byte[]]::new(8192);$requestReadTask=$ssl.ReadAsync($requestBytes,0,$requestBytes.Length);if($task.Wait(500) -and $task.IsFaulted){$d=Get-Details $task.Exception;$result=New-Actual ([ordered]@{Success=$false;Category=$d.Category;Phase=$d.Phase;StatusCode=$d.StatusCode;Sni=$sni.Name;Message=$d.Message}) $milestones};if($null -eq $result){if(-not $requestReadTask.Wait(5000)){throw 'local TLS server did not receive the HTTP request'};$request=[Text.Encoding]::ASCII.GetString($requestBytes,0,$requestReadTask.Result);$milestones.RequestReceived=$true;$body=[Text.Encoding]::UTF8.GetBytes('hello');$code=200;$reason='OK';$headers=@('Content-Type: application/octet-stream');$chunked=$false;$headersOnly=$false;switch($name){'304-default'{$code=304;$reason='Not Modified';$headers=@()};'304-authorized'{$code=304;$reason='Not Modified';$headers=@()};'redirect'{$code=302;$reason='Found';$headers=@('Location: https://redirect.test.invalid/next')};'status'{$code=404;$reason='Not Found';$headers=@()};'content-type'{$headers=@('Content-Type: text/plain')};'missing-type'{$headers=@()};'encoding'{$headers=@('Content-Type: application/octet-stream','Content-Encoding: gzip','Content-Encoding: br')};'header-limit'{$body=[Text.Encoding]::UTF8.GetBytes('hello world')};'body-limit'{$body=[Text.Encoding]::UTF8.GetBytes('abcdef');$chunked=$true};'exact-limit'{$body=[Text.Encoding]::UTF8.GetBytes('abcde');$chunked=$true};'inactivity'{$headersOnly=$true};'total'{$headersOnly=$true};'cancel'{$headersOnly=$true}};Send-Response $ssl $code $reason $body $headers -Chunked:$chunked -HeadersOnly:$headersOnly;$milestones.ResponseSent=$true;try{$payload=$task.GetAwaiter().GetResult();$milestones.PayloadAcquired=$true}catch{$d=Get-Details $_.Exception;$result=New-Actual ([ordered]@{Success=$false;Category=$d.Category;Phase=$d.Phase;StatusCode=$d.StatusCode;Sni=$sni.Name;RequestLine=if($request){($request -split '\r?\n')[0]}else{$null};Message=$d.Message}) $milestones};if($null -eq $result){if($name -in @('inactivity','total','cancel')){$readCancellation=$null;try{if($name -eq 'total'){Start-Sleep -Milliseconds 3200};if($name -eq 'cancel'){$readCancellation=[Threading.CancellationTokenSource]::new();$readCancellation.CancelAfter(100);$null=$payload.ResponseStream.ReadAsync([byte[]]::new(32),0,32,$readCancellation.Token).GetAwaiter().GetResult()}else{$null=$payload.ResponseStream.Read([byte[]]::new(32),0,32)};$result=New-Actual ([ordered]@{Success=$false;UnexpectedSuccess=$true;Sni=$sni.Name}) $milestones}catch{$d=Get-Details $_.Exception;$result=New-Actual ([ordered]@{Success=$false;Category=$d.Category;Phase=$d.Phase;Sni=$sni.Name;Message=$d.Message}) $milestones}finally{if($readCancellation){$readCancellation.Dispose()}}}else{$bodyText=if($payload.HasPayload){Read-Body $payload $milestones}else{$null};$result=New-Actual ([ordered]@{Success=$true;StatusCode=$payload.StatusCode;Disposition=[string]$payload.StatusDisposition;ContentType=$payload.ContentType;Encodings=@($payload.ContentEncodings);HasPayload=$payload.HasPayload;ResponseStreamNull=$null -eq $payload.ResponseStream;Body=$bodyText;Sni=$sni.Name;RequestLine=($request -split '\r?\n')[0]}) $milestones}}}
            }}
        }
    } catch {
        $d=Get-Details $_.Exception;$category=if($d.Category){$d.Category}elseif($name -eq 'tls-mismatch' -and $milestones.TlsHandshakeStarted){'TlsFailure'}else{'HarnessFailure'};$phase=if($d.Phase){$d.Phase}elseif(-not $milestones.ListenerStarted){'Listener'}elseif(-not $milestones.ConnectionAccepted){'Listener'}elseif(-not $milestones.TlsHandshakeCompleted){'Tls'}else{'Harness'};$result=New-Actual ([ordered]@{Success=$false;Category=$category;Phase=$phase;StatusCode=$d.StatusCode;Message=$d.Message;RequestLine=if($request){($request -split '\r?\n')[0]}else{$null};Sni=$sni.Name}) $milestones
    } finally {
        $cleanupError=$null;try{if($payload){$payload.Dispose()};if($ssl){$ssl.Dispose()};if($client){$client.Dispose()};if($handler){$handler.Dispose()};$cancellation.Dispose();if($listener){$listener.Stop()};if($chain){$chain.Server.Dispose();$chain.Root.Dispose();$chain.ServerKey.Dispose();$chain.RootKey.Dispose();$chain.Unsigned.Dispose()}}catch{$cleanupError=$_.Exception};$milestones.CleanupCompleted=$null -eq $cleanupError;if($cleanupError){$result=New-Actual ([ordered]@{Success=$false;Category='HarnessFailure';Phase='Cleanup';Message=(Safe-Message $cleanupError.Message)}) $milestones}
    }
    if($null -eq $result){$result=New-Actual ([ordered]@{Success=$false;Category='HarnessFailure';Phase='Serialization';Message='scenario returned no structured result'}) $milestones};$result
}
function Get-Property { param($Object,[string]$Name) if($Object -is [System.Collections.IDictionary]){if($Object.Contains($Name)){return [pscustomobject]@{Present=$true;Value=$Object[$Name]}};return [pscustomobject]@{Present=$false;Value=$null}};$property=$Object.PSObject.Properties[$Name];if($null -eq $property){return [pscustomobject]@{Present=$false;Value=$null}};[pscustomobject]@{Present=$true;Value=$property.Value} }
function Test-Value { param($Actual,$Expected) if($Expected -is [System.Collections.IDictionary] -and $Expected.Contains('Matches')){return [regex]::IsMatch([string]$Actual,[string]$Expected['Matches'])};if($Expected -is [System.Array] -or $Actual -is [System.Array]){$a=@($Actual);$e=@($Expected);if($a.Count -ne $e.Count){return $false};for($i=0;$i -lt $a.Count;$i++){if(-not (Test-Value $a[$i] $e[$i])){return $false}};return $true};if($Expected -is [bool]){return [bool]$Actual -eq [bool]$Expected};if($null -eq $Expected){return $null -eq $Actual};[string]$Actual -ceq [string]$Expected }
function Compare-Outcome { param($Actual,[System.Collections.IDictionary]$Expected)
    $mismatches=[Collections.Generic.List[string]]::new()
    foreach($entry in $Expected.GetEnumerator()){
        $property=Get-Property $Actual $entry.Key
        if(-not $property.Present){
            if($null -eq $entry.Value -and $entry.Key -in @('Category','Phase','StatusCode')){continue}
            $mismatches.Add("$($entry.Key) missing")
        }elseif(-not (Test-Value $property.Value $entry.Value)){
            $mismatches.Add("$($entry.Key) expected $([string]$entry.Value), actual $([string]$property.Value)")
        }
    }
    [pscustomobject]@{Matched=$mismatches.Count -eq 0;Mismatches=$mismatches.ToArray()}
}
try {
    Import-Module (Join-Path $ModulePath 'ChannelForge.psd1') -Force
    $script:Helper=Get-HelperType
    $script:TlsCallbackType = Add-Type -TypeDefinition @"
using System;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading;

public sealed class ChannelForgePinnedAcquisitionTlsCallbacks
{
    private readonly X509Certificate2 _certificate;
    private readonly string _expectedServerName;
    private string _serverName;
    private int _selectionCount;

    public ChannelForgePinnedAcquisitionTlsCallbacks(X509Certificate2 certificate, string expectedServerName)
    {
        _certificate = certificate ?? throw new ArgumentNullException(nameof(certificate));
        _expectedServerName = expectedServerName ?? throw new ArgumentNullException(nameof(expectedServerName));
    }

    public string ServerName => Volatile.Read(ref _serverName);
    public int SelectionCount => Volatile.Read(ref _selectionCount);
    public bool ServerNameMatchesExpected =>
        string.Equals(ServerName, _expectedServerName, StringComparison.OrdinalIgnoreCase);

    public ServerCertificateSelectionCallback CreateSelectionCallback() => Select;

    public X509Certificate Select(object sender, string serverName)
    {
        Volatile.Write(ref _serverName, serverName);
        Interlocked.Increment(ref _selectionCount);
        return _certificate;
    }
}
"@ -PassThru | Select-Object -First 1
    $definitions=@(Get-Scenarios)
    if($definitions.Count -ne 17){throw "expected 17 acquisition scenarios, found $($definitions.Count)"}
    if(@($definitions|ForEach-Object{$_.Name}|Sort-Object -Unique).Count -ne $definitions.Count){throw 'scenario names are not unique'}
    if(@($definitions|ForEach-Object{$_.Address}|Sort-Object -Unique).Count -ne $definitions.Count){throw 'loopback addresses are not unique'}
    if(@($definitions|ForEach-Object{$_.Port}|Where-Object{$_ -ne 443}).Count -ne 0){throw 'listener port changed from 443'}
    $results=@(foreach($definition in $definitions){$actual=Run-Scenario $definition;$comparison=Compare-Outcome $actual $definition.Expected;[pscustomobject]@{Scenario=$definition.Name;Address=$definition.Address;Port=443;Expected=$definition.Expected;Actual=$actual;Matched=[bool]$comparison.Matched;Mismatches=@($comparison.Mismatches)}})
    $failed=@($results|Where-Object{-not $_.Matched})
    $envelope=[ordered]@{Protocol='ChannelForge.PinnedHttpAcquisitionSuite.v1';Success=$failed.Count -eq 0;ScenarioCount=$results.Count;ProcessModel='one-child-acquisition-suite';ModuleImportedOnce=$true;HelperLoadedOnce=$true;Scenarios=$results;Diagnostics=[ordered]@{Execution='sequential';Port=443;UniqueLoopbackAddresses=$true;FailedScenarios=@($failed|ForEach-Object{[ordered]@{Scenario=$_.Scenario;Mismatches=@($_.Mismatches)}})}}
    Write-Result $envelope
    if($failed.Count -gt 0){exit 1}
    exit 0
} catch {
    $d=Get-Details $_.Exception;Write-Result ([ordered]@{Protocol='ChannelForge.PinnedHttpAcquisitionSuite.v1';Success=$false;HarnessFailure=$true;FailureCategory=if($d.Category){$d.Category}else{'HarnessFailure'};FailurePhase=if($d.Phase){$d.Phase}else{'Harness'};Message=$d.Message;Scenarios=@();Diagnostics=[ordered]@{Execution='sequential';Port=443;UniqueLoopbackAddresses=$true}});exit 1
}
'@
    $script:ChildScript.ToString() | Set-Content -LiteralPath $script:ChildScriptPath -Encoding utf8
    function New-PinnedTransportAcquisitionModuleCopy {
        $modulePath = Join-Path $TestDrive ('ChannelForgePinnedAcquisition-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
        Get-ChildItem -LiteralPath $script:ModuleSourceRoot -Force | Copy-Item -Destination $modulePath -Recurse -Force
        $modulePath
    }
    function Limit-PinnedTransportDiagnosticText {
        param([AllowNull()][object]$Value,[int]$Limit=5000)
        $text=if($null -eq $Value){''}else{[string]$Value};$text=[regex]::Replace($text,'(?i)\b(?:https?|ftp)://[^\s"]+','<redacted-url>');if($text.Length -le $Limit){return $text};$text.Substring(0,$Limit)+'...<truncated>'
    }
    function Get-PinnedTransportSuiteFailureMessage {
        param($Suite)
        $parts=[Collections.Generic.List[string]]::new();if($Suite.HarnessError){$parts.Add("harness=$($Suite.HarnessError)")};if($Suite.ProcessTimedOut){$parts.Add('process timed out after 120000ms')};if([int]$Suite.ProcessExitCode -ne 0){$parts.Add("child-exit=$($Suite.ProcessExitCode)")};foreach($scenario in @($Suite.Scenarios|Where-Object{-not [bool]$_.Matched})){$parts.Add("scenario=$($scenario.Scenario);mismatches=$(@($scenario.Mismatches)-join ', ');actual=$(Limit-PinnedTransportDiagnosticText ($scenario.Actual|ConvertTo-Json -Compress -Depth 10) 2500)")};if($Suite.ErrorOutput){$parts.Add("stderr=$(Limit-PinnedTransportDiagnosticText $Suite.ErrorOutput)")};if($Suite.StandardOutput){$parts.Add("stdout=$(Limit-PinnedTransportDiagnosticText $Suite.StandardOutput)")};if($parts.Count -eq 0){return 'acquisition child suite failed without diagnostics'};$parts -join ' | '
    }
    function Invoke-PinnedTransportAcquisitionSuite {
        param([string]$ModulePath)
        $process=$null;$startError=$null;$stdout='';$stderr='';$exitCode=-1;$timedOut=$false
        try {
            $startInfo=[Diagnostics.ProcessStartInfo]::new();$startInfo.FileName=$script:PowerShellExecutable;$startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true;$startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true;$startInfo.WorkingDirectory=$RepoRoot;foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$script:ChildScriptPath,'-ModulePath',$ModulePath)){[void]$startInfo.ArgumentList.Add($argument)};$process=[Diagnostics.Process]::new();$process.StartInfo=$startInfo;if(-not $process.Start()){throw 'could not start acquisition child process'};$stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync();$timedOut=-not $process.WaitForExit(120000);if($timedOut){try{$process.Kill($true)}catch{};$process.WaitForExit()};$stdout=$stdoutTask.GetAwaiter().GetResult();$stderr=$stderrTask.GetAwaiter().GetResult();if(-not $timedOut){$exitCode=$process.ExitCode}
        } catch {$startError=Limit-PinnedTransportDiagnosticText $_.Exception.Message} finally {if($process){$process.Dispose()}}
        $base=[ordered]@{Success=$false;ProcessExitCode=$exitCode;ProcessTimedOut=$timedOut;HarnessError=$null;Scenarios=@();StandardOutput=(Limit-PinnedTransportDiagnosticText $stdout);ErrorOutput=(Limit-PinnedTransportDiagnosticText $stderr)};if($startError){$base.HarnessError=$startError;return [pscustomobject]$base};if($timedOut){$base.HarnessError='acquisition child process timed out';return [pscustomobject]$base};$markerLines=@($stdout -split '\r?\n'|Where-Object{$_ -like "$($script:ResultMarker)*"});if($markerLines.Count -lt 1){$base.HarnessError='acquisition child produced no structured result marker';return [pscustomobject]$base};try{$envelope=$markerLines[-1].Substring($script:ResultMarker.Length)|ConvertFrom-Json -Depth 20 -ErrorAction Stop}catch{$base.HarnessError="acquisition child result serialization was invalid: $(Limit-PinnedTransportDiagnosticText $_.Exception.Message)";return [pscustomobject]$base};if([string]$envelope.Protocol -ne 'ChannelForge.PinnedHttpAcquisitionSuite.v1' -or $null -eq $envelope.PSObject.Properties['Success'] -or $null -eq $envelope.PSObject.Properties['Scenarios']){$base.HarnessError='acquisition child result envelope was incomplete';return [pscustomobject]$base};[pscustomobject]@{Success=[bool]$envelope.Success;ProcessExitCode=$exitCode;ProcessTimedOut=$false;HarnessError=if($envelope.HarnessFailure){[string]$envelope.Message}else{$null};Scenarios=@($envelope.Scenarios);Diagnostics=$envelope.Diagnostics;StandardOutput=if($envelope.Success){''}else{$base.StandardOutput};ErrorOutput=$base.ErrorOutput}
    }
    function Get-PinnedTransportScenarioResult {
        param([string]$Scenario)
        $suite=$script:AcquisitionSuite;if($null -eq $suite){throw 'acquisition child suite did not initialize'};if($suite.HarnessError -or $suite.ProcessTimedOut -or [int]$suite.ProcessExitCode -ne 0 -or -not [bool]$suite.Success){throw (Get-PinnedTransportSuiteFailureMessage $suite)};$matches=@($suite.Scenarios|Where-Object{$_.Scenario -eq $Scenario});if($matches.Count -ne 1){throw "acquisition child suite returned $($matches.Count) results for '$Scenario'"};if(-not [bool]$matches[0].Matched){throw "acquisition child suite marked '$Scenario' mismatched"};$matches[0].Actual
    }
    $script:ModulePath=New-PinnedTransportAcquisitionModuleCopy
    try{$script:AcquisitionSuite=Invoke-PinnedTransportAcquisitionSuite -ModulePath $script:ModulePath}catch{$script:AcquisitionSuite=[pscustomobject]@{Success=$false;ProcessExitCode=-1;ProcessTimedOut=$false;HarnessError=(Limit-PinnedTransportDiagnosticText $_.Exception.Message);Scenarios=@();StandardOutput='';ErrorOutput=''}}
}
Describe 'ChannelForge bounded HTTPS acquisition' {
    It 'streams 200 payloads with stable metadata and canonical TLS host' {$r=Get-PinnedTransportScenarioResult 'success';$r.Success|Should -BeTrue -Because ($r|ConvertTo-Json -Compress);$r.StatusCode|Should -Be 200;$r.Disposition|Should -Be Payload;$r.ContentType|Should -Be 'application/octet-stream';$r.Body|Should -Be hello;$r.Sni|Should -Be 'transport.test.invalid';$r.RequestLine|Should -Match '^GET /acquisition-test HTTP/'}
    It 'rejects ordinary 304 and other non-success statuses without redirects' {$a=Get-PinnedTransportScenarioResult '304-default';$b=Get-PinnedTransportScenarioResult 'redirect';$c=Get-PinnedTransportScenarioResult 'status';$a.Category|Should -Be RedirectRejected;$a.StatusCode|Should -Be 304;$b.Category|Should -Be RedirectRejected;$c.Category|Should -Be NonSuccessHttpStatus;$c.StatusCode|Should -Be 404}
    It 'surfaces authorized 304 as metadata only' {$r=Get-PinnedTransportScenarioResult '304-authorized';$r.Success|Should -BeTrue;$r.Disposition|Should -Be MetadataOnly;$r.HasPayload|Should -BeFalse;$r.ResponseStreamNull|Should -BeTrue}
    It 'validates content type and preserves ordered encoding metadata' {$a=Get-PinnedTransportScenarioResult 'content-type';$b=Get-PinnedTransportScenarioResult 'missing-type';$c=Get-PinnedTransportScenarioResult 'encoding';$a.Category|Should -Be UnsupportedContentType;$b.Body|Should -Be hello;@($c.Encodings)|Should -Be @('gzip','br');$c.Body|Should -Be hello}
    It 'enforces header and streamed bounds while accepting the exact limit' {$a=Get-PinnedTransportScenarioResult 'header-limit';$b=Get-PinnedTransportScenarioResult 'body-limit';$c=Get-PinnedTransportScenarioResult 'exact-limit';$a.Category|Should -Be ResponseTooLarge;$a.Phase|Should -Be Headers;$b.Category|Should -Be ResponseTooLarge;$b.Phase|Should -Be Body;$c.Body|Should -Be abcde}
    It 'distinguishes inactivity, total deadline, and caller cancellation' {$a=Get-PinnedTransportScenarioResult 'inactivity';$b=Get-PinnedTransportScenarioResult 'total';$c=Get-PinnedTransportScenarioResult 'cancel';$a.Category|Should -Be Timeout;$a.Phase|Should -Be BodyInactivity;$b.Category|Should -Be Timeout;$b.Phase|Should -Be Total;$c.Category|Should -Be Cancelled}
    It 'bounds header wait and preserves TLS hostname for the pinned IP connection' {$a=Get-PinnedTransportScenarioResult 'header-timeout';$b=Get-PinnedTransportScenarioResult 'success';$a.Category|Should -Be Timeout;$a.Phase|Should -Be Headers;$b.Sni|Should -Be 'transport.test.invalid'}
    It 'fails mismatched certificate validation and rejects URL-shaped source identity' {$a=Get-PinnedTransportScenarioResult 'tls-mismatch';$b=Get-PinnedTransportScenarioResult 'source-id';$a.Category|Should -Be TlsFailure;$b.Rejected|Should -BeTrue;$b.Message|Should -Not -Match 'secret|https?://'}
}
