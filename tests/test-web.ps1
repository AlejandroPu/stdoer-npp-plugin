# Web links: ONLY http and https are opened (in the browser). Everything else -other schemes
# (javascript:, file:, ms-settings:, program protocols...), malformed http addresses, ones with
# dangerous characters or too long- is NOT opened, and the tooltip says so.
# It is tested with the plugin's test mode (STDOER_NO_SHELL): the plugin logs what it would do
# and does not call Windows, so no test opens a real browser or program.
# Each case is a link in a .stdoer document: "Open" is requested (like the click or the menu) and
# the tooltip (like the mouse dwell) and the log is read.
#
# Usage (from the stdoer folder):   .\tests\test-web.ps1

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$work = Join-Path $Root 'build\web'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Root 'tests\targets'
$docS = Join-Path $work 'web.stdoer'; $log = Join-Path $work 'web.log'

$long = 'https://example.com/' + ('a' * 2100)
$nonAscii = 'https://example.com/caf' + [char]0x00E9                  # accented letter, built from its code
$cyrillicJ = [string][char]0x0458 + 'avascript:alert(1)'              # the first letter is Cyrillic
# kind: web = opens in the browser; no = rejected (nothing is opened); rel = neither a web address
# nor an absolute path (not opened); path = a real file path (the usual rule).
$cases = @(
    @{ t = 'http://example.com';                         k = 'web' },
    @{ t = 'https://example.com/a/b?c=d&e=f#frag';        k = 'web' },
    @{ t = 'HTTPS://EXAMPLE.COM';                        k = 'web' },
    @{ t = 'Http://Example.com/Path';                    k = 'web' },
    @{ t = 'http://localhost:8080/x';                    k = 'web' },
    @{ t = 'https://notepad-plus-plus.org/';             k = 'web' },
    @{ t = 'http://[::1]/path';                          k = 'web' },
    @{ t = 'https://user@example.com:8443/p%20q';        k = 'web' },
    @{ t = 'http://192.168.0.1/';                        k = 'web' },
    @{ t = '   https://example.com/spaces-around   ';     k = 'web' },
    @{ t = $nonAscii;                                    k = 'web'; ascii = $false },
    @{ t = 'javascript:alert(1)';                        k = 'no' },
    @{ t = 'JavaScript:alert(1)';                        k = 'no' },
    @{ t = 'JAVASCRIPT:void(0)';                         k = 'no' },
    @{ t = '  javascript:alert(1)';                      k = 'no' },
    @{ t = 'file:///C:/Windows/System32/calc.exe';       k = 'no' },
    @{ t = 'FILE://server/share/x.exe';                  k = 'no' },
    @{ t = 'ms-settings:network';                        k = 'no' },
    @{ t = 'ms-calculator:';                             k = 'no' },
    @{ t = 'mailto:someone@example.com';                 k = 'no' },
    @{ t = 'tel:+56912345678';                           k = 'no' },
    @{ t = 'ftp://example.com/x';                        k = 'no' },
    @{ t = 'sftp://example.com/x';                       k = 'no' },
    @{ t = 'ssh://host';                                 k = 'no' },
    @{ t = 'telnet://host';                              k = 'no' },
    @{ t = 'ws://host/x';                                k = 'no' },
    @{ t = 'wss://host/x';                               k = 'no' },
    @{ t = 'data:text/html,hello';                       k = 'no' },
    @{ t = 'vbscript:msgbox(1)';                         k = 'no' },
    @{ t = 'steam://run/1';                              k = 'no' },
    @{ t = 'zoommtg://zoom.us/join?confno=1';            k = 'no' },
    @{ t = 'search-ms:query=x';                          k = 'no' },
    @{ t = 'shell:startup';                              k = 'no' },
    @{ t = 'ms-msdt:/id PCWDiagnostic';                  k = 'no' },
    @{ t = 'onenote:https://example.com/x';              k = 'no' },
    @{ t = 'chrome://settings';                          k = 'no' },
    @{ t = 'edge://settings';                            k = 'no' },
    @{ t = 'about:blank';                                k = 'no' },
    @{ t = 'view-source:https://example.com';            k = 'no' },
    @{ t = 'blob:https://example.com/uuid';              k = 'no' },
    @{ t = 'cmd:/c calc';                                k = 'no' },
    @{ t = 'powershell:iex';                             k = 'no' },
    @{ t = 'httpx://example.com';                        k = 'no' },
    @{ t = 'http+evil://example.com';                    k = 'no' },
    @{ t = 'http:/example.com';                          k = 'no' },
    @{ t = 'http:example.com';                           k = 'no' },
    @{ t = 'http://';                                    k = 'no' },
    @{ t = 'https:///x';                                 k = 'no' },
    @{ t = 'http://?x';                                  k = 'no' },
    @{ t = 'http://#x';                                  k = 'no' },
    @{ t = 'https://a.b/c d';                            k = 'no' },
    @{ t = 'https://a.b/c"d';                            k = 'no' },
    @{ t = 'https://a.b/c<d';                            k = 'no' },
    @{ t = 'https://a.b/c>d';                            k = 'no' },
    @{ t = 'https://a.b/c^d';                            k = 'no' },
    @{ t = 'https://a.b/c`d';                            k = 'no' },
    @{ t = 'https://a.b\c';                              k = 'no' },
    @{ t = "https://a.b/c`td";                           k = 'no' },
    @{ t = $long;                                        k = 'no'; short = $true },
    @{ t = 'http//example.com';                          k = 'rel' },
    @{ t = 'www.example.com';                            k = 'rel' },
    @{ t = '//example.com/x';                            k = 'rel' },
    @{ t = 'c:calc.exe';                                 k = 'rel' },
    @{ t = 'h ttp://a.b';                                k = 'rel' },
    @{ t = "java`tscript:alert(1)";                      k = 'rel' },
    @{ t = $cyrillicJ;                                   k = 'rel' },
    @{ t = "$obj\text.txt";                              k = 'path' }
)
$lines = $cases | ForEach-Object { "__link[$($_.t)]" }
[IO.File]::WriteAllText($docS, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

$bad = 0
function Verdict([string]$name, [bool]$ok, [string]$detail = '') {
    if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-90} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  $detail" }))
}
function LogLines { if (Test-Path $log) { @(Get-Content $log -Encoding UTF8) } else { @() } }

Npp-Open @($docS) $log @{ STDOER_NO_SHELL = '1' }
[void](Sci 4003 0 -1)
$docsBefore = (Npp-Documents).Count

for ($i = 0; $i -lt $cases.Count; $i++) {
    $c = $cases[$i]
    $pos = [int64]((Sci 2167 $i) + 3)
    $shown = $c.t -replace "`t", '<TAB>'
    if ($shown.Length -gt 60) { $shown = $shown.Substring(0, 57) + '...' }
    $before = @(LogLines).Count
    [void](Sci 2201)                                               # SCI_CALLTIPCANCEL
    [void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', 1, $pos)    # tooltip
    Start-Sleep -Milliseconds 150
    [void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', 3, $pos)    # left click
    Start-Sleep -Milliseconds 250
    if ($c.k -eq 'web') { [void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', 11, $pos); Start-Sleep -Milliseconds 250 }   # and the menu's "Open"
    $new = @(LogLines)[$before..99999] | Where-Object { $_ }
    $text = $new -join ' | '
    $tip = ($new | Where-Object { $_ -match '^tooltip:' }) -join ''
    $allOpens = @($new | Where-Object { $_ -match '^open:' })
    $open = $allOpens[0]
    switch ($c.k) {
        'web' {
            $expected = $c.t.Trim()
            if ($c.ascii -eq $false) {
                $ok = ($open -like 'open: browser https://example.com/*') -and ($tip -like 'tooltip: https://example.com/*') -and ($tip -notmatch 'not opened')
            } else {
                $ok = ($open -eq "open: browser $expected") -and ($tip -eq "tooltip: $expected")
            }
            $ok = $ok -and ($allOpens.Count -eq 2) -and ($allOpens[0] -eq $allOpens[1])      # the click and the menu's "Open" do the same
            Verdict "OPENS in the browser (click and menu): $shown" $ok $text
        }
        'no' {
            $ok = ($open -like 'open: scheme or address not allowed*') -and ($tip -match 'not opened: only http and https addresses are opened') -and ($open -notmatch 'browser|in Notepad|with Windows|folder')
            Verdict "NOT OPENED (rejected): $shown" $ok $text
        }
        'rel' {
            $ok = ($open -like 'open: path is not absolute*') -and ($tip -match 'relative path: not opened')
            Verdict "NOT OPENED (neither web nor absolute path): $shown" $ok $text
        }
        'path' {
            $ok = (@($allOpens | Where-Object { $_ -like 'open: in Notepad++ *text.txt' }).Count -eq 1) -and ($tip -notmatch 'not opened')
            Verdict "a file path stays the same (opens in Notepad++): $shown" $ok $text
        }
    }
}

# Nothing was really opened: no new tab except the path link's (text.txt)
$docsAfter = (Npp-Documents).Count
Verdict 'only ONE new tab was opened in total (the one for the link to text.txt)' ($docsAfter -eq $docsBefore + 1) "before=$docsBefore after=$docsAfter"
Verdict 'no web case called Windows (test mode): the log has no "with Windows"' (@(LogLines | Where-Object { $_ -match 'with Windows' }).Count -eq 0)
Write-Host "SUMMARY: $bad failures out of $($cases.Count + 2) checks"
Npp-Close
if ($bad -gt 0) { exit 1 }
