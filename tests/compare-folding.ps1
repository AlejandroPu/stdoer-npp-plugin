# Compares, line by line, the fold level (SCI_GETFOLDLEVEL) that Notepad++ gives to the
# same text opened as Python (.py) and as Stdoer (.stdoer). It is the objective test of
# folding by indentation: it must come out IDENTICAL.
#
# Usage (from the stdoer folder):   .\tests\compare-folding.ps1
#
# - Uses ONLY the portable Notepad++ (npp-portable), with -multiInst -nosession.
# - Cases: tests\cases\*.py (made up) and, if they exist, samples\*.py (personal copies,
#   outside git). An identical .stdoer copy of each .py is made in build\cmp\.
# - Messages to Notepad++/Scintilla: only with numeric arguments (they work across
#   processes). No document is modified.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $root 'npp-portable\notepad++.exe'
$work = Join-Path $root 'build\cmp'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class Win {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static List<IntPtr> Scintillas(IntPtr parent) {
        var r = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => {
            var sb = new StringBuilder(64); GetClassName(h, sb, 64);
            if (sb.ToString() == "Scintilla" && IsWindowVisible(h)) r.Add(h);
            return true; }, IntPtr.Zero);
        return r;
    }
}
'@

function Send($h, $m, [int64]$w = 0, [int64]$l = 0) { [int64][Win]::SendMessage($h, [uint32]$m, [IntPtr]$w, [IntPtr]$l) }

$NPPMSG = 0x400 + 1000
$NPPM_GETNBOPENFILES    = $NPPMSG + 7
$NPPM_ACTIVATEDOC       = $NPPMSG + 28
$NPPM_GETCURRENTBUFFERID= $NPPMSG + 60
$NPPM_GETBUFFERLANGTYPE = $NPPMSG + 64
$SCI_GETLENGTH = 2006; $SCI_GETLINECOUNT = 2154; $SCI_GETFOLDLEVEL = 2223; $SCI_COLOURISE = 4003

# --- prepare the .py / .stdoer pairs ---
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$sources = @(Get-ChildItem (Join-Path $root 'tests\cases') -Filter *.py | Sort-Object Name)
$personal = Join-Path $root 'samples'
if (Test-Path $personal) { $sources += @(Get-ChildItem $personal -Filter *.py | Sort-Object Name) }
$files = @()
foreach ($f in $sources) {
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $py = Join-Path $work ($base + '.py'); $st = Join-Path $work ($base + '.stdoer')
    Copy-Item $f.FullName $py; Copy-Item $f.FullName $st
    $files += [pscustomobject]@{ Base = $base; Py = $py; St = $st; Bytes = (Get-Item $py).Length; Personal = ($f.DirectoryName -eq $personal) }
}
$list = @(); foreach ($a in $files) { $list += $a.Py; $list += $a.St }

# --- open the portable copy with all the files ---
$nppArgs = @('-multiInst', '-nosession') + ($list | ForEach-Object { '"' + $_ + '"' })
$p = Start-Process $exe -ArgumentList $nppArgs -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'The portable Notepad++ window did not appear' }

$expected = $list.Count; $n = 0
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; $n = Send $h $NPPM_GETNBOPENFILES 0 0; if ($n -ge $expected) { break } }
Start-Sleep -Seconds 2
Write-Host "Open documents: $n (expected $expected)"
if ($n -lt $expected) { throw 'Not all the files were opened' }

$sci = [Win]::Scintillas($h)
if ($sci.Count -lt 1) { throw 'The main Scintilla was not found' }
$view = $sci[0]

# Notepad++ may leave an empty tab "new 1" besides the files. All the tabs are walked and
# the offset is looked for at which each tab's length in bytes (SCI_GETLENGTH) matches
# that of the corresponding file.
$lengths = @()
for ($i = 0; $i -lt $n; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 $i)
    Start-Sleep -Milliseconds 80
    $lengths += (Send $view $SCI_GETLENGTH)
}
$offset = -1
for ($d = 0; $d -le ($n - $expected); $d++) {
    $allMatch = $true
    for ($i = 0; $i -lt $expected; $i++) { if ($lengths[$i + $d] -ne (Get-Item $list[$i]).Length) { $allMatch = $false; break } }
    if ($allMatch) { $offset = $d; break }
}
if ($offset -lt 0) { throw 'The tabs could not be matched with the files by length' }
Write-Host "Extra tabs before the files: $offset"

$results = @{}
$problems = @()
for ($i = 0; $i -lt $expected; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 ($i + $offset))
    Start-Sleep -Milliseconds 80
    [void](Send $view $SCI_COLOURISE 0 -1)
    $file = $list[$i]
    $lang = Send $h $NPPM_GETBUFFERLANGTYPE (Send $h $NPPM_GETCURRENTBUFFERID) 0
    $lineCount = Send $view $SCI_GETLINECOUNT
    $levels = New-Object 'System.Collections.Generic.List[int]'
    for ($k = 0; $k -lt $lineCount; $k++) { $levels.Add([int](Send $view $SCI_GETFOLDLEVEL $k)) }
    $results[$file] = [pscustomobject]@{ Lang = $lang; Levels = $levels }
}
# --- compare ---
function Fmt([int]$v) {
    $base = $v -band 0x3FF
    $s = "$base"
    if ($v -band 0x2000) { $s += 'H' }
    if ($v -band 0x1000) { $s += 'b' }
    $s
}
$ok = 0; $diff = 0
$report = New-Object 'System.Collections.Generic.List[string]'
$report.Add("Folding comparison .py vs .stdoer - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$report.Add('Levels: number = level; H = fold header; b = blank line (flag).')
foreach ($a in $files) {
    $r1 = $results[$a.Py]; $r2 = $results[$a.St]
    $sameCount = ($r1.Levels.Count -eq $r2.Levels.Count)
    $diffs = @()
    if ($sameCount) { for ($k = 0; $k -lt $r1.Levels.Count; $k++) { if ($r1.Levels[$k] -ne $r2.Levels[$k]) { $diffs += $k } } }
    $identical = $sameCount -and ($diffs.Count -eq 0)
    $total = $r1.Levels.Count
    $state = if ($identical) { 'IDENTICAL' } else { 'DIFFERENT' }
    $line = "{0,-34} language py={1} stdoer={2}  lines={3}  {4}" -f $a.Base, $r1.Lang, $r2.Lang, $total, $state
    Write-Host $line
    $report.Add($line)
    if ($identical) { $ok++ } else {
        $diff++
        if (-not $sameCount) { $report.Add("   different number of lines: py=$($r1.Levels.Count) stdoer=$($r2.Levels.Count)") }
        foreach ($k in $diffs) { $report.Add("   line $($k+1): py=$(Fmt $r1.Levels[$k])  stdoer=$(Fmt $r2.Levels[$k])") }
    }
    if (-not $a.Personal) {   # detail only for the made-up cases (personal copies are not dumped)
        $report.Add('   py     : ' + (($r1.Levels | ForEach-Object { Fmt $_ }) -join ' '))
        $report.Add('   stdoer : ' + (($r2.Levels | ForEach-Object { Fmt $_ }) -join ' '))
    }
}
$report.Add("SUMMARY: $ok identical, $diff different, out of $($files.Count) pairs")
foreach ($m in $problems) { $report.Add("WARNING: $m"); Write-Host "WARNING: $m" }
$report | Set-Content -Encoding utf8 (Join-Path $work 'report.txt')
Write-Host "SUMMARY: $ok identical, $diff different, out of $($files.Count) pairs"
Write-Host "Report: $(Join-Path $work 'report.txt')"

# --- close (normal close; nothing is modified) ---
[void]$p.CloseMainWindow(); Start-Sleep -Seconds 2
if (-not $p.HasExited) { Write-Host 'The portable copy is still open; close it by hand.' }
if ($diff -gt 0 -or $problems.Count -gt 0) { exit 1 }
