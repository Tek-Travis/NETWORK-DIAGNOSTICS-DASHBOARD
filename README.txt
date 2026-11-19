NETWORK DIAGNOSTICS DASHBOARD 5.0 / 
==============================================
COMPLETE PACKAGE / ORIGINAL POWERSHELL AND .NET CODE
No Angry IP Scanner source/binary, copied DNS website code, Java, embedded C#,
API keys, dependency downloads or background web server.

START
Windows 10/11, Windows PowerShell 5.1, desktop .NET Framework required.
Close old copies. Extract ALL files into a NEW normal folder. Double-click
Start Dashboard.cmd. Keep NetworkDashboard.ps1 and Engine.ps1 together.
Do not run from ZIP preview. No administrator elevation is requested.
Launcher sets process-only execution-policy bypass; it does not change stored
user/machine policy. Organization security controls can still block execution.
Do not disable organizational security tools. Review the source before running.
Manual launch from the extracted directory:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\NetworkDashboard.ps1

VERSION 5 REQUIREMENTS
- Pure BLACK main background by default; pure WHITE theme available.
- Large TOP TABS; multiline tab rows on narrower windows. No app dropdown menus.
- BLACK THEME / WHITE THEME buttons. Themes do not trigger tasks.
- Sticky START / STOP action bar visible on EVERY tab. START runs the selected
  tab's action. STOP controls the currently active dashboard task even if you
  change tabs. It is disabled when there is nothing to stop.
- ZERO startup discovery or network tests. No query/scan/browser/cache refresh
  happens on tab selection, option selection, theme changes or window resizing.
- Provider/target lists are populated locally, not tested automatically.
- No auto rediscovery, scheduled tests or persistent startup preferences.
- Repeat is OFF by default and only starts after explicit START with it enabled.

FIRST USE
1. Application opens IDLE. To read configuration, Overview -> Discover
   configuration -> START. This reads adapters, reference routes and neighbor cache.
2. Internet Tests: check targets, optionally include DNS/TCP/HTTPS, then START.
3. Network Devices: select detected adapter for a suggested range, review scope,
   optionally specify ports/hostnames, confirm permission, then START and approve.
4. DNS Benchmark: choose UDP or DoH with radio buttons, check providers, edit
   query options if needed, START, then approve endpoints and names.
5. Route Trace: START manually traces toward 1.1.1.1.
6. Statistics: START makes a snapshot of existing data ONLY, with no network work.
7. Export & Services: select an action with visible radio buttons, then START.
   Exports open a Save dialog; website actions ask confirmation before opening.

THEMES / UX
Main background #000000 or #FFFFFF. Selected-tab accent #4E5891, border #AAB1C6,
muted text #C0C5D7 in dark mode, blue/lavender accents. Primary text white on black,
dark on white. Green success, red failure, gray disabled/unknown. Text labels
accompany states. Latency heat is blue 0ms -> red 200+ms (display choices only).
Buttons have 44-pixel design-height targets; top tabs have 52-pixel design height.
Controls wrap/scroll. Technical tables can scroll horizontally. DNS has a readable
summary instead of forcing narrow windows to use a wide comparison table.
DPI autoscaling requested; actual behavior needs Windows testing.
This is a resizable/touch-oriented WINDOWS DESKTOP application, NOT an Android/
iPhone app, browser UI or remotely accessible service. No mobile-compatibility or
accessibility-conformance claim. Default minimum window is 620x760 outer pixels.

OVERVIEW / DISCOVERY
Discovery is only initiated by START. Reads local adapter configuration, Windows
reference routes toward 1.1.1.1 and 2606:4700:4700::1111, and Get-NetNeighbor cache.
0.0.0.0/:: next hop means on-link, not a router to ping. Routes are destination-
specific, especially with split VPNs. Choosing an adapter does not bind traffic.
Adapter list represents IPv4 configurations; IPv6-only adapters are not fully
inventoried. IPv6 route may have no matching adapter display name.
Driver link rate is NOT measured internet throughput. Map is observed logical
configuration, not every physical switch/router/cable. Host observations are
separate logical scan results. No ISP identity, geo lookup, public-IP lookup, NAT
classification, captive-portal diagnosis or hidden-network mapping is claimed.
Overview -> Refresh MAC cache only -> START reads current local neighbor data and
updates existing device rows. No packets are intentionally sent by this action.
MACs are local cached observations, can be missing/stale, and are not remote MACs.
If identical IPs exist on multiple interfaces, first matching cache entry is used.

INTERNET TESTS
Default IPv4 public target list is local/static until START. Discovery adds selected
next hops and IPv6 Cloudflare/Google targets when an IPv6 reference route exists.
Target enable controls are checkboxes. Ten ICMP probes per selected target, 1500ms
timeout with 1 second between completed probes. Successful replies determine ms.
PASS=10/10 replies; FAIL=at least one missing. Partial stopped rounds are labeled.
Missing ICMP responses can be filtering/rate-limiting, not an outage.
Red X = missing reply; a successful slow reply has no X. Dials are ms, NOT Mbps.
Optional service suite: direct UDP example.com A queries through up to two configured
reference-route DNS resolvers, TCP 443 on 1.1.1.1/8.8.8.8, HTTPS HEAD to Microsoft
and Cloudflare websites. HTTPS uses normal certificate validation, system default
proxy, TLS1.2 capability and up to five redirects. A failed HEAD can coexist with
a working browser GET. HTTP error does not prove the server was unreachable.
Service checks retain at most 500 results, in memory only.
Repeat monitoring is explicit opt-in: after START, next rounds begin after a
five-second pause until STOP. It does not begin from checking the box alone.
It clears prior-round samples for the selected targets. Unselected targets retain
older samples. STOP cancels both queued work and repeat. Restart requires START.
Statistics snapshots can therefore contain targets last measured in different rounds.

NETWORK DEVICES
Max 256 ascending IPv4 addresses and 16 individual TCP ports. Blank ports = ICMP
only. Public scanning rejected: allowed ranges are private IPv4, link-local, or
100.64/10 shared address space. Private does NOT imply authorization. Obtain
permission before scanning apartment/workplace/shared networks.
Large subnets suggest a /24-sized slice, never the whole large subnet. /31 and /32
retain endpoints. Adapter selection is only a scope suggestion; Windows routes apply.
1-16 concurrent hosts (default 8). Ping timeout 700ms; TCP 350ms per selected port.
TCP ports are checked even if ping fails. RESPONDED means ICMP response, accepted
TCP connection or TCP refusal. NO RESPONSE does not prove absent/offline.
OPEN means handshake accepted, not identified/authenticated service. REFUSED is
not OPEN. Timeouts cannot distinguish filtered/absent/closed reliably.
Optional reverse OS name lookup has 1200ms display wait; OS lookup may continue.
No banners, credentials, exploit checks, UDP scan or IPv6 address-range scan.
Cached MAC is populated from discovery/current cache; refresh explicitly afterward.

DNS BENCHMARK
Ordinary UDP DNS and DoH are separate modes/rankings. Ordinary providers include
up to two discovered configured resolvers plus Cloudflare/Google. DoH endpoints:
https://cloudflare-dns.com/dns-query and https://dns.google/resolve.
Compatible custom DNS JSON HTTPS endpoints are supported; not every RFC8484 endpoint
supports JSON. Custom URLs must omit query/credentials/fragment. UDP custom = IP.
1-10 public ASCII domain names; 1-10 repetitions per domain; timeout 500-10000ms.
One uncounted warm-up per resolver begins only after explicit START and approval.
Sequential resolvers reduce self-contention. Inter-query delay 200ms.
UDP directly sends A queries, bypassing Windows name cache. It validates transaction,
question echo, flags/rcode, resource-record boundaries and presence of an IPv4 A
answer. UDP query timing excludes construction/validation. No TCP fallback for
truncation. No local DNSSEC validation, cache flush or CNAME-chain verification.
DoH includes endpoint bootstrap name resolution, HTTP/TLS/connect/reuse/body time,
excluding JSON parsing. It requires Status=0, nontruncated and A answer. Redirects
disabled; normal .NET TLS certificate validation. No DNSSEC verification claim.
UDP can be intercepted upstream; neither measurement proves a resolver's identity.
Statistics use SUCCESS samples only. TIMEOUT and ERROR counts remain separate,
never converted to fake latency. Ranking requires every expected query to succeed.
Provider order/caching/connection reuse/rate-limits/network conditions affect results.
Not a universal fastest-provider recommendation or prediction of page-load speed.

ROUTE TRACE / STATISTICS
Trace: manual IPv4 ICMP toward 1.1.1.1, up to 20 hops, one 900ms probe per hop.
Silent hops do not prove forwarding failure. Timings are whole-call elapsed time,
not hop loss. No reverse DNS/geography. START begins; STOP requests cancellation.
Statistics START computes existing ICMP min/avg/max, nearest-rank P95, loss and
mean absolute difference of adjacent successful samples; failures break pairs.
Not standardized RTP/WebRTC jitter. Ten samples are only descriptive. Snapshot
is explicitly refreshed, not automatically updated on opening the tab.

EXPORT / EXTERNAL SERVICES
Choose device CSV, DNS CSV or session JSON and press START. A local Save dialog
appears; no data is uploaded. JSON adds existing ICMP samples, service checks,
map, trace and latest manually calculated statistics snapshot.
Redaction ON by default: strips target/provider/IP/domain/hostname/MAC identifiers,
map/trace/statistics free text and diagnostics. Numeric timings, statuses, port
observations and timestamps remain. Screen and log are NOT redacted. Review files.
No automatic disk history or telemetry. Data is discarded on exit unless exported.
DNS Speed Test / Cloudflare / M-Lab options open public websites only, after START
and confirmation. No integrated bandwidth API, free UDP relay, API keys or downloads.
M-Lab retains and PUBLISHES measurements including public IP addresses. Speed tests
can consume substantial data. Review provider policies before testing.
Dashboard STOP does not control a separate browser, cancel a file dialog or undo
an exported file. Use browser/dialog controls for those actions.

DESTINATIONS / NO AUTO RUN
No network task is launched on startup. The UI timer only processes jobs that START
created (or explicitly requested repeat rounds). No auto-change detection or polling.
After explicit START, tests may contact: selected range/ports; selected next hops;
1.1.1.1 / 8.8.8.8; 2606:4700:4700::1111 / 2001:4860:4860::8888 when discovered;
configured DNS / selected approved public/custom resolvers and domain names;
https://www.microsoft.com/ and https://www.cloudflare.com/ plus redirects.
External browser links: https://dnsspeedtest.online/ ; https://speed.cloudflare.com/
; https://speed.measurementlab.net/ . Endpoints receive source IP/request metadata.

CANCELLATION / SECURITY
Bounded in-process runspace pool (max16); all control access on main STA thread.
STOP clears queued work and sets a shared flag checked between calls. Native
Windows operations and HTTP per-operation timeouts are not guaranteed wall-clock
limits. Active calls can take time to finish; closing can briefly wait.
No synchronous Stop call on UI thread. No administrator request, persistent policy
change, DNS settings change, firewall edit, repair, credentials or network attacks.

VALIDATION STATUS
First build generated in a non-Windows environment. ZIP integrity, static content,
no-startup-dispatch assertions and lightweight delimiter checks performed. These
are NOT Windows PowerShell parsing, execution, DNS accuracy, DPI, touch or cancellation
tests. No Windows desktop/runtime was available. NOT a verified Windows release.
If startup fails, launcher leaves full error visible. Report the complete message.

REFERENCES
https://developers.google.com/speed/public-dns/docs/doh/json
https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/
https://learn.microsoft.com/powershell/module/nettcpip/get-netneighbor
https://learn.microsoft.com/powershell/module/nettcpip/find-netroute
