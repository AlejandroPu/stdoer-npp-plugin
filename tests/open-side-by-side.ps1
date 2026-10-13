# Opens the portable Notepad++ with a .py and its .stdoer copy side by side (.py on the
# left, .stdoer on the right) and leaves it open for trying by hand.
#
# Usage (from the stdoer folder):
#   .\tests\open-side-by-side.ps1                      # personal copies in samples\
#   .\tests\open-side-by-side.ps1 -Base build\cmp\01_blanks
#
# -Base is the path WITHOUT extension; <Base>.py and <Base>.stdoer must exist.
# Alternative: -Left and -Right with paths of any two files (e.g. two .stdoer):
#   .\tests\open-side-by-side.ps1 -Left samples\braces-demo.stdoer -Right samples\personal-sample.stdoer
# It only uses the portable copy (-multiInst -nosession). It modifies no document.

param([string]$Base = 'samples\personal-sample', [string]$Left = '', [string]$Right = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $root 'npp-portable\notepad++.exe'
if ($Left -ne '' -and $Right -ne '') {
    $py = Join-Path $root $Left; $st = Join-Path $root $Right
} else {
    $py = Join-Path $root ($Base + '.py'); $st = Join-Path $root ($Base + '.stdoer')
}
foreach ($f in $py, $st) { if (-not (Test-Path $f)) { throw "$f does not exist" } }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinSide {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@
function Send($h, $m, [int64]$w = 0, [int64]$l = 0) { [int64][WinSide]::SendMessage($h, [uint32]$m, [IntPtr]$w, [IntPtr]$l) }
$NPPMSG = 0x400 + 1000
$NPPM_GETNBOPENFILES = $NPPMSG + 7
$NPPM_ACTIVATEDOC    = $NPPMSG + 28
$NPPM_MENUCOMMAND    = $NPPMSG + 48
$IDM_VIEW_GOTO_ANOTHER_VIEW = 10001

$p = Start-Process $exe -ArgumentList @('-multiInst', '-nosession', ('"' + $py + '"'), ('"' + $st + '"')) -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'The portable Notepad++ window did not appear' }
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; if ((Send $h $NPPM_GETNBOPENFILES 0 0) -ge 2) { break } }
Start-Sleep -Seconds 2

# The last file opened (.stdoer) is the one left active; it is moved to the other view.
$n = Send $h $NPPM_GETNBOPENFILES 0 0
[void](Send $h $NPPM_ACTIVATEDOC 0 ($n - 1))
Start-Sleep -Milliseconds 300
[void](Send $h $NPPM_MENUCOMMAND 0 $IDM_VIEW_GOTO_ANOTHER_VIEW)
Start-Sleep -Milliseconds 500
Write-Host "Opened: $py  (left)  and  $st  (right). Close the portable copy when you are done."
