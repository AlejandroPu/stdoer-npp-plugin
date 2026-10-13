# Test of the styles of the __link[path] links in the portable Notepad++.
#
# Usage (from the stdoer folder):   .\tests\test-links.ps1
#
# 1) For each tests\links\<case>.stdoer it compares, byte by byte, the style with <case>.expected
#    (one map line per document line):
#       l = "link[" or "]" (clickable zone)   h = hidden path   r = visible path   . = other
#    The maps are made by hand, not copied from the output.
# 2) Attributes of the view's styles (hidden and unmodifiable path, clickable zone...).
# 3) Showing/hiding the path according to the cursor and the selection.
# It works on copies in build\links\. Nothing is saved.

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$work = Join-Path $Root 'build\links'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$cases = @(Get-ChildItem (Join-Path $Root 'tests\links') -Filter *.stdoer | Sort-Object Name)
$copies = @()
foreach ($c in $cases) { $d = Join-Path $work $c.Name; Copy-Item $c.FullName $d; $copies += $d }

$bad = 0
function Verdict([string]$name, [bool]$ok, [string]$detail = '') {
    if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-62} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  $detail" }))
}

Npp-Open $copies
$docs = Npp-Documents

# --- 1) styles per case ---
foreach ($c in $cases) {
    $base = [IO.Path]::GetFileNameWithoutExtension($c.Name)
    $path = Join-Path $work $c.Name
    $d = $docs | Where-Object { $_.Path -eq $path }
    if (-not $d) { Verdict "$base (open)" $false 'it did not open'; continue }
    Npp-Activate $d.Index
    [void](Sci 2025 0)          # SCI_GOTOPOS 0
    [void](Sci 4003 0 -1)       # SCI_COLOURISE
    Start-Sleep -Milliseconds 300
    $text = SciText
    $actual = SciStyleMap $text
    $expected = ((Get-Content (Join-Path $Root "tests\links\$base.expected") -Raw -Encoding UTF8) -replace "`r", '')
    Verdict "styles: $base" ($actual.TrimEnd("`n") -eq $expected.TrimEnd("`n")) "expected=[$($expected.Replace("`n",'|'))] got=[$($actual.Replace("`n",'|'))]"
}

# --- 2) style attributes (with a .stdoer document active) ---
$d = $docs | Where-Object { $_.Path -like '*E01_basic*' }
Npp-Activate $d.Index
Start-Sleep -Milliseconds 300
Verdict 'style 50 (hidden path): invisible'        ((Sci 2491 50) -eq 0)
Verdict 'style 50 (hidden path): not modifiable'   ((Sci 2492 50) -eq 0)
Verdict 'style 51 (visible path): visible'         ((Sci 2491 51) -eq 1)
Verdict 'style 51 (visible path): modifiable'      ((Sci 2492 51) -eq 1)
Verdict 'style 52 (link[ and ]): clickable zone'   ((Sci 2493 52) -eq 1)

# --- 3) show the path according to the cursor / selection. E01: "__link[a.txt]" (path at 7..11) ---
function CurrentMap { SciStyleMap (SciText) }
function At([int64]$start, [int64]$end) { [void](Sci 2160 $start $end); Start-Sleep -Milliseconds 250 }   # SCI_SETSEL
$hidden = '..lllllhhhhhl'
$shown = '..lllllrrrrrl'
foreach ($p in @(@('cursor at the start of the line', 0, 0, $hidden),
                 @('cursor between "k" and "["', 6, 6, $hidden),
                 @('cursor right after "["', 7, 7, $shown),
                 @('cursor inside the path', 9, 9, $shown),
                 @('cursor right before "]"', 12, 12, $shown),
                 @('cursor right after "]"', 13, 13, $hidden),
                 @('selection that contains the whole link', 0, 13, $shown),
                 @('selection that ends in the path', 0, 9, $shown),
                 @('selection that starts in the path', 9, 13, $shown),
                 @('selection that ends before the path', 0, 6, $hidden),
                 @('cursor back at the start', 0, 0, $hidden))) {
    At $p[1] $p[2]
    $m = (CurrentMap).Split("`n")[0]
    Verdict "revealed: $($p[0])" ($m -eq $p[3]) "expected=[$($p[3])] got=[$m]"
}

Write-Host "SUMMARY: $bad failures"
Npp-Close
if ($bad -gt 0) { exit 1 }
