# Network Diagnostics Dashboard 5.0 / Windows PowerShell 5.1
# All tasks are manual. Loading or selecting a tab NEVER starts network work.
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') {throw 'Windows is required.'}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {throw 'Use Start Dashboard.cmd or powershell.exe -STA -File .\NetworkDashboard.ps1'}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$enginePath=Join-Path $PSScriptRoot 'Engine.ps1'
if (-not (Test-Path -LiteralPath $enginePath)) {throw 'Engine.ps1 is missing. Extract all files from the ZIP before running.'}
$script:Worker=[IO.File]::ReadAllText($enginePath)
$script:Pool=$null;$script:Pending=[Collections.Generic.Queue[object]]::new();$script:Active=[Collections.Generic.List[object]]::new();$script:Updates=[Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:Signal=[hashtable]::Synchronized(@{Stop=$false});$script:Mode='idle';$script:TaskTotal=0;$script:TaskDone=0;$script:Parallel=8;$script:Closing=$false;$script:RepeatAt=$null;$script:RepeatTargets=@()
$script:Adapters=@();$script:Routes=@();$script:Neighbors=@();$script:Targets=@();$script:Providers=@();$script:Samples=@{};$script:Cards=@{}
$script:Devices=[Collections.Generic.List[object]]::new();$script:Checks=[Collections.Generic.List[object]]::new();$script:DnsSamples=[Collections.Generic.List[object]]::new()
$script:Map='IDLE / No discovery has run. Select Overview and press START to read network configuration.'
$script:Trace='IDLE / Select this tab and press START to trace the IPv4 route toward 1.1.1.1.'
$script:DnsExpected=0;$script:DnsTransport='UDP';$script:StatsSnapshot='';$script:DeviceMap=''
$script:Font=[Drawing.Font]::new('Segoe UI',10)
$script:Mono=[Drawing.Font]::new('Consolas',10)
$script:Small=[Drawing.Font]::new('Consolas',9)
$script:Big=[Drawing.Font]::new('Consolas',21)
$script:Colors=@{Bg=[Drawing.Color]::Black;Surface=[Drawing.Color]::FromArgb(20,20,24);Text=[Drawing.Color]::White;Muted=[Drawing.ColorTranslator]::FromHtml('#C0C5D7');Border=[Drawing.ColorTranslator]::FromHtml('#AAB1C6');Accent=[Drawing.ColorTranslator]::FromHtml('#4E5891');Green=[Drawing.Color]::FromArgb(66,222,133);Red=[Drawing.Color]::FromArgb(255,95,108);Disabled=[Drawing.Color]::FromArgb(145,149,160)}
function Status([string]$Text) {$script:StatusLabel.Text=$Text}
function Log([string]$Text) {$script:LogBox.AppendText(('{0:HH:mm:ss} {1}' -f (Get-Date),$Text)+"`r`n");if ($script:LogBox.TextLength -gt 50000) {$script:LogBox.Text=$script:LogBox.Text.Substring($script:LogBox.TextLength-40000)}}
function Button([string]$Text,$Parent) {$b=[Windows.Forms.Button]::new();$b.Text=$Text;$b.AutoSize=$true;$b.MinimumSize=[Drawing.Size]::new(125,44);$b.FlatStyle='Flat';$b.Margin=[Windows.Forms.Padding]::new(6);$Parent.Controls.Add($b);return $b}
function Label([string]$Text,$Parent) {$l=[Windows.Forms.Label]::new();$l.Text=$Text;$l.AutoSize=$true;$l.MaximumSize=[Drawing.Size]::new(760,0);$l.Margin=[Windows.Forms.Padding]::new(6,9,6,8);$Parent.Controls.Add($l);return $l}
function Edit([string]$Text,$Parent,[int]$Width=220) {$e=[Windows.Forms.TextBox]::new();$e.Text=$Text;$e.Width=$Width;$e.Margin=[Windows.Forms.Padding]::new(6,9,6,6);$Parent.Controls.Add($e);return $e}
function Choice([string]$Text,$Parent,[bool]$Checked=$false) {$r=[Windows.Forms.RadioButton]::new();$r.Text=$Text;$r.AutoSize=$true;$r.MinimumSize=[Drawing.Size]::new(200,42);$r.Checked=$Checked;$r.Margin=[Windows.Forms.Padding]::new(6);$Parent.Controls.Add($r);return $r}
function Check([string]$Text,$Parent,[bool]$Checked=$false) {$c=[Windows.Forms.CheckBox]::new();$c.Text=$Text;$c.AutoSize=$true;$c.MinimumSize=[Drawing.Size]::new(200,42);$c.Checked=$Checked;$c.Margin=[Windows.Forms.Padding]::new(6);$Parent.Controls.Add($c);return $c}
function Flow($Parent) {$f=[Windows.Forms.FlowLayoutPanel]::new();$f.Dock='Fill';$f.WrapContents=$true;$f.AutoScroll=$true;$Parent.Controls.Add($f);return $f}
function ReadBox($Parent) {$t=[Windows.Forms.TextBox]::new();$t.Dock='Fill';$t.Multiline=$true;$t.ReadOnly=$true;$t.ScrollBars='Vertical';$t.WordWrap=$true;$t.BorderStyle='None';$t.Font=$script:Mono;$Parent.Controls.Add($t);return $t}
function SplitPage($Parent,[int]$Height) {$t=[Windows.Forms.TableLayoutPanel]::new();$t.Dock='Fill';$t.RowCount=2;$t.ColumnCount=1;[void]$t.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$Height));[void]$t.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100));$Parent.Controls.Add($t);$top=[Windows.Forms.Panel]::new();$top.Dock='Fill';$bottom=[Windows.Forms.Panel]::new();$bottom.Dock='Fill';$t.Controls.Add($top,0,0);$t.Controls.Add($bottom,0,1);return [pscustomobject]@{Layout=$t;Top=$top;Bottom=$bottom}}
function Grid($Parent,[string[]]$Names) {$g=[Windows.Forms.DataGridView]::new();$g.Dock='Fill';$g.ReadOnly=$true;$g.AllowUserToAddRows=$false;$g.AllowUserToDeleteRows=$false;$g.RowHeadersVisible=$false;$g.AutoSizeColumnsMode='Fill';$g.AutoSizeRowsMode='AllCells';$g.DefaultCellStyle.WrapMode='True';$g.EnableHeadersVisualStyles=$false;foreach($n in $Names) {[void]$g.Columns.Add($n,$n);$g.Columns[$n].MinimumWidth=75};$Parent.Controls.Add($g);return $g}
function Page([string]$Text) {$p=[Windows.Forms.TabPage]::new($Text);$p.Padding=[Windows.Forms.Padding]::new(8);$script:Tabs.TabPages.Add($p);return $p}
function InnerTabs($Parent,[string[]]$Names) {$t=[Windows.Forms.TabControl]::new();$t.Dock='Fill';$t.Multiline=$true;$t.ItemSize=[Drawing.Size]::new(140,36);$t.SizeMode='Fixed';foreach($n in $Names) {$p=[Windows.Forms.TabPage]::new($n);$p.Padding=[Windows.Forms.Padding]::new(6);$t.TabPages.Add($p)};$Parent.Controls.Add($t);return $t}
function Heat([double]$Ms) {$v=[Math]::Max(0,[Math]::Min(1,$Ms/200));[Drawing.Color]::FromArgb([int](46+209*$v),[int](156-80*$v),[int](255-164*$v))}
function DrawText($G,[string]$Text,$Font,$Color,[single]$X,[single]$Y) {$b=[Drawing.SolidBrush]::new($Color);try {$G.DrawString($Text,$Font,$b,$X,$Y)} finally {$b.Dispose()}}
function ApplyTheme($Control) {
 $Control.BackColor=$script:Colors.Bg;$Control.ForeColor=$script:Colors.Text
 if ($Control -is [Windows.Forms.TextBox] -or $Control -is [Windows.Forms.ListBox] -or $Control -is [Windows.Forms.CheckedListBox] -or $Control -is [Windows.Forms.NumericUpDown]) {$Control.BackColor=$script:Colors.Surface}
 if ($Control -is [Windows.Forms.Button]) {$Control.BackColor=$script:Colors.Surface;$Control.FlatAppearance.BorderColor=$script:Colors.Border}
 if ($Control -is [Windows.Forms.DataGridView]) {
  $Control.BackgroundColor=$script:Colors.Bg;$Control.GridColor=$script:Colors.Border;$Control.DefaultCellStyle.BackColor=$script:Colors.Surface;$Control.DefaultCellStyle.ForeColor=$script:Colors.Text;$Control.DefaultCellStyle.SelectionBackColor=$script:Colors.Accent;$Control.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White;$Control.ColumnHeadersDefaultCellStyle.BackColor=$script:Colors.Surface;$Control.ColumnHeadersDefaultCellStyle.ForeColor=$script:Colors.Text
  return
 }
 foreach($child in $Control.Controls) {ApplyTheme $child}
}
function SetTheme([bool]$Light) {
 if ($Light) {$script:Colors.Bg=[Drawing.Color]::White;$script:Colors.Surface=[Drawing.Color]::FromArgb(244,245,249);$script:Colors.Text=[Drawing.Color]::FromArgb(15,15,18);$script:Colors.Muted=[Drawing.ColorTranslator]::FromHtml('#4E5891');$script:Colors.Green=[Drawing.Color]::FromArgb(0,116,58);$script:Colors.Red=[Drawing.Color]::FromArgb(184,25,43)}
 else {$script:Colors.Bg=[Drawing.Color]::Black;$script:Colors.Surface=[Drawing.Color]::FromArgb(20,20,24);$script:Colors.Text=[Drawing.Color]::White;$script:Colors.Muted=[Drawing.ColorTranslator]::FromHtml('#C0C5D7');$script:Colors.Green=[Drawing.Color]::FromArgb(66,222,133);$script:Colors.Red=[Drawing.Color]::FromArgb(255,95,108)}
 ApplyTheme $script:Form;$script:Tabs.Invalidate();foreach($card in $script:Cards.Values) {$card.Invalidate()};RefreshSemanticColors
}
function RefreshSemanticColors {
 foreach($row in $script:DeviceGrid.Rows) {$color=$script:Colors.Disabled;if ([string]$row.Cells[2].Value -eq 'RESPONDED') {$color=$script:Colors.Green};$row.Cells[2].Style.ForeColor=$color}
 foreach($row in $script:CheckGrid.Rows) {$color=$script:Colors.Red;if ([string]$row.Cells[1].Value -eq 'PASS') {$color=$script:Colors.Green};$row.Cells[1].Style.ForeColor=$color}
 foreach($row in $script:DnsDetails.Rows) {$color=$script:Colors.Red;if ([string]$row.Cells[3].Value -eq 'SUCCESS') {$color=$script:Colors.Green};$row.Cells[3].Style.ForeColor=$color}
}
function PaintCard($Target,$G) {
 $G.SmoothingMode='AntiAlias';$s=$script:Samples[$Target.Address];$n=$s.Count;$good=@($s | Where-Object {$null -ne $_.Ms}).Count;$state='READY';$color=$script:Colors.Disabled
 if ($n) {$state='NO REPLY';$color=$script:Colors.Red;if ($null -ne $s[$n-1].Ms) {$state='REPLY OK';$color=$script:Colors.Green}}
 if ($n -eq 10) {$state='FAIL';$color=$script:Colors.Red;if ($good -eq 10) {$state='PASS';$color=$script:Colors.Green}}
 if ($script:Mode -ne 'Internet Tests' -and $n -gt 0 -and $n -lt 10) {$state='PARTIAL';$color=$script:Colors.Disabled}
 $pen=[Drawing.Pen]::new($color,2);try {$G.DrawRectangle($pen,1,1,330,251)} finally {$pen.Dispose()}
 DrawText $G $Target.Name $script:Mono $script:Colors.Text 10 10;DrawText $G $Target.Address $script:Small $script:Colors.Muted 10 32;DrawText $G $state $script:Mono $color 10 53
 for($i=0;$i -lt 40;$i++) {$pen=[Drawing.Pen]::new((Heat ($i*200/39)),8);try {$G.DrawArc($pen,100,85,130,130,[single](150+$i*6),[single]5)} finally {$pen.Dispose()}}
 $reading='-- ms';if ($n -gt 0 -and $null -ne $s[$n-1].Ms) {$ms=$s[$n-1].Ms;$reading=('{0:0} ms' -f $ms);$angle=(150+[Math]::Min(200,$ms)*1.2)*[Math]::PI/180;$pen=[Drawing.Pen]::new($script:Colors.Text,2);try {$G.DrawLine($pen,[single]165,[single]150,[single](165+53*[Math]::Cos($angle)),[single](150+53*[Math]::Sin($angle)))} finally {$pen.Dispose()}}
 DrawText $G $reading $script:Big $script:Colors.Text 115 164;DrawText $G '0 ms          200+ ms' $script:Small $script:Colors.Muted 90 192
 for($i=0;$i -lt 10;$i++) {$h=$script:Colors.Surface;$fail=$false;if ($i -lt $n) {if ($null -eq $s[$i].Ms) {$h=$script:Colors.Red;$fail=$true} else {$h=Heat $s[$i].Ms}};$b=[Drawing.SolidBrush]::new($h);try {$G.FillRectangle($b,10+$i*31,215,26,16)} finally {$b.Dispose()};if ($fail) {DrawText $G 'X' $script:Small ([Drawing.Color]::White) (17+$i*31) 215}}
 $text='Not tested';if ($n) {$text='{0}/{1} replies / {2:0}% ICMP loss' -f $good,$n,(100*($n-$good)/$n)};DrawText $G $text $script:Small $script:Colors.Text 10 235
}
function IpNumber([string]$Text) {$ip=$null;if (-not [Net.IPAddress]::TryParse($Text,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {throw "Invalid IPv4: $Text"};$b=$ip.GetAddressBytes();[uint64]($b[0]*16777216.0+$b[1]*65536.0+$b[2]*256.0+$b[3])}
function NumberIp([uint64]$N) {'{0}.{1}.{2}.{3}' -f ([Math]::Floor($N/16777216)%256),([Math]::Floor($N/65536)%256),([Math]::Floor($N/256)%256),($N%256)}
function BeginBatch([string]$Name,$Works,[int]$Parallel=8) {
 if ($script:Mode -ne 'idle') {return};$script:RepeatAt=$null
 if ($null -eq $script:Pool) {$script:Pool=[RunspaceFactory]::CreateRunspacePool(1,16);$script:Pool.Open()}
 $script:Signal=[hashtable]::Synchronized(@{Stop=$false});$script:Mode=$Name;$script:TaskTotal=@($Works).Count;$script:TaskDone=0;$script:Parallel=$Parallel
 foreach($w in $Works) {$script:Pending.Enqueue($w)};Status "$Name starting...";Log "$Name started by user."
}
function BuildTargets {
 foreach($old in @($script:Live.Controls)) {$script:Live.Controls.Remove($old);$old.Dispose()};$script:Cards=@{};$script:Samples=@{};$script:TargetList.Items.Clear()
 $targets=@();foreach($r in $script:Routes) {if ($r.NextHop -and $r.NextHop -notin @('0.0.0.0','::')) {$address=$r.NextHop;$ip=[Net.IPAddress]::Parse($address);if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and $ip.IsIPv6LinkLocal -and -not $address.Contains('%')) {$address+='%'+$r.Index};$targets += [pscustomobject]@{Name='Selected next hop';Address=$address}}}
 $targets += [pscustomobject]@{Name='Cloudflare IPv4';Address='1.1.1.1'},[pscustomobject]@{Name='Google IPv4';Address='8.8.8.8'}
 if (@($script:Routes | Where-Object {$_.Destination.Contains(':')}).Count) {$targets += [pscustomobject]@{Name='Cloudflare IPv6';Address='2606:4700:4700::1111'},[pscustomobject]@{Name='Google IPv6';Address='2001:4860:4860::8888'}}
 $script:Targets=@($targets | Sort-Object Address -Unique)
 foreach($t in $script:Targets) {[void]$script:TargetList.Items.Add("$($t.Name) / $($t.Address)",$true);$script:Samples[$t.Address]=[Collections.Generic.List[object]]::new();$p=[Windows.Forms.Panel]::new();$p.Size=[Drawing.Size]::new(333,254);$p.Margin=[Windows.Forms.Padding]::new(7);$p.Tag=$t;$p.Add_Paint({param($sender,$e) PaintCard $sender.Tag $e.Graphics});$script:Cards[$t.Address]=$p;$script:Live.Controls.Add($p);ApplyTheme $p}
}
function FillProviders {
 $script:ProviderList.Items.Clear();$script:Providers=@()
 if ($script:DoH.Checked) {$script:Providers=@([pscustomobject]@{Name='Cloudflare DoH';Endpoint='https://cloudflare-dns.com/dns-query'},[pscustomobject]@{Name='Google DoH';Endpoint='https://dns.google/resolve'})}
 else {
  $configured=@(@(foreach($route in $script:Routes) {$a=$script:Adapters | Where-Object Index -eq $route.Index | Select-Object -First 1;if ($null -ne $a) {$a.Dns}}) | Select-Object -Unique -First 2)
  foreach($ip in $configured) {$script:Providers += [pscustomobject]@{Name="Configured $ip";Endpoint=$ip}}
  foreach($pair in @(@('Cloudflare','1.1.1.1'),@('Google','8.8.8.8'))) {if (-not @($script:Providers | Where-Object Endpoint -eq $pair[1]).Count) {$script:Providers += [pscustomobject]@{Name=$pair[0];Endpoint=$pair[1]}}}
 }
 foreach($p in $script:Providers) {[void]$script:ProviderList.Items.Add($p.Name,$true)}
}
function SuggestRange {
 $i=$script:AdapterList.SelectedIndex;if ($i -lt 0 -or $i -ge $script:Adapters.Count) {return};$a=$script:Adapters[$i]
 $script:AdapterNote.Text="$($a.Name) / $($a.Address)/$($a.Prefix) / $($a.State). Scope suggestion only; actual traffic follows Windows routes."
 $n=IpNumber $a.Address;$size=[Math]::Pow(2,32-[int]$a.Prefix);$first=[uint64]([Math]::Floor($n/$size)*$size);$last=[uint64]($first+$size-1);if ($a.Prefix -le 30) {$first++;$last--};if ($last-$first+1 -gt 256) {$first=[uint64]([Math]::Floor($n/256)*256+1);$last=$first+253;$script:AdapterNote.Text+=' Large subnet: only a /24-sized slice suggested.'};$script:From.Text=NumberIp $first;$script:To.Text=NumberIp $last
}
function StartInternet([bool]$Repeat=$false) {
 if ($script:Mode -ne 'idle') {return}
 $selected=$script:RepeatTargets;if (-not $Repeat) {$selected=@(foreach($i in $script:TargetList.CheckedIndices) {$script:Targets[[int]$i]})}
 if (-not $selected.Count) {throw 'Select one or more targets in Internet Tests.'}
 if (-not $Repeat) {$script:RepeatTargets=$selected}
 foreach($t in $selected) {$script:Samples[$t.Address].Clear()}
 $works=@(foreach($t in $selected) {[pscustomobject]@{Kind='ping';Address=$t.Address;Name=$t.Name}})
 if ($script:Services.Checked) {$dns=@(foreach($route in $script:Routes) {$a=$script:Adapters | Where-Object Index -eq $route.Index | Select-Object -First 1;if ($null -ne $a) {$a.Dns}});$works += [pscustomobject]@{Kind='services';Address='';Dns=@($dns | Select-Object -Unique)}}
 BeginBatch 'Internet Tests' $works 8
}
function StartScan {
 if (-not $script:Authorized.Checked) {throw 'Confirm permission for this exact scan range.'}
 $first=IpNumber $script:From.Text.Trim();$last=IpNumber $script:To.Text.Trim();if ($last -lt $first -or $last-$first+1 -gt 256) {throw 'Choose an ascending IPv4 range with at most 256 addresses.'}
 foreach($n in @($first,$last)) {$ip=NumberIp $n;if ($ip -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)') {throw 'Public-address scanning is disabled. Use an authorized private, local or shared range.'}}
 $ports=@();foreach($part in ($script:Ports.Text -split '[,;\s]+')) {if (-not $part) {continue};$p=0;if (-not [int]::TryParse($part,[ref]$p) -or $p -lt 1 -or $p -gt 65535) {throw "Invalid TCP port: $part"};$ports+=$p};$ports=@($ports | Select-Object -Unique);if ($ports.Count -gt 16) {throw 'Maximum 16 individual TCP ports.'}
 if ([Windows.Forms.MessageBox]::Show($script:Form,"Scan $($script:From.Text) through $($script:To.Text)?`r`nTCP ports: $($ports -join ', ')`r`nProceed only with permission for this exact scope.",'Approve device scan',[Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes') {return}
 $script:Devices.Clear();$script:DeviceGrid.Rows.Clear();$works=@(for($n=$first;$n -le $last;$n++) {$addr=NumberIp $n;$neighbor=$script:Neighbors | Where-Object IPAddress -eq $addr | Select-Object -First 1;$mac='';if ($null -ne $neighbor) {$mac=$neighbor.LinkLayerAddress};[pscustomobject]@{Kind='scan';Address=$addr;Ports=$ports;Names=$script:Names.Checked;Mac=$mac}})
 BeginBatch 'Network Devices' $works ([int]$script:Concurrency.Value)
}
function StartDns {
 $domains=@($script:Domains.Text -split '[,;\s]+' | Where-Object {$_} | Select-Object -Unique)
 if ($domains.Count -lt 1 -or $domains.Count -gt 10) {throw 'Enter 1-10 public domain names, not URLs.'}
 foreach($d in $domains) {if ($d.Length -gt 253 -or $d -notmatch '^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\.?$') {throw "Invalid public ASCII domain name: $d"}}
 $selected=@(foreach($i in $script:ProviderList.CheckedIndices) {$script:Providers[[int]$i]});$transport='UDP';if ($script:DoH.Checked) {$transport='DoH'}
 $custom=$script:Custom.Text.Trim();if ($custom) {
  if ($transport -eq 'UDP') {$ip=$null;if (-not [Net.IPAddress]::TryParse($custom,[ref]$ip)) {throw 'Custom ordinary DNS must be an IP address.'};$custom=$ip.ToString()}
  else {$uri=$null;if (-not [Uri]::TryCreate($custom,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Query -or $uri.Fragment -or $uri.UserInfo) {throw 'Use an HTTPS JSON endpoint without query, credentials or fragment.'}}
  $selected += [pscustomobject]@{Name='Custom '+$custom;Endpoint=$custom}
 }
 if (-not $selected.Count) {throw 'Select at least one resolver.'};$count=$domains.Count*[int]$script:Repetitions.Value
 $message="$transport test: $($selected.Count) resolvers, $count measured queries each and one warm-up each.`r`nEndpoints:`r`n$($selected.Endpoint -join "`r`n")`r`nNames: $($domains -join ', ')`r`nResolvers receive these names and your source public IP. No DNS settings change. Continue?"
 if ([Windows.Forms.MessageBox]::Show($script:Form,$message,'Approve DNS benchmark',[Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes') {return}
 $script:DnsSamples.Clear();$script:DnsSummary.Rows.Clear();$script:DnsDetails.Rows.Clear();$script:DnsExpected=$count;$script:DnsTransport=$transport;$script:DnsNotice.Text='Running only because START was pressed. Warm-ups are excluded; one resolver runs at a time.'
 $works=@(foreach($p in $selected) {[pscustomobject]@{Kind='benchmark';Name=$p.Name;Address=$p.Endpoint;Endpoint=$p.Endpoint;Transport=$transport;Domains=$domains;Repetitions=[int]$script:Repetitions.Value;Timeout=[int]$script:Timeout.Value}})
 BeginBatch 'DNS Benchmark' $works 1
}
function RefreshDns {
 $script:DnsSummary.Rows.Clear();$stats=@(foreach($group in ($script:DnsSamples | Group-Object Provider)) {
  $v=@($group.Group | Where-Object Outcome -eq 'SUCCESS' | ForEach-Object {[double]$_.Ms} | Sort-Object);$min=$null;$max=$null;$mean=$null;$median=$null
  if ($v.Count) {$m=$v | Measure-Object -Minimum -Maximum -Average;$min=$m.Minimum;$max=$m.Maximum;$mean=$m.Average;$mid=[int][Math]::Floor($v.Count/2);$median=$v[$mid];if ($v.Count%2 -eq 0) {$median=($v[$mid-1]+$v[$mid])/2}}
  [pscustomobject]@{Name=$group.Name;Good=$v.Count;Timeouts=@($group.Group | Where-Object Outcome -eq 'TIMEOUT').Count;Errors=@($group.Group | Where-Object Outcome -eq 'ERROR').Count;Min=$min;Median=$median;Mean=$mean;Max=$max;Eligible=($group.Count -eq $script:DnsExpected -and $v.Count -eq $script:DnsExpected)}
 })
 $b=[Text.StringBuilder]::new();[void]$b.AppendLine("$script:DnsTransport / milliseconds / successful queries only").AppendLine('Rank requires a complete all-success run. Failures never become invented timing penalties.').AppendLine();$rank=0
 foreach($s in ($stats | Sort-Object @{Expression='Eligible';Descending=$true},@{Expression={if ($null -eq $_.Median) {[double]::MaxValue} else {$_.Median}}})) {
  $label='partial/errors';if ($s.Eligible) {$rank++;$label="#$rank this run"};$times=@(foreach($n in @($s.Min,$s.Median,$s.Mean,$s.Max)) {if ($null -eq $n) {'--'} else {'{0:0.0}' -f $n}})
  $idx=$script:DnsSummary.Rows.Add([string]$s.Name,[string]$label,"$($s.Good)/$script:DnsExpected",[string]$s.Timeouts,[string]$s.Errors,[string]$times[0],[string]$times[1],[string]$times[2],[string]$times[3])
  if ($null -ne $s.Median) {$script:DnsSummary.Rows[$idx].Cells[6].Style.BackColor=Heat $s.Median;$script:DnsSummary.Rows[$idx].Cells[6].Style.ForeColor=[Drawing.Color]::Black}
  [void]$b.AppendLine("$($s.Name) / $label").AppendLine("  Success $($s.Good)/$script:DnsExpected | timeouts $($s.Timeouts) | errors $($s.Errors)");if ($null -ne $s.Median) {[void]$b.AppendLine(('  min {0:0.0} / median {1:0.0} / avg {2:0.0} / max {3:0.0} ms' -f $s.Min,$s.Median,$s.Mean,$s.Max))};[void]$b.AppendLine()
 };$script:DnsCompact.Text=$b.ToString()
}
function RefreshStatistics {
 $b=[Text.StringBuilder]::new();[void]$b.AppendLine('STATISTICS SNAPSHOT / no network requests').AppendLine(('Updated {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date))).AppendLine().AppendLine('ICMP: successful replies only; ms. P95 uses nearest rank.').AppendLine('Variation = mean absolute difference of adjacent successful samples; failures break pairs.').AppendLine()
 foreach($t in $script:Targets) {$s=$script:Samples[$t.Address];$v=@($s | Where-Object {$null -ne $_.Ms} | ForEach-Object {[double]$_.Ms} | Sort-Object);[void]$b.AppendLine("$($t.Name) / $($t.Address)");if (-not $s.Count) {[void]$b.AppendLine('  Not tested.');continue};$loss=100.0*($s.Count-$v.Count)/$s.Count;[void]$b.AppendLine(('  Replies {0}/{1}; ICMP loss {2:0.0}%' -f $v.Count,$s.Count,$loss));if ($v.Count) {$m=$v | Measure-Object -Minimum -Maximum -Average;$p95=$v[[int][Math]::Ceiling($v.Count*.95)-1];$diff=@(for($i=1;$i -lt $s.Count;$i++) {if ($null -ne $s[$i].Ms -and $null -ne $s[$i-1].Ms) {[Math]::Abs($s[$i].Ms-$s[$i-1].Ms)}});$variation='n/a';if ($diff.Count) {$variation='{0:0.0}' -f ($diff | Measure-Object -Average).Average};[void]$b.AppendLine(('  min {0:0} / avg {1:0.0} / max {2:0} / P95 {3:0} / variation {4}' -f $m.Minimum,$m.Average,$m.Maximum,$p95,$variation))}}
 [void]$b.AppendLine().AppendLine("Device rows: $($script:Devices.Count); responding observations: $(@($script:Devices | Where-Object State -eq 'RESPONDED').Count)").AppendLine("DNS measured samples: $($script:DnsSamples.Count)").AppendLine("Retained service checks: $($script:Checks.Count)").AppendLine().AppendLine('These are observations, not a universal internet-health score.');$script:StatsSnapshot=$b.ToString();$script:StatsBox.Text=$script:StatsSnapshot;Status 'Statistics refreshed from existing data only.'
}
function ExportData([string]$Kind) {
 $dialog=[Windows.Forms.SaveFileDialog]::new()
 try {
  $json=$Kind -eq 'json';$dialog.Filter='CSV|*.csv';$dialog.FileName='NetworkDashboard-devices.csv';if ($Kind -eq 'dns') {$dialog.FileName='NetworkDashboard-DNS.csv'};if ($json) {$dialog.Filter='JSON session|*.json';$dialog.FileName='NetworkDashboard-session.json'}
  if ($dialog.ShowDialog($script:Form) -ne 'OK') {return};$hide=$script:Redact.Checked;$devices=@();$i=0
  foreach($r in $script:Devices) {$i++;$address=$r.Address;$name=$r.Hostname;$mac=$r.Mac;if ($hide) {$address="Device $i";$name='[redacted]';$mac='[redacted]'};$devices += [pscustomobject]@{Address=$address;Hostname=$name;State=$r.State;Ms=$r.Ms;Ports=$r.Ports;CachedMac=$mac;Time=$r.Time}}
  $dns=@();$labels=@{};$i=0;foreach($r in $script:DnsSamples) {if (-not $labels.ContainsKey($r.Provider)) {$i++;$labels[$r.Provider]="Resolver $i"};$provider=$r.Provider;$endpoint=$r.Endpoint;$domain=$r.Domain;$detail=$r.Detail;if ($hide) {$provider=$labels[$r.Provider];$endpoint='[redacted]';$domain='[redacted]';$detail='[redacted]'};$dns += [pscustomobject]@{Provider=$provider;Transport=$r.Transport;Endpoint=$endpoint;Domain=$domain;Round=$r.Round;Outcome=$r.Outcome;Ms=$r.Ms;Detail=$detail;Time=$r.Time}}
  if ($json) {
   $samples=@();$i=0;foreach($address in $script:Samples.Keys) {$i++;foreach($s in $script:Samples[$address]) {$target=$address;$detail=$s.Detail;if ($hide) {$target="Target $i";$detail='[redacted]'};$samples += [pscustomobject]@{Target=$target;Ms=$s.Ms;Detail=$detail;Time=$s.Time}}}
   $checks=@();$i=0;foreach($r in $script:Checks) {$i++;$name=$r.Test;$detail=$r.Detail;if ($hide) {$name="Check $i";$detail='[redacted]'};$checks += [pscustomobject]@{Test=$name;State=$r.State;Detail=$detail;Time=$r.Time}}
   $map='[redacted]';$trace='[redacted]';$stats='[redacted]';if (-not $hide) {$map=$script:Map+"`r`n"+$script:DeviceMap;$trace=$script:Trace;$stats=$script:StatsSnapshot};$content=[pscustomobject]@{Version='5.0';ExportTime=[DateTimeOffset]::Now.ToString('o');Redacted=$hide;Devices=$devices;DNS=$dns;ICMP=$samples;Checks=$checks;Map=$map;Trace=$trace;Statistics=$stats} | ConvertTo-Json -Depth 10
  } else {$rows=$devices;if ($Kind -eq 'dns') {$rows=$dns};if ($rows.Count) {$content=($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"} elseif ($Kind -eq 'dns') {$content='"Provider","Transport","Endpoint","Domain","Round","Outcome","Ms","Detail","Time"'} else {$content='"Address","Hostname","State","Ms","Ports","CachedMac","Time"'}}
  [IO.File]::WriteAllText($dialog.FileName,$content,[Text.UTF8Encoding]::new($true));Status 'Export saved locally.'
 } finally {$dialog.Dispose()}
}
function StartSelected {
 if ($script:Mode -ne 'idle' -or $null -ne $script:RepeatAt) {return}
 try {
  switch($script:Tabs.SelectedIndex) {
   0 {if ($script:OverviewMac.Checked) {BeginBatch 'MAC Cache' @([pscustomobject]@{Kind='neighbors';Address=''}) 1} else {BeginBatch 'Discovery' @([pscustomobject]@{Kind='discover';Address=''}) 1}}
   1 {StartInternet}
   2 {StartScan}
   3 {StartDns}
   4 {$script:Trace="IPv4 route -> 1.1.1.1. Silent hops are not confirmed failures.`r`n";$script:TraceBox.Text=$script:Trace;BeginBatch 'Route Trace' @([pscustomobject]@{Kind='trace';Address='1.1.1.1'}) 1}
   5 {RefreshStatistics}
   6 {
    if ($script:ExportJson.Checked) {ExportData 'json'} elseif ($script:ExportDns.Checked) {ExportData 'dns'} elseif ($script:ExportDevices.Checked) {ExportData 'devices'} else {
     $url='https://dnsspeedtest.online/';if ($script:ServiceCloudflare.Checked) {$url='https://speed.cloudflare.com/'};if ($script:ServiceMLab.Checked) {$url='https://speed.measurementlab.net/'}
     $message="Open $url in your browser? The external service receives connection/request information. Speed tests can use substantial data.";if ($script:ServiceMLab.Checked) {$message+=' M-Lab retains and publishes measurements including public IP addresses.'}
     if ([Windows.Forms.MessageBox]::Show($script:Form,$message,'External service confirmation',[Windows.Forms.MessageBoxButtons]::YesNo) -eq 'Yes') {Start-Process $url;Status 'External browser opened. Use its own controls; dashboard STOP cannot cancel browser activity.'}
    }
   }
  }
 } catch {Status ('Not started: '+$_.Exception.GetBaseException().Message);Log $_.Exception.Message;[void][Windows.Forms.MessageBox]::Show($script:Form,$_.Exception.GetBaseException().Message,'Task not completed')}
}
function RefreshMap {$script:MapBox.Text=$script:Map+"`r`n"+$script:DeviceMap}
function Receive {
 $r=$null;$dnsChanged=$false
 while($script:Updates.TryDequeue([ref]$r)) {
  switch($r.Kind) {
   'discovery' {
    $script:Adapters=@($r.Adapters);$script:Routes=@($r.Routes);$script:Neighbors=@($r.Neighbors);$script:AdapterList.Items.Clear()
    foreach($a in $script:Adapters) {[void]$script:AdapterList.Items.Add("$($a.Name) / $($a.Address)/$($a.Prefix) / $($a.State)")};$idx=0;$refRoute=$script:Routes | Where-Object Destination -eq '1.1.1.1' | Select-Object -First 1;for($i=0;$i -lt $script:Adapters.Count;$i++) {if ($script:Adapters[$i].Address -eq $refRoute.Source) {$idx=$i;break}};if ($script:Adapters.Count) {$script:AdapterList.SelectedIndex=$idx}
    $b=[Text.StringBuilder]::new();[void]$b.AppendLine('OBSERVED CONNECTION / not complete physical topology').AppendLine().AppendLine('[ THIS WINDOWS COMPUTER ]')
    foreach($route in $script:Routes) {$a=$script:Adapters | Where-Object {if ($route.Destination.Contains(':')) {$_.IPv6Index -eq $route.Index} else {$_.Index -eq $route.Index}} | Select-Object -First 1;[void]$b.AppendLine("  +-- $($a.Name) / interface $($route.Index)").AppendLine("      source: $($route.Source)").AppendLine("      next hop: $($route.NextHop)").AppendLine("        -> reference destination: $($route.Destination)");if ($null -ne $a) {[void]$b.AppendLine('      DNS side branch: '+($a.Dns -join ', '))}}
    [void]$b.AppendLine().AppendLine('0.0.0.0 / :: = on-link, not a router to ping. Routes differ by destination.').AppendLine('VPN physical paths are not inferred. Adapter list does not bind test traffic.').AppendLine().AppendLine('ADAPTER DETAILS')
    foreach($a in $script:Adapters) {[void]$b.AppendLine("$($a.Name) / $($a.Type) / $($a.State)").AppendLine('  addresses: '+($a.AllAddresses -join ', ')).AppendLine('  configured DNS: '+($a.Dns -join ', ')).AppendLine("  reported link rate: $($a.LinkMbps) Mbps (not measured internet bandwidth)")};foreach($note in @($r.Notes)) {[void]$b.AppendLine('Discovery note: '+$note)};$script:Map=$b.ToString();RefreshMap;BuildTargets;FillProviders
   }
   'neighbors' {$script:Neighbors=@($r.Neighbors);for($i=0;$i -lt $script:Devices.Count;$i++) {$d=$script:Devices[$i];$n=$script:Neighbors | Where-Object {$_.IPAddress -eq $d.Address -and $_.LinkLayerAddress -and $_.LinkLayerAddress -notmatch '^(00[-:]){5}00$'} | Select-Object -First 1;$d.Mac='';if ($null -ne $n) {$d.Mac=$n.LinkLayerAddress};$script:DeviceGrid.Rows[$i].Cells[5].Value=[string]$d.Mac};Log 'Neighbor cache manually refreshed; no scan or settings change.'}
   'device' {$script:Devices.Add($r);[void]$script:DeviceGrid.Rows.Add([string]$r.Address,[string]$r.Hostname,[string]$r.State,[string]$r.Ms,[string]$r.Ports,[string]$r.Mac)}
   'sample' {if ($script:Samples.ContainsKey($r.Address)) {$script:Samples[$r.Address].Add($r)}}
   'check' {$script:Checks.Add($r);if ($script:Checks.Count -gt 500) {$script:Checks.RemoveAt(0);$script:CheckGrid.Rows.RemoveAt(0)};[void]$script:CheckGrid.Rows.Add([string]$r.Test,[string]$r.State,[string]$r.Detail)}
   'dns' {$script:DnsSamples.Add($r);$ms='--';if ($null -ne $r.Ms) {$ms='{0:0.0}' -f $r.Ms};[void]$script:DnsDetails.Rows.Add([string]$r.Provider,[string]$r.Domain,[string]$r.Round,[string]$r.Outcome,[string]$ms,[string]$r.Detail);$dnsChanged=$true}
   'warmup' {$script:DnsNotice.Text=$r.Text;Log $r.Text}
   'trace' {$script:Trace+=$r.Text+"`r`n";$script:TraceBox.Text=$script:Trace}
   'error' {Log $r.Text}
  };$r=$null
 }
 if ($dnsChanged) {RefreshDns};RefreshSemanticColors
}
function Tick {
 if ($script:Closing) {return};Receive
 for($i=$script:Active.Count-1;$i -ge 0;$i--) {$j=$script:Active[$i];if ($j.Handle.IsCompleted) {try {[void]$j.Engine.EndInvoke($j.Handle)} catch {Log $_.Exception.Message};$j.Engine.Dispose();$script:Active.RemoveAt($i);$script:TaskDone++}}
 while(-not $script:Signal.Stop -and $script:Pending.Count -gt 0 -and $script:Active.Count -lt $script:Parallel) {$w=$script:Pending.Dequeue();$engine=[PowerShell]::Create();$engine.RunspacePool=$script:Pool;[void]$engine.AddScript($script:Worker).AddArgument($w).AddArgument($script:Signal).AddArgument($script:Updates);try {$h=$engine.BeginInvoke();$script:Active.Add([pscustomobject]@{Engine=$engine;Handle=$h})} catch {$engine.Dispose();$script:TaskDone++;Log $_.Exception.Message}}
 Receive
 if ($script:Mode -ne 'idle') {
  $script:Progress.Maximum=[Math]::Max(1,$script:TaskTotal);$script:Progress.Value=[Math]::Min($script:TaskDone,$script:Progress.Maximum);$label=$script:Mode;if ($script:Signal.Stop) {$label='STOPPING'};Status "$label / $script:TaskDone of $script:TaskTotal jobs finished / $($script:Active.Count) active"
  if (-not $script:Pending.Count -and -not $script:Active.Count) {
   $mode=$script:Mode;$script:Mode='idle';$note='FINISHED - inspect results for pass/fail';if ($script:Signal.Stop) {$note='STOPPED / partial results'};Status "$mode / $note";Log "$mode / $note"
   if ($mode -eq 'DNS Benchmark') {$script:DnsNotice.Text="$note. Only complete all-success resolvers are ranked.";RefreshDns}
   if ($mode -eq 'Network Devices') {$b=[Text.StringBuilder]::new();[void]$b.AppendLine('LAST DEVICE SCAN / logical observations, not physical links');foreach($d in $script:Devices) {if ($d.State -eq 'RESPONDED') {[void]$b.AppendLine("  +-- $($d.Address) $($d.Hostname) $($d.Ports)")}};$script:DeviceMap=$b.ToString();RefreshMap}
   if ($mode -eq 'Internet Tests' -and $script:Repeat.Checked -and -not $script:Signal.Stop) {$script:RepeatAt=[DateTime]::UtcNow.AddSeconds(5);Status 'Repeat explicitly enabled / next round in 5 seconds; STOP cancels repeat.'}
  }
 }
 if ($null -ne $script:RepeatAt -and [DateTime]::UtcNow -ge $script:RepeatAt -and $script:Mode -eq 'idle') {$script:RepeatAt=$null;StartInternet $true}
 $busy=$script:Mode -ne 'idle' -or $null -ne $script:RepeatAt;$script:StartButton.Enabled=-not $busy;$script:StopButton.Enabled=$busy
 foreach($c in $script:BusyControls) {$c.Enabled=-not $busy}
 foreach($card in $script:Cards.Values) {$card.Invalidate()}
}

# UI construction only: no discovery, scan, benchmark, query or browser launch here.
$script:Form=[Windows.Forms.Form]::new();$script:Form.Text='Network Diagnostics Dashboard 5.0';$script:Form.Size=[Drawing.Size]::new(1260,940);$script:Form.MinimumSize=[Drawing.Size]::new(620,760);$script:Form.StartPosition='CenterScreen';$script:Form.AutoScaleMode='Dpi';$script:Form.Font=$script:Font
$root=[Windows.Forms.TableLayoutPanel]::new();$root.Dock='Fill';$root.RowCount=3;$root.ColumnCount=1;$root.Padding=[Windows.Forms.Padding]::new(8)
[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,70));[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100));[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,112));$script:Form.Controls.Add($root)
$header=[Windows.Forms.Panel]::new();$header.Dock='Fill';$root.Controls.Add($header,0,0);$headerFlow=Flow $header
[void](Label '>_ NETWORK DIAGNOSTICS 5.0' $headerFlow)
$dark=Button 'BLACK THEME' $headerFlow;$light=Button 'WHITE THEME' $headerFlow
$script:Tabs=[Windows.Forms.TabControl]::new();$script:Tabs.Dock='Fill';$script:Tabs.Multiline=$true;$script:Tabs.SizeMode='Fixed';$script:Tabs.ItemSize=[Drawing.Size]::new(156,52);$script:Tabs.DrawMode='OwnerDrawFixed';$root.Controls.Add($script:Tabs,0,1)
$overview=Page 'Overview';$internet=Page 'Internet Tests';$devices=Page 'Network Devices';$dnsPage=Page 'DNS Benchmark';$tracePage=Page 'Route Trace';$statistics=Page 'Statistics';$exports=Page 'Export & Services'
$script:Tabs.Add_DrawItem({param($sender,$e)
 $selected=$e.Index -eq $sender.SelectedIndex;$bg=$script:Colors.Surface;$fg=$script:Colors.Text;if ($selected) {$bg=$script:Colors.Accent;$fg=[Drawing.Color]::White}
 $brush=[Drawing.SolidBrush]::new($bg);try {$e.Graphics.FillRectangle($brush,$e.Bounds)} finally {$brush.Dispose()}
 [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$sender.TabPages[$e.Index].Text,$sender.Font,$e.Bounds,$fg,([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::WordBreak))
 if ($selected) {$e.DrawFocusRectangle()}
})
$overviewSplit=SplitPage $overview 135;$overviewFlow=Flow $overviewSplit.Top
$script:OverviewDiscover=Choice 'Discover configuration' $overviewFlow $true
$script:OverviewMac=Choice 'Refresh MAC cache only' $overviewFlow
[void](Label 'Nothing runs on startup. Choose an action and press START below. Cache refresh reads existing local neighbor data; it does not scan.' $overviewFlow)
$script:MapBox=ReadBox $overviewSplit.Bottom;$script:MapBox.Text=$script:Map

$internetSplit=SplitPage $internet 210;$internetFlow=Flow $internetSplit.Top
$script:TargetList=[Windows.Forms.CheckedListBox]::new();$script:TargetList.Width=330;$script:TargetList.Height=110;$script:TargetList.CheckOnClick=$true;$script:TargetList.Margin=[Windows.Forms.Padding]::new(6);$internetFlow.Controls.Add($script:TargetList)
$script:Services=Check 'Include DNS / TCP / HTTPS checks' $internetFlow $true
$script:Repeat=Check 'Repeat rounds (off by default)' $internetFlow $false
[void](Label 'Select targets. START sends 10 pings per selected target. Repeat works only after an explicit START; STOP ends it. Dials measure ms, not Mbps.' $internetFlow)
$internetTabs=InnerTabs $internetSplit.Bottom @('Latency & heat','Service results')
$script:Live=Flow $internetTabs.TabPages[0];$script:CheckGrid=Grid $internetTabs.TabPages[1] @('Test','State','Detail')

$deviceSplit=SplitPage $devices 280;$deviceFlow=Flow $deviceSplit.Top
$script:AdapterList=[Windows.Forms.ListBox]::new();$script:AdapterList.Width=420;$script:AdapterList.Height=83;$script:AdapterList.Margin=[Windows.Forms.Padding]::new(6);$deviceFlow.Controls.Add($script:AdapterList)
$script:AdapterNote=Label 'No adapters have been read. Run Overview discovery manually, or enter an authorized range below.' $deviceFlow
[void](Label 'From IPv4' $deviceFlow);$script:From=Edit '' $deviceFlow 150;[void](Label 'To IPv4' $deviceFlow);$script:To=Edit '' $deviceFlow 150
[void](Label 'TCP ports: blank = ICMP only' $deviceFlow);$script:Ports=Edit '' $deviceFlow 180
$script:Names=Check 'Optional hostname lookup' $deviceFlow
[void](Label 'Parallel hosts' $deviceFlow);$script:Concurrency=[Windows.Forms.NumericUpDown]::new();$script:Concurrency.Minimum=1;$script:Concurrency.Maximum=16;$script:Concurrency.Value=8;$script:Concurrency.Width=60;$deviceFlow.Controls.Add($script:Concurrency)
$script:Authorized=Check 'I have permission for this exact range' $deviceFlow
$script:DeviceGrid=Grid $deviceSplit.Bottom @('Address','Hostname','State','Latency ms','TCP results','Cached MAC')

$dnsSplit=SplitPage $dnsPage 330;$dnsFlow=Flow $dnsSplit.Top
$script:UDP=Choice 'Ordinary DNS / UDP 53' $dnsFlow $true
$script:DoH=Choice 'DNS over HTTPS / JSON' $dnsFlow
$script:ProviderList=[Windows.Forms.CheckedListBox]::new();$script:ProviderList.Width=270;$script:ProviderList.Height=100;$script:ProviderList.CheckOnClick=$true;$script:ProviderList.Margin=[Windows.Forms.Padding]::new(6);$dnsFlow.Controls.Add($script:ProviderList)
[void](Label 'Query domains, comma separated' $dnsFlow);$script:Domains=Edit 'example.com,microsoft.com,cloudflare.com' $dnsFlow 410
[void](Label 'Repetitions per domain' $dnsFlow);$script:Repetitions=[Windows.Forms.NumericUpDown]::new();$script:Repetitions.Minimum=1;$script:Repetitions.Maximum=10;$script:Repetitions.Value=3;$script:Repetitions.Width=60;$dnsFlow.Controls.Add($script:Repetitions)
[void](Label 'Timeout ms' $dnsFlow);$script:Timeout=[Windows.Forms.NumericUpDown]::new();$script:Timeout.Minimum=500;$script:Timeout.Maximum=10000;$script:Timeout.Increment=500;$script:Timeout.Value=3000;$script:Timeout.Width=80;$dnsFlow.Controls.Add($script:Timeout)
[void](Label 'Optional custom resolver IP or HTTPS JSON endpoint' $dnsFlow);$script:Custom=Edit '' $dnsFlow 390
$script:DnsNotice=Label 'IDLE. START asks for approval before warm-up or queries. No DNS settings are changed. UDP and DoH rankings remain separate.' $dnsFlow
$dnsTabs=InnerTabs $dnsSplit.Bottom @('Readable summary','Comparison','Query details')
$script:DnsCompact=ReadBox $dnsTabs.TabPages[0];$script:DnsCompact.Text='No DNS benchmark has run.'
$script:DnsSummary=Grid $dnsTabs.TabPages[1] @('Provider','Rank','Success','Timeouts','Errors','Min','Median','Average','Max')
$script:DnsDetails=Grid $dnsTabs.TabPages[2] @('Provider','Domain','Round','Outcome','ms','Detail')

$traceSplit=SplitPage $tracePage 100;$traceFlow=Flow $traceSplit.Top
[void](Label 'START traces toward 1.1.1.1 using up to 20 IPv4 hops. No route trace runs on tab selection. Silent hops are not confirmed failures; elapsed times are not hop-loss measurements.' $traceFlow)
$script:TraceBox=ReadBox $traceSplit.Bottom;$script:TraceBox.Text=$script:Trace
$script:StatsBox=ReadBox $statistics;$script:StatsBox.Text='IDLE. Press START to calculate a statistics snapshot from existing data only. This action makes no network requests.'

$exportTabs=InnerTabs $exports @('Choose action','Privacy & help','Log')
$exportFlow=Flow $exportTabs.TabPages[0];$exportFlow.FlowDirection='TopDown';$exportFlow.WrapContents=$false
$script:ExportJson=Choice 'Save session JSON' $exportFlow $true
$script:ExportDevices=Choice 'Save device results CSV' $exportFlow
$script:ExportDns=Choice 'Save DNS samples CSV' $exportFlow
$script:ServiceDns=Choice 'Open DNS Speed Test website' $exportFlow
$script:ServiceCloudflare=Choice 'Open Cloudflare speed-test website' $exportFlow
$script:ServiceMLab=Choice 'Open M-Lab speed-test website' $exportFlow
$script:Redact=Check 'Redact identifiers in exports (recommended)' $exportFlow $true
[void](Label 'Choose one action, then press START. Exports require a local file choice. Websites require confirmation; external browser tests have their own Stop controls.' $exportFlow)
$help=ReadBox $exportTabs.TabPages[1]
$help.Text=@'
VERSION 5 / MANUAL BY DESIGN
No startup discovery, pings, scans, DNS benchmarks, browser launch or cache refresh.
Tabs, theme buttons, checkboxes and radio buttons only change the UI/options.
START launches the selected tab action. STOP cancels queued work and repeat mode;
active native network calls may need to finish. Statistics/export are local actions.

No Angry IP Scanner code, copied website implementation, Java, embedded C#, API
keys, download dependencies or background server. All tests run from this Windows PC.
Touch-oriented Windows layout, NOT an Android/iPhone app or remote phone website.

COLORS
Pure black or pure white main background. Blue/lavender accents. Green success,
red failure, gray disabled/unknown. Status text accompanies color. Heat: blue
0 ms -> red 200+ ms, a display scale, not universal quality criteria.
Red X means a missing ICMP reply; successful slow replies have no X.

NETWORK SAFETY
Private/shared address space does not establish ownership. Scan only authorized
ranges, especially on apartment/workplace networks. Max 256 IPv4 addresses and
16 TCP ports. NO RESPONSE does not prove a device is offline. REFUSED is not OPEN.
MACs come from local neighbor cache, may be missing/stale, and are not remote MACs.
Adapter selection suggests scope; Windows routing determines traffic direction.
No network settings, DNS, firewall or persistent policy changes are made.

DNS
Ordinary UDP and DoH are separate tests. One uncounted warm-up is performed only
after you approve START. Resolvers receive chosen names and public source IP.
DoH includes HTTPS overhead/connection reuse; UDP times send/receive only.
Failures are counted separately, not converted into pretend latency. Rankings
require all expected queries to succeed. DoH custom URLs must support DNS JSON.
Resolver caching and test order affect measurements. This is not a universal
fastest-resolver recommendation. No local DNSSEC validation is performed.

EXTERNAL SERVICES
Website buttons only open a browser after confirmation. Bandwidth tests can use
substantial data. M-Lab retains/publishes measurements including public IPs.
Dashboard STOP cannot control a separately launched browser or cancel file dialogs.

PRIVACY
No automatic history saving or telemetry. Export redaction is on by default.
Screen/log are not redacted. Review files before sharing. Redaction keeps numeric
results, port observations, statuses and timestamps. See README for destinations.

VALIDATION
This package has not been run on a Windows desktop here. Lightweight source and
ZIP checks are not runtime testing. Report the full launcher error if it fails.
'@
$script:LogBox=ReadBox $exportTabs.TabPages[2];$script:LogBox.Text='IDLE / No tools have been started.'+"`r`n"

# Shared sticky action bar: visible on every tab, never hidden in a menu.
$footer=[Windows.Forms.TableLayoutPanel]::new();$footer.Dock='Fill';$footer.RowCount=3;$footer.ColumnCount=1
[void]$footer.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,58));[void]$footer.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,65));[void]$footer.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,35));$root.Controls.Add($footer,0,2)
$actionPanel=[Windows.Forms.Panel]::new();$actionPanel.Dock='Fill';$footer.Controls.Add($actionPanel,0,0);$actionFlow=Flow $actionPanel
$script:StartButton=Button 'START Overview' $actionFlow;$script:StartButton.MinimumSize=[Drawing.Size]::new(220,44);$script:StartButton.AccessibleName='Start the action on the selected tab'
$script:StopButton=Button 'STOP' $actionFlow;$script:StopButton.AccessibleName='Stop active tools and repeat monitoring';$script:StopButton.Enabled=$false
$script:StatusLabel=[Windows.Forms.Label]::new();$script:StatusLabel.Dock='Fill';$script:StatusLabel.AutoEllipsis=$true;$script:StatusLabel.Text='IDLE / Nothing runs until you press START.';$footer.Controls.Add($script:StatusLabel,0,1)
$script:Progress=[Windows.Forms.ProgressBar]::new();$script:Progress.Dock='Fill';$footer.Controls.Add($script:Progress,0,2)
$script:BusyControls=@($script:OverviewDiscover,$script:OverviewMac,$script:TargetList,$script:Services,$script:Repeat,$script:AdapterList,$script:From,$script:To,$script:Ports,$script:Names,$script:Concurrency,$script:Authorized,$script:UDP,$script:DoH,$script:ProviderList,$script:Domains,$script:Repetitions,$script:Timeout,$script:Custom)
$script:Tabs.Add_SelectedIndexChanged({$script:StartButton.Text='START '+$script:Tabs.SelectedTab.Text})
$dark.Add_Click({SetTheme $false});$light.Add_Click({SetTheme $true})
$script:AdapterList.Add_SelectedIndexChanged({SuggestRange})
$script:UDP.Add_CheckedChanged({if ($script:UDP.Checked) {FillProviders}});$script:DoH.Add_CheckedChanged({if ($script:DoH.Checked) {FillProviders}})
$script:StartButton.Add_Click({StartSelected})
$script:StopButton.Add_Click({$script:RepeatAt=$null;$script:Signal.Stop=$true;$script:Pending.Clear();Status 'STOP requested / no new work; active calls may need to finish.';Log 'STOP requested by user.'})
$script:Form.Add_Resize({$narrow=$script:Form.ClientSize.Width -lt 900;$dnsHeight=330;$deviceHeight=280;$internetHeight=210;$overviewHeight=135;if ($narrow) {$dnsHeight=350;$deviceHeight=300;$internetHeight=240;$overviewHeight=160};$dnsSplit.Layout.RowStyles[0].Height=$dnsHeight;$deviceSplit.Layout.RowStyles[0].Height=$deviceHeight;$internetSplit.Layout.RowStyles[0].Height=$internetHeight;$overviewSplit.Layout.RowStyles[0].Height=$overviewHeight;foreach($l in @($script:DnsNotice,$script:AdapterNote)) {$l.MaximumSize=[Drawing.Size]::new([Math]::Max(300,$script:Form.ClientSize.Width-80),0)}})
# These build local lists/draw controls only. No engine call or network discovery.
BuildTargets;FillProviders;SetTheme $false
$script:Timer=[Windows.Forms.Timer]::new();$script:Timer.Interval=250
$script:Timer.Add_Tick({try {Tick} catch {Status ('Dashboard error: '+$_.Exception.GetBaseException().Message);Log $_.Exception.Message}})
$script:Form.Add_Shown({$script:Timer.Start()})
$script:Form.Add_FormClosing({$script:Closing=$true;$script:RepeatAt=$null;$script:Signal.Stop=$true;$script:Pending.Clear();$script:Timer.Stop()})
try {[Windows.Forms.Application]::Run($script:Form)} finally {
 $script:Signal.Stop=$true;$script:Timer.Dispose();foreach($j in $script:Active) {try {$j.Engine.Dispose()} catch {}}
 if ($null -ne $script:Pool) {$script:Pool.Close();$script:Pool.Dispose()}
 $script:Font.Dispose();$script:Mono.Dispose();$script:Small.Dispose();$script:Big.Dispose();$script:Form.Dispose()
}
