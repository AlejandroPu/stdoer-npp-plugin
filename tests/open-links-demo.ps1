# Generates samples\links-demo.stdoer (with absolute paths to the files in tests\targets\,
# computed here: what is versioned carries nobody's paths) and opens the portable Notepad++ with
# it on the left and the braces demo (samples\braces-demo.stdoer) on the right.
# The clicks DO open for real (tabs, Explorer, Windows' program for .ods).
#
# Usage (from the stdoer folder):   .\tests\open-links-demo.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$obj = Join-Path $root 'tests\targets'
$samples = Join-Path $root 'samples'
if (-not (Test-Path $samples)) { New-Item -ItemType Directory $samples | Out-Null }

$demo = @"
Links demo (stdoer 0.6.0)
All of this is made up: the links point to test files inside the plugin's folder.
Hover the mouse over a link (tooltip with the path) and click on "link[]" to open it.
RIGHT click on a link: menu with Open, Open containing folder and Disable link
(on a disabled one, Enable link). Ctrl+Z undoes each change in a single step.

1. Text: opens in a Notepad++ tab
   __link[$obj\text.txt]
2. Spreadsheet (.ods): with the program Windows has assigned (if there is none, its folder is shown)
   __link[$obj\sheet.ods]
3. Folder: opens in Explorer
   __link[$obj\folder]
4. Executable (.exe): NEVER run; its folder is shown in Explorer
   __link[$obj\harmless.exe]
5. Broken link (the file does not exist): the tooltip says so and the click does nothing
   __link[$obj\does-not-exist.txt]
6. Disabled link (a single _ ): shown in full and does nothing
   _link[$obj\text.txt]
7. Path with brackets in the name: the last ] is the one that closes
   __link[$obj\file [1].txt]
8. Relative path: not opened (only full paths)
   __link[tests\targets\text.txt]
9. No extension: only its folder is shown
   __link[$obj\noextension]
10. Several links on one line: __link[$obj\text.txt] and __link[$obj\folder]
11. Network path that does not respond (it may take up to a second, never more): the tooltip says there was no response
   __link[\\10.255.255.1\share\x.txt]
12. A link inside a { } region (when folded, the closing brace is hidden too) {
   Text of the region.
   __link[$obj\text.txt]
}
13. Web address (opens in the browser; the tooltip shows the address without touching the network)
   __link[https://notepad-plus-plus.org/]
14. Another web address, with http
   __link[http://example.com/]
15. Scheme NOT allowed (only http and https are opened): the tooltip says so and the click does nothing
   __link[javascript:alert(1)]
16. Another scheme that is not allowed (a Windows program's protocol)
   __link[ms-settings:network]

To edit a path: delete one _ (it becomes _link[...] and the path is shown), edit it and type the _ again.
With the cursor inside the brackets, or with a selection that touches the link, the path is shown by itself.
At the end of this file there is a line with a { that never closes: it hides nothing. {
End.
"@
$demoLf = $demo -replace "`r`n", "`n"
$file = Join-Path $samples 'links-demo.stdoer'
[IO.File]::WriteAllText($file, $demoLf, (New-Object Text.UTF8Encoding $false))

$braces = Join-Path $samples 'braces-demo.stdoer'
Copy-Item (Join-Path $root 'tests\braces\L23_demo.stdoer') $braces -Force

& (Join-Path $PSScriptRoot 'open-side-by-side.ps1') -Left 'samples\links-demo.stdoer' -Right 'samples\braces-demo.stdoer'
