# EDITING test of the folding with { }: without forcing the coloring, a brace is deleted/typed
# in a copy (in memory, unsaved) and it is checked that the folding of ALL the lines, also
# those before the change, ends up as it should.
#
# Usage (from the stdoer folder):   .\tests\edit-braces.ps1
# It only uses the portable Notepad++. It works on build\edit\L01_basic.stdoer and does not save.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $root 'npp-portable\notepad++.exe'
$work = Join-Path $root 'build\edit'
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class WinE {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static List<IntPtr> Scintillas(IntPtr parent) {
        var r = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { var sb = new StringBuilder(64); GetClassName(h, sb, 64);
            if (sb.ToString() == "Scintilla" && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero);
        return r; }
}
'@
function Send($h, $m, [int64]$w = 0, [int64]$l = 0) { [int64][WinE]::SendMessage($h, [uint32]$m, [IntPtr]$w, [IntPtr]$l) }
$SCI_GETLINECOUNT = 2154; $SCI_GETFOLDLEVEL = 2223; $SCI_GOTOPOS = 2025; $SCI_DELETERANGE = 2645; $SCI_UNDO = 2176; $WM_CHAR = 0x102
$NPPM_GETNBOPENFILES = 0x400 + 1000 + 7

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$doc = Join-Path $work 'L01_basic.stdoer'
Copy-Item (Join-Path $root 'tests\braces\L01_basic.stdoer') $doc
$p = Start-Process $exe -ArgumentList @('-multiInst', '-nosession', ('"' + $doc + '"')) -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'The window did not appear' }
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; if ((Send $h $NPPM_GETNBOPENFILES) -ge 1) { break } }
Start-Sleep -Seconds 2
$view = ([WinE]::Scintillas($h))[0]
function Levels {
    Start-Sleep -Milliseconds 1500
    $o = @(); $n = Send $view $SCI_GETLINECOUNT
    for ($k = 0; $k -lt $n; $k++) { $v = [int](Send $view $SCI_GETFOLDLEVEL $k); $s = [string](($v -band 0xFFF) - 1024); if ($v -band 0x2000) { $s += 'H' }; $o += $s }
    $o -join ' '
}
$bad = 0
function Check($name, $expected) {
    $got = Levels
    $ok = ($got -eq $expected); if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-52} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  expected=[$expected] got=[$got]" }))
}
# The text is a line ending in "{", two body lines, the closing "}" and one line after it:
# the "}" is at position 17; the end of the first body line is at 12.
Check 'initial (not edited)' '0H 1 1 1 0 0'
[void](Send $view $SCI_DELETERANGE 17 1)
Check 'delete the "}" -> "{" is left unmatched and ignored' '0 0 0 0 0 0'
[void](Send $view $SCI_UNDO)
Check 'undo -> the region comes back' '0H 1 1 1 0 0'
[void](Send $view $SCI_GOTOPOS 12); [void](Send $view $WM_CHAR ([int][char]'{') 0)
Check 'type "{" at the end of the first body line (the "}" pairs with it)' '0 0H 1 1 0 0'
[void](Send $view $SCI_UNDO)
Check 'undo -> the original region comes back' '0H 1 1 1 0 0'
[void](Send $view $SCI_GOTOPOS 12); [void](Send $view $WM_CHAR ([int][char]'}') 0)
Check '"}" typed at the end of the first body line (not first character)' '0H 1 1 1 0 0'
Write-Host "SUMMARY: $bad failures"
# The document was left modified (it is a copy in build\edit, never saved): the own process is
# terminated instead of asking for a normal close, which would open a save prompt.
Stop-Process -Id $p.Id -Force
if ($bad -gt 0) { exit 1 }
