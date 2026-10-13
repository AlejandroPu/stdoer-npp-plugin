# Tests the right-click menu with the PORTABLE Notepad++, through the real path: WM_CONTEXTMENU
# is sent to the view (as Windows does on a right click), the actual popup menu is awaited, its
# content is read and the choice is made with the keyboard (Down + Enter).
#   - On an active / disabled / web / broken link...: the right options (and which are grayed out).
#   - Outside a link (text, after the end of the link, after the end of the line, "my_link[0]",
#     "___link[x]", another .txt tab): Notepad++'s NORMAL menu (it carries "Cut").
#   - Each option does what it says (the plugin's log is read, with STDOER_NO_SHELL: nothing is
#     really opened); Enable / Disable change ONE "_" and are undone with a SINGLE Undo.
#   - A cancelled menu changes nothing; read-only; menu from the keyboard.
#
# Usage (from the stdoer folder):   .\tests\test-menu.ps1

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$work = Join-Path $Root 'build\menu'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Root 'tests\targets'
$docS = Join-Path $work 'menu.stdoer'; $docT = Join-Path $work 'other.txt'; $log = Join-Path $work 'menu.log'
$lines = @(
    'plain text here',
    "__link[$obj\text.txt] end",
    "__link[$obj\folder]",
    "__link[$obj\harmless.exe]",
    "__link[$obj\does-not-exist.txt]",
    "_link[$obj\text.txt] switched off",
    '__link[https://notepad-plus-plus.org/]',
    '__link[javascript:alert(1)]',
    '__link[tests\targets\text.txt]',
    'my_link[0] and x_link[path] and ___link[x.txt]',
    '',
    '{',
    "    __link[$obj\text.txt]",
    '}',
    'zz'
)
$original = ($lines -join "`n") + "`n"
[IO.File]::WriteAllText($docS, $original, (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText($docT, "__link[$obj\text.txt] in a txt`n", (New-Object Text.UTF8Encoding $false))

$bad = 0
function Verdict([string]$name, [bool]$ok, [string]$detail = '') {
    if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-88} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  $detail" }))
}
function LogLines { if (Test-Path $log) { @(Get-Content $log) } else { @() } }
function Summary($items) {
    if ($null -eq $items) { return 'NO MENU' }
    if ($items -match '42001\|Cut') { return 'NORMAL' }
    $r = @()
    foreach ($l in ($items -split "`n")) {
        if ($l -match '^(\d+)\|([^|]*)\|(\w+)$') { $r += $Matches[2] + $(if ($Matches[3] -eq 'gray') { ' (grayed)' } else { '' }) }
    }
    $r -join ' | '
}
function LineStart([int]$line) { [int](Sci 2167 $line) }          # SCI_POSITIONFROMLINE
function DocText { (SciText) }

Npp-Open @($docS, $docT) $log @{ STDOER_NO_SHELL = '1' }
$iS = (Npp-Documents | Where-Object { $_.Path -eq $docS }).Index
$iT = (Npp-Documents | Where-Object { $_.Path -eq $docT }).Index
Npp-Activate $iS; Start-Sleep -Milliseconds 600
[void](Sci 4003 0 -1)
Verdict 'the document is as it was (start)' ((DocText) -eq $original)

$A3 = 'Open | Open containing folder | Disable link'
Write-Host '--- options according to the link'
$cases = @(
    @{ n = 'link to a text file';                  l = 1;  k = 2; e = $A3 },
    @{ n = 'link to a folder';                     l = 2;  k = 2; e = $A3 },
    @{ n = 'link to an .exe (Open shows its folder)'; l = 3; k = 2; e = $A3 },
    @{ n = 'broken link (does not exist)';         l = 4;  k = 2; e = 'Open (grayed) | Open containing folder | Disable link' },
    @{ n = 'disabled link (_link[)';               l = 5;  k = 1; e = 'Enable link' },
    @{ n = 'https web address';                    l = 6;  k = 2; e = 'Open | Disable link' },
    @{ n = 'rejected scheme (javascript:)';        l = 7;  k = 2; e = 'Open (grayed) | Disable link' },
    @{ n = 'relative path';                        l = 8;  k = 2; e = 'Open (grayed) | Open containing folder (grayed) | Disable link' },
    @{ n = 'link inside a { } region';             l = 12; k = 6; e = $A3 }
)
foreach ($c in $cases) {
    $actual = Summary (Npp-ContextMenu ((LineStart $c.l) + $c.k))
    Verdict "$($c.n)" ($actual -eq $c.e) "got: $actual"
}

Write-Host '--- any point of the link (line 1) opens the link menu; outside it, the normal one'
$t = DocText
$line1 = $lines[1]; $closing = $line1.IndexOf(']')
foreach ($k in 0, 1, 2, 6) {
    Verdict "on character $k of the link (`"$($line1.Substring($k, 1))`")" ((Summary (Npp-ContextMenu ((LineStart 1) + $k))) -eq $A3)
}
Verdict 'on the closing "]"' ((Summary (Npp-ContextMenu ((LineStart 1) + $closing))) -eq $A3)
Verdict 'right after the "]" (the space): normal menu' ((Summary (Npp-ContextMenu ((LineStart 1) + $closing + 1))) -eq 'NORMAL')
Verdict 'on the text after it ("end"): normal menu' ((Summary (Npp-ContextMenu ((LineStart 1) + $closing + 3))) -eq 'NORMAL')
Verdict 'in the empty space right of the end of the line: normal menu' ((Summary (Npp-ContextMenu ((LineStart 1) + $line1.Length) 120 3)) -eq 'NORMAL')
Verdict 'on plain text (line 0): normal menu' ((Summary (Npp-ContextMenu ((LineStart 0) + 3))) -eq 'NORMAL')
$l9 = $lines[9]
foreach ($pair in @(@('my_link[0]', 'my_link[0] (letter before the _)'), @('x_link[path]', 'x_link[path] (letter before the _)'), @('___link[x.txt]', '___link[x.txt] (three _: not a link)'))) {
    Verdict "$($pair[1]): normal menu" ((Summary (Npp-ContextMenu ((LineStart 9) + $l9.IndexOf($pair[0]) + 4))) -eq 'NORMAL')
}
Npp-Activate $iT; Start-Sleep -Milliseconds 500
Verdict 'in a .txt with "__link[...]": normal menu (the plugin only acts on .stdoer)' ((Summary (Npp-ContextMenu 4)) -eq 'NORMAL')
Npp-Activate $iS; Start-Sleep -Milliseconds 500
Verdict 'after all that the document is still identical' ((DocText) -eq $original)

Write-Host '--- a cancelled menu changes nothing (already cancelled above); choosing with the keyboard'
function Choose([int]$line, [int]$k, [int]$n) {
    $before = @(LogLines).Count
    $r = Npp-ContextMenu ((LineStart $line) + $k) -Choose -Down $n
    Start-Sleep -Milliseconds 700
    $new = @(LogLines)[$before..99999] | Where-Object { $_ }
    return [pscustomobject]@{ Items = (Summary $r); Log = ($new -join ' | ') }
}

# Open
$nDocs = (Npp-Documents).Count
$r = Choose 1 2 1
Verdict 'Open on a text file: opens it in a Notepad++ tab' (($r.Log -match 'open: in Notepad\+\+ .*text\.txt') -and ((Npp-Documents).Count -eq $nDocs + 1)) $r.Log
Npp-Activate $iS; Start-Sleep -Milliseconds 400
$r = Choose 2 2 1
Verdict 'Open on a folder: opens the folder' ($r.Log -match 'open: folder .*folder') $r.Log
$r = Choose 3 2 1
Verdict 'Open on an .exe: does NOT run it, shows its folder' (($r.Log -match 'open: containing folder of .*harmless\.exe') -and ($r.Log -notmatch 'with Windows')) $r.Log
$r = Choose 6 2 1
Verdict 'Open on an https address: opens it in the browser' ($r.Log -match 'open: browser https://notepad-plus-plus\.org/') $r.Log
# Open containing folder
$r = Choose 1 2 2
Verdict 'Open containing folder (existing file): shows it in its folder' ($r.Log -match 'open: containing folder of .*text\.txt') $r.Log
$r = Choose 4 2 2
Verdict 'Open containing folder (broken file): opens the folder that does exist' ($r.Log -match 'open: folder .*targets \(the file does not exist\)') $r.Log
# grayed-out options: even if requested through the test channel, they do nothing
Write-Host '--- grayed-out options do nothing (requested through the test channel)'
foreach ($c in @(@(4, 11, 'Open on a broken link'), @(7, 11, 'Open on a rejected scheme'), @(8, 11, 'Open on a relative path'), @(8, 12, 'Open containing folder on a relative path'))) {
    $before = @(LogLines).Count
    [void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', $c[1], [int64]((LineStart $c[0]) + 3))
    Start-Sleep -Milliseconds 500
    $new = (@(LogLines)[$before..99999] | Where-Object { $_ }) -join ' | '
    Verdict "$($c[2]): not available, nothing is done" (($new -match 'is not available') -and ($new -notmatch 'open:')) $new
}

# Disable / Enable: one "_", a single Undo
Write-Host '--- Disable / Enable'
Npp-Activate $iS; Start-Sleep -Milliseconds 400
[void](Sci 2175)                 # SCI_EMPTYUNDOBUFFER: the undo history starts empty
$before = DocText
$r = Choose 1 2 3
$after = DocText
$expected = $before.Remove((LineStart 1), 1)
Verdict 'Disable link: removes exactly ONE "_" (and nothing else)' ($after -eq $expected) $r.Log
Verdict '   the line now starts with "_link[" and the path is shown in full' ($after.Split("`n")[1].StartsWith('_link['))
Verdict '   the disabled link''s menu offers "Enable link"' ((Summary (Npp-ContextMenu ((LineStart 1) + 2))) -eq 'Enable link')
[void](Sci 2176)                 # SCI_UNDO: ONE Ctrl+Z
Verdict '   a SINGLE Undo returns the document as it was' ((DocText) -eq $before)
Verdict '   and there is nothing more to undo' ((Sci 2174) -eq 0)       # SCI_CANUNDO
[void](Sci 2011)                 # SCI_REDO
Verdict '   Redo disables it again' ((DocText) -eq $after)
[void](Sci 2176)

$before = DocText
$r = Choose 5 2 1
$after = DocText
Verdict 'Enable link: adds exactly ONE "_" (and nothing else)' ($after -eq $before.Insert((LineStart 5), '_')) $r.Log
Verdict '   the line now starts with "__link[" and the path is hidden again' (($after.Split("`n")[5].StartsWith('__link[')) -and ((Summary (Npp-ContextMenu ((LineStart 5) + 2))) -eq $A3))
[void](Sci 2176)
Verdict '   a SINGLE Undo returns the document as it was' ((DocText) -eq $before)
Verdict '   and there is nothing more to undo' ((Sci 2174) -eq 0)

# several times in a row, back and forth
$before = DocText
foreach ($i in 1..3) { [void](Choose 1 2 3); [void](Choose 1 2 1) }
Verdict '3 times Disable+Enable in a row: it ends up as at the start' ((DocText) -eq $before)
foreach ($i in 1..6) { [void](Sci 2176) }
Verdict '   and 6 Undos (one per action) leave it as at the start' ((DocText) -eq $original)

# web: Disable and Enable an address
$before = DocText
[void](Choose 6 2 2)
Verdict 'Disable a web address: removes one "_"' ((DocText) -eq $before.Remove((LineStart 6), 1))
[void](Choose 6 2 1)
Verdict 'and Enable leaves it as it was' ((DocText) -eq $before)

# the menu does not change the document if it is cancelled
$before = DocText
foreach ($l in 1, 4, 5, 6, 7) { [void](Npp-ContextMenu ((LineStart $l) + 2)) }
Verdict 'cancelled menus (5 links): the document does not change' ((DocText) -eq $before)

Write-Host '--- read-only'
[void](Sci 2171 1)              # SCI_SETREADONLY
Verdict 'read-only: Disable is grayed out' ((Summary (Npp-ContextMenu ((LineStart 1) + 2))) -eq 'Open | Open containing folder | Disable link (grayed)')
Verdict 'read-only: Enable is grayed out' ((Summary (Npp-ContextMenu ((LineStart 5) + 2))) -eq 'Enable link (grayed)')
$before = DocText
[void][NppT]::MessageToPlugin($script:HNpp, 'Stdoer.dll', 13, [int64]((LineStart 1) + 3))
Start-Sleep -Milliseconds 400
Verdict 'read-only: requesting Disable through the test channel changes nothing' ((DocText) -eq $before)
[void](Sci 2171 0)

Write-Host '--- menu from the keyboard (Menu key / Shift+F10)'
[void](Sci 2025 ((LineStart 1) + 3))   # cursor on the link
Verdict 'cursor on a link: the link menu appears' ((Summary (Npp-ContextMenu 0 -Keyboard)) -eq $A3)
[void](Sci 2025 ((LineStart 0) + 3))
Verdict 'cursor outside a link: normal menu' ((Summary (Npp-ContextMenu 0 -Keyboard)) -eq 'NORMAL')

Verdict 'at the end, the document is still identical to the original' ((DocText) -eq $original)
Write-Host '--- plugin log: no errors'
$all = LogLines
Verdict 'the log mentions no errors' (@($all | Where-Object { $_ -match 'error|exception' }).Count -eq 0)
Write-Host "SUMMARY: $bad failures"
Npp-Close
if ($bad -gt 0) { exit 1 }
