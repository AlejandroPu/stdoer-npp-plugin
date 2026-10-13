# Checks that hiding the path SURVIVES what Notepad++ does with the styles: switching tabs,
# changing the document's language and resetting all the styles (what it does when the theme
# changes, SCI_STYLECLEARALL). And that, when the document stops being .stdoer, style numbers
# 50-52 go back to normal (another lexer might use them).
#
# Usage (from the stdoer folder):   .\tests\test-link-persistence.ps1

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$work = Join-Path $Root 'build\persistence'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$docA = Join-Path $work 'link.stdoer'; $docB = Join-Path $work 'other.txt'
[IO.File]::WriteAllText($docA, "start __link[secret-paths.txt] end`n", (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText($docB, "plain text document`n", (New-Object Text.UTF8Encoding $false))

$bad = 0
function Verdict([string]$name, [bool]$ok, [string]$detail = '') {
    if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-72} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  $detail" }))
}
function Hidden { ((SciStyleMap (SciText)).Split("`n")[0]) -match '^\.{8}lllllh{16}l' }
function Attributes { "vis50=$(Sci 2491 50) chg50=$(Sci 2492 50) hot52=$(Sci 2493 52)" }
function Nudge { [void](Sci 2025 0); Start-Sleep -Milliseconds 150 }

Npp-Open @($docA, $docB)
$a = (Npp-Documents | Where-Object { $_.Path -eq $docA }).Index
$b = (Npp-Documents | Where-Object { $_.Path -eq $docB }).Index
Npp-Activate $a; [void](Sci 4003 0 -1); Nudge
Verdict 'start: path hidden, styles set' ((Hidden) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) (Attributes)

# 1) switch tabs and come back
Npp-Activate $b; Start-Sleep -Milliseconds 300
Verdict 'in another tab (.txt): styles 50-52 are back to normal' (((Sci 2491 50) -eq 1) -and ((Sci 2492 50) -eq 1) -and ((Sci 2493 52) -eq 0)) (Attributes)
Npp-Activate $a; Start-Sleep -Milliseconds 400; Nudge
Verdict 'back on the .stdoer tab: path hidden again' ((Hidden) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) (Attributes + ' map=' + ((SciStyleMap (SciText)).Split("`n")[0]))
for ($i = 0; $i -lt 5; $i++) { Npp-Activate $b; Npp-Activate $a; Start-Sleep -Milliseconds 150 }
Nudge
Verdict '5 quick round trips between tabs: still hidden' ((Hidden) -and (Sci 2491 50) -eq 0) (Attributes)

# 2) reset all the styles (what Notepad++ does when the theme changes)
[void](Sci 2050)    # SCI_STYLECLEARALL
Start-Sleep -Milliseconds 100
$after = Attributes
[void](Sci 2025 3); Start-Sleep -Milliseconds 300     # the next cursor movement repairs the styles
Nudge
Verdict 'after resetting the styles (STYLECLEARALL) and moving the cursor: hidden again' ((Hidden) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) ("right after the reset: $after ; now: " + (Attributes))

# 3) change the document's language to Python and back to Stdoer
$NPPM_SETCURRENTLANGTYPE = $NPPMSG + 6
[void](NppMsg $NPPM_SETCURRENTLANGTYPE 0 22)           # L_PYTHON
Start-Sleep -Milliseconds 600; [void](Sci 4003 0 -1); Nudge
$m = (SciStyleMap (SciText)).Split("`n")[0]
Verdict 'as Python: the text is fully visible (nothing hidden) and styles normal' (($m -notmatch 'h') -and ((Sci 2491 50) -eq 1) -and ((Sci 2493 52) -eq 0)) ("map=$m " + (Attributes))
[void](NppMsg $NPPM_SETCURRENTLANGTYPE 0 95)           # L_EXTERNAL (Stdoer)
Start-Sleep -Milliseconds 800; [void](Sci 4003 0 -1); Nudge
Verdict 'back to Stdoer: path hidden again' ((Hidden) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) ("map=" + ((SciStyleMap (SciText)).Split("`n")[0]) + ' ' + (Attributes))

Write-Host "SUMMARY: $bad failures"
Npp-Close
if ($bad -gt 0) { exit 1 }
