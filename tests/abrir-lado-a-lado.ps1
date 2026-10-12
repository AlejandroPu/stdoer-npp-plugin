# Abre el Notepad++ portátil con un .py y su copia .stdoer lado a lado (.py a la
# izquierda, .stdoer a la derecha) y lo deja abierto para probar a mano.
#
# Uso (desde la carpeta stdoer):
#   .\tests\abrir-lado-a-lado.ps1                      # copias personales en pruebas\
#   .\tests\abrir-lado-a-lado.ps1 -Base build\cmp\01_blancos
#
# -Base es la ruta SIN extensión; deben existir <Base>.py y <Base>.stdoer.
# Solo usa el portátil (-multiInst -nosession). No modifica ningún documento.

param([string]$Base = 'pruebas\muestra-personal')

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $raiz 'npp-portable\notepad++.exe'
$py = Join-Path $raiz ($Base + '.py'); $st = Join-Path $raiz ($Base + '.stdoer')
foreach ($f in $py, $st) { if (-not (Test-Path $f)) { throw "No existe $f" } }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinLado {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@
function Send($h, $m, [int64]$w = 0, [int64]$l = 0) { [int64][WinLado]::SendMessage($h, [uint32]$m, [IntPtr]$w, [IntPtr]$l) }
$NPPMSG = 0x400 + 1000
$NPPM_GETNBOPENFILES = $NPPMSG + 7
$NPPM_ACTIVATEDOC    = $NPPMSG + 28
$NPPM_MENUCOMMAND    = $NPPMSG + 48
$IDM_VIEW_GOTO_ANOTHER_VIEW = 10001

$p = Start-Process $exe -ArgumentList @('-multiInst', '-nosession', ('"' + $py + '"'), ('"' + $st + '"')) -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'No apareció la ventana de Notepad++ portátil' }
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; if ((Send $h $NPPM_GETNBOPENFILES 0 0) -ge 2) { break } }
Start-Sleep -Seconds 2

# El último archivo abierto (.stdoer) es el que queda activo; se mueve a la otra vista.
$n = Send $h $NPPM_GETNBOPENFILES 0 0
[void](Send $h $NPPM_ACTIVATEDOC 0 ($n - 1))
Start-Sleep -Milliseconds 300
[void](Send $h $NPPM_MENUCOMMAND 0 $IDM_VIEW_GOTO_ANOTHER_VIEW)
Start-Sleep -Milliseconds 500
Write-Host "Abierto: $py  (izquierda)  y  $st  (derecha). Cierra el portátil cuando termines."
