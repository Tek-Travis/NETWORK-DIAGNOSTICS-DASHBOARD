param($Work,$Signal,$Updates)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$WarningPreference='SilentlyContinue'
function Emit($Item) {$Updates.Enqueue($Item)}
function CheckStop {if ($Signal.Stop) {throw [OperationCanceledException]::new('Stopped by user.')}}
function Tcp([string]$Address,[int]$Port,[int]$Timeout) {
 $client=[Net.Sockets.TcpClient]::new(([Net.IPAddress]::Parse($Address)).AddressFamily);$wait=$null
 try {$a=$client.BeginConnect([Net.IPAddress]::Parse($Address),$Port,$null,$null);$wait=$a.AsyncWaitHandle;if (-not $wait.WaitOne($Timeout)) {return 'NO RESPONSE'};$client.EndConnect($a);return 'OPEN'}
 catch {$e=$_.Exception.GetBaseException();if ($e -is [Net.Sockets.SocketException] -and $e.SocketErrorCode -eq [Net.Sockets.SocketError]::ConnectionRefused) {return 'REFUSED'};return 'ERROR/UNREACHABLE'}
 finally {$client.Close();if ($null -ne $wait) {$wait.Close()}}
}
function SkipDnsName([byte[]]$Bytes,[ref]$Position) {
 $p=[int]$Position.Value;$steps=0
 while($true) {
  if ($p -ge $Bytes.Length -or ++$steps -gt 128) {throw 'Malformed DNS record name.'}
  $n=[int]$Bytes[$p];$p++
  if ($n -eq 0) {break}
  if (($n -band 192) -eq 192) {if ($p -ge $Bytes.Length) {throw 'Truncated DNS pointer.'};$p++;break}
  if ($n -gt 63 -or $p+$n -gt $Bytes.Length) {throw 'Malformed DNS name label.'};$p+=$n
 }
 $Position.Value=$p
}
function Query([string]$Transport,[string]$Endpoint,[string]$Domain,[int]$Timeout) {
 $watch=[Diagnostics.Stopwatch]::new();$response=$null;$reader=$null;$udp=$null
 try {
  if ($Transport -eq 'DoH') {
   $request=[Net.HttpWebRequest]::Create($Endpoint+'?name='+[Uri]::EscapeDataString($Domain)+'&type=A')
   $request.Method='GET';$request.Accept='application/dns-json';$request.UserAgent='NetworkDashboard/5.0';$request.Timeout=$Timeout;$request.ReadWriteTimeout=$Timeout;$request.AllowAutoRedirect=$false;$request.KeepAlive=$true
   $request.CachePolicy=[Net.Cache.RequestCachePolicy]::new([Net.Cache.RequestCacheLevel]::NoCacheNoStore)
   $watch.Start();$response=$request.GetResponse();$reader=[IO.StreamReader]::new($response.GetResponseStream());$body=$reader.ReadToEnd();$watch.Stop();$ms=$watch.Elapsed.TotalMilliseconds
   if ([int]$response.StatusCode -ne 200) {throw "HTTP $([int]$response.StatusCode)"}
   $json=$body | ConvertFrom-Json
   if ($null -eq $json.PSObject.Properties['Status'] -or [int]$json.Status -ne 0 -or $json.TC) {throw 'Negative, truncated or unsupported DNS JSON response.'}
   if (@($json.Answer | Where-Object {[int]$_.type -eq 1}).Count -eq 0) {throw 'No A answer returned.'}
   return [pscustomobject]@{Ms=$ms;Outcome='SUCCESS';Detail='Positive A answer; elapsed HTTPS headers/body time, excluding JSON parsing.'}
  }
  $id=Get-Random -Minimum 0 -Maximum 65536;$bytes=[Collections.Generic.List[byte]]::new()
  foreach($b in @([byte]($id -shr 8),[byte]($id -band 255),1,0,0,1,0,0,0,0,0,0)) {$bytes.Add([byte]$b)}
  foreach($label in $Domain.TrimEnd('.').Split('.')) {$bytes.Add([byte]$label.Length);$bytes.AddRange([Text.Encoding]::ASCII.GetBytes($label))}
  $bytes.AddRange([byte[]]@(0,0,1,0,1));$packet=$bytes.ToArray();$ip=[Net.IPAddress]::Parse($Endpoint)
  $udp=[Net.Sockets.UdpClient]::new($ip.AddressFamily);$udp.Client.ReceiveTimeout=$Timeout;$udp.Client.SendTimeout=$Timeout;$udp.Connect($ip,53)
  $any=[Net.IPAddress]::Any;if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {$any=[Net.IPAddress]::IPv6Any};$remote=[Net.IPEndPoint]::new($any,0)
  $watch.Start();[void]$udp.Send($packet,$packet.Length);$reply=$udp.Receive([ref]$remote);$watch.Stop();$ms=$watch.Elapsed.TotalMilliseconds
  if ($reply.Length -lt $packet.Length -or $reply[0] -ne $packet[0] -or $reply[1] -ne $packet[1] -or ($reply[2] -band 128) -eq 0) {throw 'Invalid DNS transaction response.'}
  if ($reply[4] -ne 0 -or $reply[5] -ne 1) {throw 'Unexpected DNS question count.'}
  for($i=12;$i -lt $packet.Length;$i++) {if ($reply[$i] -ne $packet[$i]) {throw 'DNS question mismatch.'}}
  if (($reply[2] -band 2) -ne 0) {throw 'Truncated UDP response; no TCP retry implemented.'}
  $rcode=$reply[3] -band 15;if ($rcode -ne 0) {throw "DNS response code $rcode"}
  $count=[int]$reply[6]*256+$reply[7];$pos=$packet.Length;$found=$false
  for($i=0;$i -lt $count;$i++) {
   SkipDnsName $reply ([ref]$pos)
   if ($pos+10 -gt $reply.Length) {throw 'Truncated resource record.'}
   $type=[int]$reply[$pos]*256+$reply[$pos+1];$class=[int]$reply[$pos+2]*256+$reply[$pos+3];$length=[int]$reply[$pos+8]*256+$reply[$pos+9];$pos+=10
   if ($pos+$length -gt $reply.Length) {throw 'Truncated answer data.'}
   if ($type -eq 1 -and $class -eq 1 -and $length -eq 4) {$found=$true};$pos+=$length
  }
  if (-not $found) {throw 'No IPv4 A answer in DNS response.'}
  return [pscustomobject]@{Ms=$ms;Outcome='SUCCESS';Detail='Positive UDP A answer; elapsed send/receive time, excluding packet construction/validation.'}
 } catch {
  $e=$_.Exception.GetBaseException();$outcome='ERROR';if ($e -is [Net.WebException] -and $null -ne $e.Response) {try {$e.Response.Close()} catch {}}
  if (($e -is [Net.Sockets.SocketException] -and $e.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut) -or ($e -is [Net.WebException] -and $e.Status -eq [Net.WebExceptionStatus]::Timeout)) {$outcome='TIMEOUT'}
  return [pscustomobject]@{Ms=$null;Outcome=$outcome;Detail=$e.Message}
 } finally {if ($null -ne $reader) {$reader.Dispose()};if ($null -ne $response) {$response.Close()};if ($null -ne $udp) {$udp.Close()}}
}
try {
 CheckStop
 switch($Work.Kind) {
  'discover' {
   $adapters=@(foreach($n in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {try {
    $p=$n.GetIPProperties();$v4=-1;$v6=-1;try {$v4=$p.GetIPv4Properties().Index} catch {};try {$v6=$p.GetIPv6Properties().Index} catch {}; $speed=0;try {$speed=$n.Speed} catch {}
    $addresses=@($p.UnicastAddresses | ForEach-Object {$_.Address.ToString()})
    foreach($u in $p.UnicastAddresses) {if ($u.Address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {continue};$prefix=0;foreach($b in $u.IPv4Mask.GetAddressBytes()) {$prefix += [Convert]::ToString($b,2).Replace('0','').Length}
     [pscustomobject]@{Name=$n.Name;Type=$n.NetworkInterfaceType.ToString();State=$n.OperationalStatus.ToString();Index=$v4;IPv6Index=$v6;Address=$u.Address.ToString();Prefix=$prefix;AllAddresses=$addresses;Dns=@($p.DnsAddresses | ForEach-Object {$_.ToString()});Gateways=@($p.GatewayAddresses | ForEach-Object {$_.Address.ToString()});LinkMbps=([double]$speed/1000000)}
    }
   } catch {}})
   $routes=@();$notes=@();foreach($dest in @('1.1.1.1','2606:4700:4700::1111')) {CheckStop;try {
    $x=@(Find-NetRoute -RemoteIPAddress $dest -ErrorAction Stop);$r=$x | Where-Object {$_.PSObject.Properties['NextHop']} | Select-Object -First 1;$a=$x | Where-Object {$_.PSObject.Properties['IPAddress']} | Select-Object -First 1
    if ($null -ne $r) {$routes += [pscustomobject]@{Destination=$dest;Index=[int]$r.InterfaceIndex;NextHop=[string]$r.NextHop;Source=[string]$a.IPAddress}}
   } catch {$notes += $_.Exception.Message}}
   $neighbors=@();try {$neighbors=@(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop | Select-Object IPAddress,LinkLayerAddress,InterfaceIndex,State)} catch {}
   Emit ([pscustomobject]@{Kind='discovery';Adapters=$adapters;Routes=$routes;Neighbors=$neighbors;Notes=$notes})
  }
  'neighbors' { $neighbors=@(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop | Select-Object IPAddress,LinkLayerAddress,InterfaceIndex,State);Emit ([pscustomobject]@{Kind='neighbors';Neighbors=$neighbors}) }
  'ping' {
   for($i=1;$i -le 10;$i++) {CheckStop;$ms=$null;$detail='';$p=[Net.NetworkInformation.Ping]::new()
    try {$r=$p.Send($Work.Address,1500);$detail=$r.Status.ToString();if ($r.Status -eq [Net.NetworkInformation.IPStatus]::Success) {$ms=[double]$r.RoundtripTime}} catch {$detail=$_.Exception.GetBaseException().Message} finally {$p.Dispose()}
    Emit ([pscustomobject]@{Kind='sample';Address=$Work.Address;Name=$Work.Name;Ms=$ms;Detail=$detail;Time=[DateTimeOffset]::Now.ToString('o')})
    if ($i -lt 10) {for($j=0;$j -lt 10;$j++) {CheckStop;Start-Sleep -Milliseconds 100}}
   }
  }
  'services' {
   function Result([string]$Name,[string]$State,[string]$Detail) {Emit ([pscustomobject]@{Kind='check';Test=$Name;State=$State;Detail=$Detail;Time=[DateTimeOffset]::Now.ToString('o')})}
   foreach($server in @($Work.Dns | Select-Object -Unique -First 2)) {CheckStop;$r=Query 'UDP' $server 'example.com' 2000;$state='FAIL';if ($r.Outcome -eq 'SUCCESS') {$state='PASS'};Result "Configured DNS $server" $state "$($r.Outcome) / $($r.Ms) ms / $($r.Detail)"}
   foreach($ip in @('1.1.1.1','8.8.8.8')) {CheckStop;$sw=[Diagnostics.Stopwatch]::StartNew();$r=Tcp $ip 443 3500;$state='FAIL';if ($r -eq 'OPEN') {$state='PASS'};Result "TCP ${ip}:443" $state "$r / $($sw.ElapsedMilliseconds) ms"}
   [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
   foreach($url in @('https://www.microsoft.com/','https://www.cloudflare.com/')) {CheckStop;$response=$null;$sw=[Diagnostics.Stopwatch]::StartNew();$state='FAIL'
    try {$req=[Net.HttpWebRequest]::Create($url);$req.Method='HEAD';$req.Timeout=6000;$req.ReadWriteTimeout=6000;$req.MaximumAutomaticRedirections=5;$response=$req.GetResponse();$code=[int]$response.StatusCode;if ($code -ge 200 -and $code -lt 400) {$state='PASS'};$detail="HTTP $code / $($sw.ElapsedMilliseconds) ms including DNS/TLS; default proxy; normal certificate validation"} catch {$detail=$_.Exception.GetBaseException().Message} finally {if ($null -ne $response) {$response.Close()}};Result "HTTPS $url" $state $detail
   }
  }
  'scan' {
   $ms=$null;$p=[Net.NetworkInformation.Ping]::new();try {$r=$p.Send($Work.Address,700);if ($r.Status -eq [Net.NetworkInformation.IPStatus]::Success) {$ms=[double]$r.RoundtripTime}} catch {} finally {$p.Dispose()}
   $responded=$null -ne $ms;$ports=@();foreach($port in $Work.Ports) {CheckStop;$state=Tcp $Work.Address $port 350;$ports += "${port}:$state";if ($state -in @('OPEN','REFUSED')) {$responded=$true}}
   $hostname='';if ($Work.Names -and $responded) {try {$a=[Net.Dns]::BeginGetHostEntry([string]$Work.Address,$null,$null);$wait=$a.AsyncWaitHandle;try {if ($wait.WaitOne(1200)) {$hostname=[Net.Dns]::EndGetHostEntry($a).HostName}} finally {$wait.Close()}} catch {}}
   $state='NO RESPONSE';if ($responded) {$state='RESPONDED'};Emit ([pscustomobject]@{Kind='device';Address=$Work.Address;Hostname=$hostname;State=$state;Ms=$ms;Ports=($ports -join '; ');Mac=$Work.Mac;Time=[DateTimeOffset]::Now.ToString('o')})
  }
  'benchmark' {
   [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
   $warm=Query $Work.Transport $Work.Endpoint $Work.Domains[0] $Work.Timeout;Emit ([pscustomobject]@{Kind='warmup';Text="$($Work.Name) warm-up: $($warm.Outcome), not counted"})
   for($round=1;$round -le $Work.Repetitions;$round++) {foreach($domain in $Work.Domains) {CheckStop;$r=Query $Work.Transport $Work.Endpoint $domain $Work.Timeout
    Emit ([pscustomobject]@{Kind='dns';Provider=$Work.Name;Transport=$Work.Transport;Endpoint=$Work.Endpoint;Domain=$domain;Round=$round;Outcome=$r.Outcome;Ms=$r.Ms;Detail=$r.Detail;Time=[DateTimeOffset]::Now.ToString('o')})
    for($j=0;$j -lt 2;$j++) {CheckStop;Start-Sleep -Milliseconds 100}
   }}
  }
  'trace' {
   $reached=$false
   for($ttl=1;$ttl -le 20;$ttl++) {CheckStop;$p=[Net.NetworkInformation.Ping]::new();$sw=[Diagnostics.Stopwatch]::StartNew()
    try {$r=$p.Send('1.1.1.1',900,[byte[]]::new(32),[Net.NetworkInformation.PingOptions]::new($ttl,$true));$addr='*';if ($null -ne $r.Address) {$addr=$r.Address.ToString()};$line=('{0,2}  {1,-24} {2} / {3} ms elapsed' -f $ttl,$addr,$r.Status,$sw.ElapsedMilliseconds);$reached=$r.Status -eq [Net.NetworkInformation.IPStatus]::Success} catch {$line="$ttl  $($_.Exception.GetBaseException().Message)"} finally {$p.Dispose()}
    Emit ([pscustomobject]@{Kind='trace';Text=$line});if ($reached) {break}
   }
   $line='Hop limit reached; destination not confirmed.';if ($reached) {$line='Destination replied.'};Emit ([pscustomobject]@{Kind='trace';Text=$line})
  }
 }
} catch {Emit ([pscustomobject]@{Kind='error';Text="$($Work.Kind) $($Work.Address): $($_.Exception.GetBaseException().Message)"})}
