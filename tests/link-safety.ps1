# SAFETY tests of the hidden text of the links.
#
# Criterion: no common action may delete or change the hidden path without it being seen. If
# one fails, the acceptable outcome is that the link ends up visible; never that the text
# changes behind the user's back.
#
# Usage (from the stdoer folder):   .\tests\link-safety.ps1  [-NoClipboard]
#
# Test document (made up):   start __link[SECRET-1234] after
# Each scenario: the cursor/selection is prepared, it is noted whether the path was SHOWN, the
# action is done (with the same commands as the keys: Backspace, Delete, typing...), and the
# result is judged:
#   OK intact      the path is unchanged
#   OK undone      no link is left (all the text ended up in view or was deleted entirely)
#   OK seen        the path changed, but it was shown when the action was done
#   OK exposed     the path changed in a way that cannot be seen (Replace All) and the plugin
#                  left it in view and/or put up a warning (annotation under the link)
#   FAIL           the path changed while hidden
# And it is checked that Undo returns the original text and Redo the result.
# Actions with the clipboard overwrite it: its content is saved and restored if it is text
# (if it is not, those tests are skipped). It works in the portable copy, saving nothing.

param([switch]$NoClipboard)
$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$work = Join-Path $Root 'build\safety'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$file = Join-Path $work 'S01.stdoer'
$D0 = "start __link[SECRET-1234] after`nend`n"
$ORIG = 'SECRET-1234'
[IO.File]::WriteAllText($file, $D0, (New-Object Text.UTF8Encoding $false))

Npp-Open @($file) -Log (Join-Path $work 'stdoer.log')
$doc = Npp-Documents | Where-Object { $_.Path -eq $file }
Npp-Activate $doc.Index

$SCI_SETTEXT = 2181; $SCI_EMPTYUNDOBUFFER = 2175; $SCI_COLOURISE = 4003; $SCI_GOTOPOS = 2025
$SCI_SETSEL = 2160; $SCI_UNDO = 2176; $SCI_REDO = 2011; $SCI_DELETEBACK = 2326; $SCI_CLEAR = 2180
$SCI_CHARRIGHT = 2306; $SCI_CHARLEFT = 2304; $SCI_GETCURRENTPOS = 2008; $SCI_CUT = 2177
$SCI_COPY = 2178; $SCI_PASTE = 2179; $SCI_REPLACESEL = 2170; $SCI_SETTARGETRANGE = 2686
$SCI_SEARCHINTARGET = 2197; $SCI_REPLACETARGET = 2194; $SCI_GETLENGTH = 2006; $SCI_SETTARGETSTART = 2190; $SCI_SETTARGETEND = 2192
$WM_CHAR = 0x102

function Reset-Doc {
    [void](SciString $SCI_SETTEXT 0 $D0)
    [void](Sci $SCI_EMPTYUNDOBUFFER)
    [void](Sci $SCI_COLOURISE 0 -1)
    [void](Sci $SCI_GOTOPOS 0)
    Start-Sleep -Milliseconds 30
}
function Path-Shown { (SciStyleMap (SciText)) -match 'r' }
function Links-Of([string]$text) { [regex]::Matches($text, '__link\[([^\]]*)\]') | ForEach-Object { $_.Groups[1].Value } }

# Judges the result of an action.
function Judge([string]$before, [bool]$shown, [string]$after, [string]$mapAfter, [bool]$warningActive) {
    if ($after -eq $before) { return 'OK same' }
    $paths = @(Links-Of $after)
    if ($paths -contains $ORIG) { return 'OK intact' }
    if ($paths.Count -eq 0) { return 'OK undone' }
    if ($shown) { return 'OK seen' }
    if ($warningActive -or ($mapAfter -match 'r' -and $mapAfter -notmatch 'h')) { return 'OK exposed' }
    return 'FAIL'
}

$results = New-Object 'System.Collections.Generic.List[object]'
$failures = 0; $undoFailures = 0
function Scenario([string]$group, [string]$name, [scriptblock]$prepare, [scriptblock]$action) {
    if ($group -like 'replace*') { Write-Host ("  " + (Get-Date -Format 'HH:mm:ss') + " ... $name") }
    Reset-Doc
    & $prepare
    Start-Sleep -Milliseconds 40
    $before = SciText
    $shown = Path-Shown
    $script:shownAtChange = $null
    & $action
    Start-Sleep -Milliseconds 40
    if ($script:shownAtChange -ne $null) { $shown = $script:shownAtChange }
    $after = SciText
    $v = Judge $before $shown $after (SciStyleMap $after) ((Sci 2546 0) -gt 0)   # SCI_ANNOTATIONGETLINES of line 0: the plugin's warning
    # Undo / redo
    $undoOk = $true; $redoOk = $true
    if ($after -ne $before) {
        for ($i = 0; $i -lt 6 -and (SciText) -ne $before; $i++) { [void](Sci $SCI_UNDO) }
        $undoOk = ((SciText) -eq $before)
        for ($i = 0; $i -lt 6 -and (SciText) -ne $after; $i++) { [void](Sci $SCI_REDO) }
        $redoOk = ((SciText) -eq $after)
    }
    if ($v -eq 'FAIL') { $script:failures++ }
    if (-not $undoOk -or -not $redoOk) { $script:undoFailures++ }
    $results.Add([pscustomobject]@{ Group = $group; Name = $name; Verdict = $v; Shown = $shown; Undo = $undoOk; Redo = $redoOk; After = ($after -replace "`n", '\n') })
}

# ---------- 1) move the cursor with the arrows through the link ----------
Reset-Doc
$badCursor = @()
[void](Sci $SCI_GOTOPOS 3)
for ($i = 0; $i -lt 30; $i++) {
    [void](Sci $SCI_CHARRIGHT); Start-Sleep -Milliseconds 20
    $pos = Sci $SCI_GETCURRENTPOS
    $expectShown = ($pos -ge 13 -and $pos -le 24)
    $m = (SciStyleMap (SciText)).Split("`n")[0]
    $any = $m -match 'r'; $hidden = $m -match 'h'
    if ($expectShown -and (-not $any -or $hidden)) { $badCursor += "pos $pos should be shown: $m" }
    if (-not $expectShown -and ($any -or ($pos -ge 6 -and -not $hidden))) { $badCursor += "pos $pos should be hidden: $m" }
}
for ($i = 0; $i -lt 30; $i++) {
    [void](Sci $SCI_CHARLEFT); Start-Sleep -Milliseconds 20
    $pos = Sci $SCI_GETCURRENTPOS
    $expectShown = ($pos -ge 13 -and $pos -le 24)
    $m = (SciStyleMap (SciText)).Split("`n")[0]
    $any = $m -match 'r'; $hidden = $m -match 'h'
    if ($expectShown -and (-not $any -or $hidden)) { $badCursor += "(<-) pos $pos should be shown: $m" }
    if (-not $expectShown -and ($any -or ($pos -ge 6 -and -not $hidden))) { $badCursor += "(<-) pos $pos should be hidden: $m" }
}
Write-Host ("arrows: walk through the link with -> and <- (60 steps): " + $(if ($badCursor.Count -eq 0) { 'OK (the path is shown while the cursor touches it and hidden outside)' } else { 'BAD' }))
$badCursor | ForEach-Object { Write-Host "   $_" }

# ---------- 2) type, Backspace and Delete with the cursor at each position ----------
foreach ($p in 3..27) {
    Scenario 'type'      "type Z with the cursor at $p"        { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $WM_CHAR ([int][char]'Z') 0) }
    Scenario 'backspace' "Backspace with the cursor at $p"     { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $SCI_DELETEBACK) }
    Scenario 'delete'    "Delete with the cursor at $p"        { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $SCI_CLEAR) }
}

# ---------- 3) selections: type over and delete ----------
$points = 4, 6, 8, 12, 13, 15, 20, 24, 25, 27
foreach ($a in $points) { foreach ($b in $points) { if ($b -gt $a) {
    Scenario 'sel-type'      "type Z over the selection $a..$b"       { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $WM_CHAR ([int][char]'Z') 0) }
    Scenario 'sel-delete'    "Delete the selection $a..$b"            { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_CLEAR) }
    Scenario 'sel-backspace' "Backspace with the selection $a..$b"    { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_DELETEBACK) }
} } }

# ---------- 4) copy / cut / paste / overwrite (uses the clipboard) ----------
$skipClipboard = $NoClipboard.IsPresent
$saved = $null
if (-not $skipClipboard) {
    Add-Type -AssemblyName System.Windows.Forms
    $data = [Windows.Forms.Clipboard]::GetDataObject()
    $formats = if ($data) { @($data.GetFormats($false)) } else { @() }
    $textOnly = ($formats.Count -eq 0) -or (@($formats | Where-Object { $_ -notin @('Text', 'UnicodeText', 'OEMText', 'System.String', 'Locale') }).Count -eq 0)
    if (-not $textOnly) { Write-Host 'clipboard: it holds non-text data; the clipboard tests are skipped'; $skipClipboard = $true }
    elseif ($data -and $data.GetDataPresent([string])) { $saved = [Windows.Forms.Clipboard]::GetText() }
}
if (-not $skipClipboard) {
    foreach ($a in $points) { foreach ($b in $points) { if ($b -gt $a) {
        Scenario 'cut' "Cut the selection $a..$b" { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_CUT) }
    } } }
    # paste over a selection and paste with the cursor at each position; the pasted text is "PASTED"
    [Windows.Forms.Clipboard]::SetText('PASTED')
    foreach ($a in $points) { foreach ($b in $points) { if ($b -gt $a) {
        Scenario 'paste-over' "Paste over the selection $a..$b" { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_PASTE) }
    } } }
    foreach ($p in 3..27) {
        Scenario 'paste' "Paste with the cursor at $p" { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $SCI_PASTE) }
    }
    # copying does not modify: it is checked that the text does not change and that the full path is copied
    Scenario 'copy' 'Copy the selection 4..27' { [void](Sci $SCI_SETSEL 4 27) } { [void](Sci $SCI_COPY) }
    $copied = [Windows.Forms.Clipboard]::GetText()
    Write-Host ("copy: the clipboard receives '" + $copied + "' " + $(if ($copied -like '*SECRET-1234*') { '(it includes the hidden path, like the rest of the text)' } else { '(it does NOT include the path)' }))
    if ($saved -ne $null) { [Windows.Forms.Clipboard]::SetText($saved) } else { [Windows.Forms.Clipboard]::Clear() }
}

# ---------- 5) find and replace ----------
# Replace (one button): the search selects the match and then the target is replaced.
function Replace-One([string]$find, [string]$with) {
    [void](Sci 2198 0)   # SCI_SETSEARCHFLAGS 0: Notepad++'s dialog leaves options active
    [void](Sci $SCI_SETTARGETRANGE 0 (Sci $SCI_GETLENGTH))
    $pos = SciString $SCI_SEARCHINTARGET ([Text.Encoding]::UTF8.GetByteCount($find)) $find
    if ($pos -ge 0) {
        $end = $pos + [Text.Encoding]::UTF8.GetByteCount($find)
        [void](Sci $SCI_SETSEL $pos $end)             # "Find next" selects the match
        Start-Sleep -Milliseconds 40
        $script:shownAtChange = Path-Shown            # was the path visible right before replacing?
        [void](Sci $SCI_SETTARGETRANGE $pos $end)
        [void](SciString $SCI_REPLACETARGET ([Text.Encoding]::UTF8.GetByteCount($with)) $with)
    }
}
Scenario 'replace' 'Replace (one selected match) ECRET with XX' { } { Replace-One 'ECRET' 'XX' }
Scenario 'replace' 'Replace the match "start" (outside the path)'  { } { Replace-One 'start' 'START' }
# Replace All with Notepad++'s REAL dialog: it selects nothing, uses SCI_REPLACETARGET and turns
# off modification notifications. The plugin must find out through NPPN_GLOBALMODIFIED.
Scenario 'replace-all' 'Replace All (real dialog) ECRET with XX' { } { Npp-ReplaceAllDialog 'ECRET' 'XX' }
Scenario 'replace-all' 'Replace All (real dialog) "start" with "START" (outside the path)' { } { Npp-ReplaceAllDialog 'start' 'START' }
Scenario 'replace-all' 'Replace All (real dialog) SECRET-1234 with nothing' { } { Npp-ReplaceAllDialog 'SECRET-1234' '' }
# Through the programming route (another plugin): without a Notepad++ notice there is no way
# to find out. It is noted as a known limitation; it does not count as a plugin failure.
$limitation = $null
Write-Host ('  ' + (Get-Date -Format 'HH:mm:ss') + ' ... direct REPLACETARGET')
Reset-Doc
$beforeL = SciText
[void](Sci 2198 0)   # SCI_SETSEARCHFLAGS 0
[void](Sci $SCI_SETTARGETRANGE 0 (Sci $SCI_GETLENGTH))
$posL = SciString $SCI_SEARCHINTARGET 5 'ECRET'
if ($posL -ge 0) {   # NEVER use -1 as a position: Scintilla crashes with an invalid target
    [void](Sci $SCI_SETTARGETRANGE $posL ($posL + 5))
    [void](SciString $SCI_REPLACETARGET 2 'XX')
}
Start-Sleep -Milliseconds 100
$limitation = 'direct REPLACETARGET (as another plugin would do), without a Notepad++ notice: path ' + $(if ($posL -lt 0) { 'could not be tested (the search did not find the text)' } elseif ((SciText) -eq $beforeL) { 'intact' } else { 'CHANGED without being visible (known limitation)' })

# ---------- report ----------
$groups = $results | Group-Object Group
Write-Host ''
Write-Host ('{0,-16} {1,6} {2,9} {3,9} {4,9} {5,7}' -f 'group', 'cases', 'intact', 'undone', 'seen', 'FAIL')
foreach ($g in $groups) {
    $c = $g.Group
    Write-Host ('{0,-16} {1,6} {2,9} {3,9} {4,9} {5,7}' -f $g.Name, $c.Count,
        (@($c | Where-Object { $_.Verdict -in 'OK intact', 'OK same' }).Count),
        (@($c | Where-Object { $_.Verdict -eq 'OK undone' }).Count),
        (@($c | Where-Object { $_.Verdict -in 'OK seen', 'OK exposed' }).Count),
        (@($c | Where-Object { $_.Verdict -eq 'FAIL' }).Count))
}
Write-Host ''
$badOnes = @($results | Where-Object { $_.Verdict -eq 'FAIL' })
foreach ($m in $badOnes | Select-Object -First 40) { Write-Host ("FAIL [{0}] {1}  -> {2}" -f $m.Group, $m.Name, $m.After) }
$badUndo = @($results | Where-Object { -not $_.Undo -or -not $_.Redo })
foreach ($m in $badUndo | Select-Object -First 20) { Write-Host ("UNDO/REDO does not match [{0}] {1} (undo={2} redo={3})" -f $m.Group, $m.Name, $m.Undo, $m.Redo) }
Write-Host ("note: " + $limitation)
Write-Host ("SUMMARY: {0} scenarios, {1} FAILURES (path changed while hidden), {2} with different Undo/Redo, {3} cursor failures" -f $results.Count, $failures, $undoFailures, $badCursor.Count)
$results | Export-Csv (Join-Path $work 'results.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('  ' + (Get-Date -Format 'HH:mm:ss') + ' ... closing; portable copy alive: ' + (-not $script:ProcNpp.HasExited))
Npp-Close
if ($failures -gt 0 -or $undoFailures -gt 0 -or $badCursor.Count -gt 0) { exit 1 }
