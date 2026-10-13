# Test of the click and the tooltip of the __link[path] links in the portable Notepad++.
#
# Usage (from the stdoer folder):   .\tests\test-link-clicks.ps1
#
# A document is created in build\clicks\ with links to files in tests\targets\ (made up,
# inside stdoer). The mouse (move, left click) is simulated with Windows messages and the
# plugin's debug log (STDOER_LOG) is read to learn what it decided. With STDOER_NO_SHELL the
# plugin does NOT call Windows (it opens no programs or Explorer): it only logs what it would
# have opened. What it does open for real is "in Notepad++" (tabs).
# It also measures how long a click takes on a network path that does not respond (it must
# stay bounded).

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$work = Join-Path $Root 'build\clicks'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Root 'tests\targets'
$doc = Join-Path $work 'links.stdoer'
$lines = @(
    "text: __link[$obj\text.txt]",
    "sheet: __link[$obj\sheet.ods]",
    "folder: __link[$obj\folder]",
    "executable: __link[$obj\harmless.exe]",
    "broken: __link[$obj\does-not-exist.txt]",
    "disabled: _link[$obj\text.txt]",
    "brackets: __link[$obj\file [1].txt]",
    "relative: __link[tests\targets\text.txt]",
    "no extension: __link[$obj\noextension]",
    "slow network: __link[\\10.255.255.1\share\x.txt]",
    "Section {",
    "    in region: __link[$obj\text.txt]",
    "}",
    "empty path: __link[]",
    ""
)
[IO.File]::WriteAllText($doc, ($lines -join "`n"), (New-Object Text.UTF8Encoding $false))
$log = Join-Path $work 'stdoer.log'

$bad = 0
function Verdict([string]$name, [bool]$ok, [string]$detail = '') {
    if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-64} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  $detail" }))
}
function LogLines { if (Test-Path $log) { @(Get-Content $log) } else { @() } }

Npp-Open @($doc) -Log $log -Env @{ STDOER_NO_SHELL = '1' }
$d = Npp-Documents | Where-Object { $_.Path -eq $doc }
Npp-Activate $d.Index
[void](Sci 4003 0 -1)
Start-Sleep -Milliseconds 400

# position of a text within a line of the document
function PosOf([int]$line, [string]$needle, [int]$shift = 0) {
    $start = Sci 2167 $line            # SCI_POSITIONFROMLINE
    $txt = $lines[$line]
    $i = $txt.IndexOf($needle)
    return $start + [Text.Encoding]::UTF8.GetByteCount($txt.Substring(0, $i)) + $shift
}
function PointOf([int64]$pos) {
    $x = Sci 2164 0 $pos              # SCI_POINTXFROMPOSITION
    $y = Sci 2165 0 $pos              # SCI_POINTYFROMPOSITION
    return @([int]$x, [int]$y)
}
function MoveMouse([int]$x, [int]$y) { [void][NppT]::SendMessage($script:VNpp, 0x0200, [IntPtr]0, (Npp-LParamMouse $x $y)) }
function Click([int]$x, [int]$y, [int]$keys = 0) {
    $lp = Npp-LParamMouse $x $y
    MoveMouse $x $y
    [void][NppT]::SendMessage($script:VNpp, 0x0201, [IntPtr](1 -bor $keys), $lp)   # WM_LBUTTONDOWN (+ Shift/Ctrl in $keys)
    [void][NppT]::SendMessage($script:VNpp, 0x0202, [IntPtr]$keys, $lp)            # WM_LBUTTONUP
}
# Click on "link[" of the line (on the 'l', not on the "__").
function ClickOnLine([int]$line, [int]$keys = 0) {
    $p = PointOf (PosOf $line 'link[' 1)
    Click ($p[0] + 2) ($p[1] + 4) $keys
}
function Wait-Log([int]$before, [string]$pattern, [int]$ms = 4000) {
    $t = [Diagnostics.Stopwatch]::StartNew()
    while ($t.ElapsedMilliseconds -lt $ms) {
        $new = @(LogLines)[$before..9999] | Where-Object { $_ -match $pattern }
        if ($new) { return ($new | Select-Object -First 1) }
        Start-Sleep -Milliseconds 80
    }
    return $null
}

# ---------- clicks ----------
$cases = @(
    @{ n = 'click on a link to .txt  -> opens in Notepad++';              l = 0;  exp = 'open: in Notepad\+\+ .*text\.txt' },
    @{ n = 'click on a link to .ods  -> Windows (or its folder if no program)'; l = 1; exp = 'open: (with Windows|containing folder of) .*sheet\.ods' },
    @{ n = 'click on a link to a folder -> opens it (Explorer)';          l = 2;  exp = 'open: folder .*folder' },
    @{ n = 'click on a link to .exe  -> NOT run: shows its folder';        l = 3;  exp = 'open: containing folder of .*harmless\.exe' },
    @{ n = 'click on a link with a missing path -> does nothing';          l = 4;  exp = 'does not exist, nothing done' },
    @{ n = 'click on a path with [ ] in the name -> opens';                l = 6;  exp = 'open: in Notepad\+\+ .*file \[1\]\.txt' },
    @{ n = 'click on a relative path -> nothing is done';                  l = 7;  exp = 'path is not absolute' },
    @{ n = 'click on a file without extension -> only its folder';         l = 8;  exp = 'open: containing folder of .*noextension' },
    @{ n = 'click on a link inside a { } region -> opens';                 l = 11; exp = 'open: in Notepad\+\+ .*text\.txt' }
)
foreach ($c in $cases) {
    $before = (LogLines).Count
    $docsBefore = NppMsg $NPPM_GETNBOPENFILES
    ClickOnLine $c.l
    $r = Wait-Log $before $c.exp
    Verdict $c.n ($r -ne $null) ("log: " + ((@(LogLines)[$before..9999]) -join ' || '))
    # back to the links document for the next click
    $dd = Npp-Documents | Where-Object { $_.Path -eq $doc }; Npp-Activate $dd.Index
}
# tabs opened by the clicks in Notepad++: text.txt and file [1].txt
$opened = (Npp-Documents | Where-Object { $_.Path } | ForEach-Object { Split-Path -Leaf $_.Path })
Verdict 'new tabs: text.txt and file [1].txt' (($opened -contains 'text.txt') -and ($opened -contains 'file [1].txt')) ("opened: " + ($opened -join ', '))
$dd = Npp-Documents | Where-Object { $_.Path -eq $doc }; Npp-Activate $dd.Index

# ---------- clicks that must not open ----------
$before = (LogLines).Count
ClickOnLine 5                                          # disabled link (_link[...])
Start-Sleep -Milliseconds 700
Verdict 'click on a disabled link (_link[...]) -> nothing' (((@(LogLines)[$before..9999]) | Where-Object { $_ -match 'open: (in Notepad|with Windows|folder|containing folder)' }).Count -eq 0)
$before = (LogLines).Count
$p = PointOf (PosOf 0 '__link[' 0)
Click ($p[0] + 2) ($p[1] + 4)                          # click on the "__": not the clickable zone
Start-Sleep -Milliseconds 700
Verdict 'click on the "__" (not a clickable zone) -> nothing' (((@(LogLines)[$before..9999]) | Where-Object { $_ -match 'open: (in Notepad|with Windows|folder|containing folder)' }).Count -eq 0)
$before = (LogLines).Count
ClickOnLine 0 4                                        # Shift (MK_SHIFT = 4) + click: it is selecting
Start-Sleep -Milliseconds 700
Verdict 'Shift + click on a link -> does not open (it selects)' (((@(LogLines)[$before..9999]) | Where-Object { $_ -match 'open: (in Notepad|with Windows|folder|containing folder)' }).Count -eq 0)
$before = (LogLines).Count
ClickOnLine 13                                         # empty-path link
Start-Sleep -Milliseconds 700
Verdict 'click on an empty-path link -> nothing' (((@(LogLines)[$before..9999]) | Where-Object { $_ -match 'open: (in Notepad|with Windows|folder|containing folder)' }).Count -eq 0)

# ---------- network path that does not respond: the click must not freeze ----------
$before = (LogLines).Count
$timer = [Diagnostics.Stopwatch]::StartNew()
ClickOnLine 9
$ms = $timer.ElapsedMilliseconds
Verdict "click on a network path that does not respond -> returns in $ms ms (limit ~1000)" ($ms -lt 2500)
$r = Wait-Log $before 'no response' 1500
Verdict 'that click logs "no response" and does nothing' ($r -ne $null)
# Notepad++ is still alive and responds
Verdict 'Notepad++ keeps responding after the slow click' ((Sci 2006) -gt 0)

# ---------- tooltip on mouse hover ----------
# The plugin receives Scintilla's "mouse dwell" notice, which does not arrive with a synthetic
# mouse; here it is asked through NPPM_MSGTOPLUGIN (only in test mode) to show the tooltip of
# that position.
function Tooltip([int]$line, [string]$where = '__link[') {
    [void](Sci 2201)    # SCI_CALLTIPCANCEL: as if the mouse had left earlier
    $before = (LogLines).Count
    $pos = PosOf $line $where 2
    [void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', 1, $pos)
    $r = Wait-Log $before 'tooltip:' 2500
    return $r
}
$r = Tooltip 0
Verdict 'tooltip on an existing link: shows the path, no warnings' (($r -match 'text\.txt') -and ($r -notmatch 'does not exist'))  $r
$r = Tooltip 4
Verdict 'tooltip on a broken link: says it does not exist' (($r -match 'does-not-exist\.txt') -and ($r -match 'does not exist')) $r
$r = Tooltip 7
Verdict 'tooltip on a relative path: says it is not opened' ($r -match 'relative path') $r
$r = Tooltip 13
Verdict 'tooltip on an empty path' ($r -match 'empty path') $r
$timer = [Diagnostics.Stopwatch]::StartNew()
$r = Tooltip 9
Verdict 'tooltip on a network path that does not respond: says there was no response' ($r -match 'no response') $r
Verdict 'Notepad++ keeps responding after the slow tooltip' ((Sci 2006) -gt 0)
# outside a link there is no tooltip
$before = (LogLines).Count
[void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', 1, (PosOf 0 'text:' 0))
Start-Sleep -Milliseconds 800
Verdict 'tooltip outside a link: none' ((@(LogLines)[$before..9999] | Where-Object { $_ -match 'tooltip:' }).Count -eq 0)

Write-Host "SUMMARY: $bad failures"
Write-Host "(plugin log: $log)"
Npp-Close
if ($bad -gt 0) { exit 1 }
