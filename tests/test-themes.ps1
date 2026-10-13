# Checks that a .stdoer document takes the colors of the ACTIVE Notepad++ THEME (the 0.4.0
# defect: indentation and end of line with a white background in dark themes). It is MEASURED,
# not eyeballed:
#   - background of each style used by the document == background of the theme's default style;
#   - text color of each style (except the visible path) == the theme's default color;
#   - the visible path (51) == midpoint between text and background; the color on mouse hover
#     contrasts with the background; no style with end-of-line fill;
#   - style 0 matches that of a .txt opened in the same window.
# Part A: start with each configuration (light, dark mode, themes that Notepad++ ships).
# Part B: HOT theme change with the document open, from the Style Configurator (what the user
#         does), with round trips between tabs.
# Part C: HOT dark mode / light mode from Preferences (Light mode / Dark mode).
#
# It touches npp-portable\config.xml (portable copy, NOT %AppData%): it saves the original in
# build\config-original.xml and restores it at the end, whatever happens.
#
# Usage (from the stdoer folder):   .\tests\test-themes.ps1

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'npp-tools.ps1')

$cfg = Join-Path $Root 'npp-portable\config.xml'
$backup = Join-Path $Root 'build\config-original.xml'
$work = Join-Path $Root 'build\themes'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Root 'tests\targets'
$docS = Join-Path $work 'theme.stdoer'; $docT = Join-Path $work 'theme.txt'
$content = @"
def f():
    x = 1  # comment
    y = "text"
    __link[$obj\text.txt] y _link[x] disabled
    __link[https://notepad-plus-plus.org/]

    {
        z = 2
    }
"@ -replace "`r`n", "`n"
[IO.File]::WriteAllText($docS, $content + "`n", (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText($docT, "plain text`n    with indentation`n", (New-Object Text.UTF8Encoding $false))

if (-not (Test-Path $backup)) { Copy-Item $cfg $backup }   # the original, only once

$bad = 0
function Verdict([string]$name, [bool]$ok, [string]$detail = '') {
    if (-not $ok) { $script:bad++ }
    Write-Host ("{0,-86} {1}" -f $name, $(if ($ok) { 'OK' } else { "BAD  $detail" }))
}
function Hex([int64]$c) { '{0:X2}{1:X2}{2:X2}' -f ($c -band 0xFF), (($c -shr 8) -band 0xFF), (($c -shr 16) -band 0xFF) }   # Scintilla BGR -> RRGGBB
function Channel([int64]$c, [int]$i) { ($c -shr (8 * $i)) -band 0xFF }
function Half([int]$x, [int]$y) { [int][Math]::Floor(($x + $y) / 2) }      # integer division, as in the plugin (C++)
function Blend([int64]$a, [int64]$b) { (Half (Channel $a 0) (Channel $b 0)) -bor ((Half (Channel $a 1) (Channel $b 1)) -shl 8) -bor ((Half (Channel $a 2) (Channel $b 2)) -shl 16) }
function Brightness([int64]$c) { ((Channel $c 0) * 299 + (Channel $c 1) * 587 + (Channel $c 2) * 114) / 1000 }

function Config([string]$darkMode, [string]$theme = '', [string]$darkName = '') {
    $x = Get-Content $backup -Raw -Encoding UTF8
    $x = $x -replace '(<GUIConfig name="DarkMode" enable=")(yes|no)', ('${1}' + $darkMode)
    if ($darkName -ne '') { $x = $x -replace 'darkThemeName="[^"]*"', ('darkThemeName="' + $darkName + '"') }
    if ($theme -ne '') { $x = $x -replace 'lightThemeName="[^"]*"', ('lightThemeName="' + $theme + '"') }
    [IO.File]::WriteAllText($cfg, $x, (New-Object Text.UTF8Encoding $false))
}

# Measures the .stdoer document (tab $iS) and compares with the .txt (tab $iT).
function Measure-Theme([string]$label, [int]$iS, [int]$iT) {
    Npp-Activate $iS; Start-Sleep -Milliseconds 500
    [void](Sci 4003 0 -1); [void](Sci 2025 0); Start-Sleep -Milliseconds 400     # color everything; cursor at the start
    $text = SciText
    $bytes = [Text.Encoding]::UTF8.GetByteCount($text)
    $used = @{}
    for ($i = 0; $i -lt $bytes; $i++) { $used[[int](Sci 2010 $i)] = $true }
    $db = Sci 2482 32; $df = Sci 2481 32                                           # background and text of the default style
    $wrong = @()
    foreach ($e in ($used.Keys | Sort-Object)) {
        if ($e -eq 50) { continue }                                                # the hidden path is not drawn
        $b = Sci 2482 $e; $f = Sci 2481 $e
        if ($b -ne $db) { $wrong += "style ${e}: background $(Hex $b) != theme $(Hex $db)" }
        if ($e -ne 51 -and $f -ne $df) { $wrong += "style ${e}: text $(Hex $f) != theme $(Hex $df)" }
        if ((Sci 2487 $e) -ne 0) { $wrong += "style ${e}: with end-of-line fill" }
    }
    Verdict "$label | background and text of the $($used.Count) used styles = theme (background $(Hex $db), text $(Hex $df))" ($wrong.Count -eq 0) ($wrong -join '; ')
    # visible path (51): midpoint between text and background (forced to show with the cursor on the path)
    $pathStart = [Text.Encoding]::UTF8.GetByteCount($text.Substring(0, $text.IndexOf('text.txt')))
    [void](Sci 2025 $pathStart); Start-Sleep -Milliseconds 400
    $f51 = Sci 2481 51; $exp = Blend $df $db
    Verdict "$label | visible path (51) = midpoint text/background ($(Hex $exp)) and shown there (style $(Sci 2010 $pathStart))" (($f51 -eq $exp) -and ((Sci 2010 $pathStart) -eq 51)) "51=$(Hex $f51)"
    $hot = Sci 2494 0    # SCI_GETHOTSPOTACTIVEFORE
    $light = (Brightness $db) -ge 128
    $contrast = [Math]::Abs((Brightness $hot) - (Brightness $db))
    Verdict "$label | color on mouse hover $(Hex $hot) contrasts with the background (difference $([int]$contrast) of 255)" ($contrast -ge 60 -and ((Sci 2493 52) -eq 1)) ''
    # the .txt in the same window
    Npp-Activate $iT; Start-Sleep -Milliseconds 400
    $b0t = Sci 2482 0; $f0t = Sci 2481 0
    Npp-Activate $iS; Start-Sleep -Milliseconds 400
    Verdict "$label | style 0 of the .stdoer ($(Hex (Sci 2482 0))/$(Hex (Sci 2481 0))) = that of the .txt ($(Hex $b0t)/$(Hex $f0t))" (((Sci 2482 0) -eq $b0t) -and ((Sci 2481 0) -eq $f0t)) ''
}

function Open-Docs([string]$label) {
    Npp-Open @($docS, $docT)
    $iS = (Npp-Documents | Where-Object { $_.Path -eq $docS }).Index
    $iT = (Npp-Documents | Where-Object { $_.Path -eq $docT }).Index
    return @($iS, $iT)
}

try {
    Write-Host '=== Part A: start with different configurations ==='
    $variants = @(
        @{ n = 'default theme (light)';              mode = 'no';  theme = '' },
        @{ n = 'dark mode (Deep Black)';             mode = 'yes'; theme = ''; dark = 'Deep Black.xml' },
        @{ n = 'dark mode (DarkModeDefault)';        mode = 'yes'; theme = ''; dark = 'DarkModeDefault.xml' },
        @{ n = 'dark theme Zenburn (no dark mode)';  mode = 'no';  theme = 'Zenburn.xml' },
        @{ n = 'dark theme Monokai';                 mode = 'no';  theme = 'Monokai.xml' },
        @{ n = 'dark theme Obsidian';                mode = 'no';  theme = 'Obsidian.xml' },
        @{ n = 'light theme with a colored background: Solarized-light'; mode = 'no'; theme = 'Solarized-light.xml' },
        @{ n = 'theme with odd colors: Hello Kitty'; mode = 'no';  theme = 'Hello Kitty.xml' }
    )
    foreach ($v in $variants) {
        Write-Host "--- $($v.n)"
        Config $v.mode $v.theme $v.dark
        $ix = Open-Docs $v.n
        Measure-Theme $v.n $ix[0] $ix[1]
        Npp-Close
    }

    Write-Host '=== Part B: hot theme change (Style Configurator) ==='
    Config 'no' ''
    $ix = Open-Docs 'hot'
    Measure-Theme 'start (default)' $ix[0] $ix[1]
    [void](NppMsg $NPPM_MENUCOMMAND 0 46001)       # Settings > Style Configurator
    $dlg = [IntPtr]::Zero
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 150; $dlg = [NppT]::WindowWithTitle([uint32]$script:ProcNpp.Id, 'Style Configurator'); if ($dlg -ne [IntPtr]::Zero) { break } }
    if ($dlg -eq [IntPtr]::Zero) { throw 'The Style Configurator did not appear' }
    $combo = [NppT]::GetDlgItem($dlg, 2307)
    function Pick-Theme([string]$name) {
        $idx = [int][NppT]::SendMessageStr($combo, 0x014C, [IntPtr](-1), $name)      # CB_FINDSTRING
        if ($idx -lt 0) { throw "There is no theme '$name' in the Configurator" }
        [void][NppT]::SendMessage($combo, 0x014E, [IntPtr]$idx, [IntPtr]::Zero)         # CB_SETCURSEL
        [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr](2307 + (1 -shl 16)), $combo)   # WM_COMMAND, CBN_SELCHANGE
        Start-Sleep -Milliseconds 1200
    }
    foreach ($t in 'Zenburn', 'Obsidian', 'Default', 'Solarized-light', 'Hello Kitty', 'Black board', 'Default') {
        Pick-Theme $t
        Measure-Theme "hot -> $t" $ix[0] $ix[1]
    }
    # Cancel the Configurator (leaves the theme as it was)
    [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr]2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800
    Npp-Close

    Write-Host '=== Part C: hot dark / light mode (Preferences) ==='
    Config 'no' ''
    $ix = Open-Docs 'hot mode'
    Measure-Theme 'start (light)' $ix[0] $ix[1]
    [void](NppMsg $NPPM_MENUCOMMAND 0 48011)       # Settings > Preferences
    $pref = [IntPtr]::Zero
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 150; $pref = [NppT]::WindowWithTitle([uint32]$script:ProcNpp.Id, 'Preferences'); if ($pref -ne [IntPtr]::Zero) { break } }
    if ($pref -eq [IntPtr]::Zero) { throw 'Preferences did not appear' }
    $rLight = [NppT]::ChildById($pref, 7131); $rDark = [NppT]::ChildById($pref, 7132)
    if ($rLight -eq [IntPtr]::Zero -or $rDark -eq [IntPtr]::Zero) { throw 'The Light mode / Dark mode buttons were not found' }
    foreach ($step in 'dark', 'light', 'dark', 'light') {
        $button = if ($step -eq 'dark') { $rDark } else { $rLight }
        [void][NppT]::SendMessage($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)      # BM_CLICK
        Start-Sleep -Milliseconds 1800
        Measure-Theme "$step mode hot" $ix[0] $ix[1]
    }
    [void][NppT]::SendMessage($pref, 0x0111, [IntPtr]6001, [NppT]::GetDlgItem($pref, 6001))    # Close
    Start-Sleep -Milliseconds 600
    Npp-Close
}
finally {
    Copy-Item $backup $cfg -Force      # the portable copy's original configuration, always
}
Write-Host "SUMMARY: $bad failures"
if ($bad -gt 0) { exit 1 }
