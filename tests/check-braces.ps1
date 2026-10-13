# Verifies the folding with { } of the stdoer lexer: opens in the portable Notepad++ each
# tests\braces\*.stdoer, forces full coloring and compares the fold level
# (SCI_GETFOLDLEVEL) of EVERY line with tests\braces\<case>.expected.
#
# Usage (from the stdoer folder):   .\tests\check-braces.ps1
#
# Format of .expected (one line of text, one token per document line):
#   <depth>[H]     depth = level - 1024; H = fold header (it can be folded).
# The expected values are worked out by hand from the rules (src\Braces.h), not taken from
# the program's output. A document without matched braces keeps Python's levels
# (in a document without indentation, all 0).
#
# - Uses ONLY the portable Notepad++ (npp-portable), with -multiInst -nosession.
# - No document is modified (it works on copies in build\braces\).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $root 'npp-portable\notepad++.exe'
$work = Join-Path $root 'build\braces'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class WinL {
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

function Send($h, $m, [int64]$w = 0, [int64]$l = 0) { [int64][WinL]::SendMessage($h, [uint32]$m, [IntPtr]$w, [IntPtr]$l) }

$NPPMSG = 0x400 + 1000
$NPPM_GETNBOPENFILES    = $NPPMSG + 7
$NPPM_ACTIVATEDOC       = $NPPMSG + 28
$NPPM_GETCURRENTBUFFERID= $NPPMSG + 60
$NPPM_GETBUFFERLANGTYPE = $NPPMSG + 64
$SCI_GETLENGTH = 2006; $SCI_GETLINECOUNT = 2154; $SCI_GETFOLDLEVEL = 2223; $SCI_COLOURISE = 4003

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$cases = @(Get-ChildItem (Join-Path $root 'tests\braces') -Filter *.stdoer | Sort-Object Name)
$files = @()
foreach ($f in $cases) {
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $copy = Join-Path $work $f.Name
    Copy-Item $f.FullName $copy
    $exp = (Get-Content (Join-Path $root "tests\braces\$base.expected") -Raw).Trim()
    $files += [pscustomobject]@{ Base = $base; Path = $copy; Expected = $exp }
}

$nppArgs = @('-multiInst', '-nosession') + ($files | ForEach-Object { '"' + $_.Path + '"' })
$p = Start-Process $exe -ArgumentList $nppArgs -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'The portable Notepad++ window did not appear' }

$expectedCount = $files.Count; $n = 0
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; $n = Send $h $NPPM_GETNBOPENFILES 0 0; if ($n -ge $expectedCount) { break } }
Start-Sleep -Seconds 2
Write-Host "Open documents: $n (expected $expectedCount)"
if ($n -lt $expectedCount) { throw 'Not all the files were opened' }

$sci = [WinL]::Scintillas($h)
if ($sci.Count -lt 1) { throw 'The main Scintilla was not found' }
$view = $sci[0]

# Match tabs with files by length (there may be one extra empty tab).
$lengths = @()
for ($i = 0; $i -lt $n; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 $i); Start-Sleep -Milliseconds 80
    $lengths += (Send $view $SCI_GETLENGTH)
}
$offset = -1
for ($d = 0; $d -le ($n - $expectedCount); $d++) {
    $allMatch = $true
    for ($i = 0; $i -lt $expectedCount; $i++) { if ($lengths[$i + $d] -ne (Get-Item $files[$i].Path).Length) { $allMatch = $false; break } }
    if ($allMatch) { $offset = $d; break }
}
if ($offset -lt 0) { throw 'The tabs could not be matched with the files by length' }

function Fmt([int]$v) {
    $s = [string](($v -band 0xFFF) - 1024)
    if ($v -band 0x2000) { $s += 'H' }
    $s
}
$ok = 0; $bad = 0
$report = New-Object 'System.Collections.Generic.List[string]'
$report.Add("Braces check - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
for ($i = 0; $i -lt $expectedCount; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 ($i + $offset)); Start-Sleep -Milliseconds 80
    [void](Send $view $SCI_COLOURISE 0 -1)
    $a = $files[$i]
    $lang = Send $h $NPPM_GETBUFFERLANGTYPE (Send $h $NPPM_GETCURRENTBUFFERID) 0
    $lineCount = Send $view $SCI_GETLINECOUNT
    $got = @(); for ($k = 0; $k -lt $lineCount; $k++) { $got += (Fmt ([int](Send $view $SCI_GETFOLDLEVEL $k))) }
    $actual = $got -join ' '
    $good = ($actual -eq $a.Expected) -and ($lang -eq 95)
    $state = if ($good) { 'OK' } else { 'BAD' }
    $line = "{0,-36} {1}" -f $a.Base, $state
    Write-Host $line
    $report.Add($line)
    if ($good) { $ok++ } else {
        $bad++
        $report.Add("   language=$lang (expected 95)")
        $report.Add("   expected: $($a.Expected)")
        $report.Add("   got:      $actual")
        Write-Host "   expected: $($a.Expected)"; Write-Host "   got:      $actual"
    }
}
$report.Add("SUMMARY: $ok good, $bad bad, out of $expectedCount cases")
$report | Set-Content -Encoding utf8 (Join-Path $work 'report.txt')
Write-Host "SUMMARY: $ok good, $bad bad, out of $expectedCount cases"

[void]$p.CloseMainWindow(); Start-Sleep -Seconds 2
if (-not $p.HasExited) { Write-Host 'The portable copy is still open; close it by hand.' }
if ($bad -gt 0) { exit 1 }
