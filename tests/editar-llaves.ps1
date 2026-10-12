# Prueba de EDICIÓN de la contracción con { }: sin forzar el coloreado, se borra/teclea
# una llave en una copia (en memoria, sin guardar) y se comprueba que el plegado de TODAS
# las líneas, también las anteriores al cambio, queda como corresponde.
#
# Uso (desde la carpeta stdoer):   .\tests\editar-llaves.ps1
# Solo usa el Notepad++ portátil. Trabaja sobre build\editar\L01_basico.stdoer y no guarda.

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $raiz 'npp-portable\notepad++.exe'
$work = Join-Path $raiz 'build\editar'
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
$doc = Join-Path $work 'L01_basico.stdoer'
Copy-Item (Join-Path $raiz 'tests\llaves\L01_basico.stdoer') $doc
$p = Start-Process $exe -ArgumentList @('-multiInst', '-nosession', ('"' + $doc + '"')) -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'No apareció la ventana' }
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; if ((Send $h $NPPM_GETNBOPENFILES) -ge 1) { break } }
Start-Sleep -Seconds 2
$vista = ([WinE]::Scintillas($h))[0]
function Niveles {
    Start-Sleep -Milliseconds 1500
    $o = @(); $n = Send $vista $SCI_GETLINECOUNT
    for ($k = 0; $k -lt $n; $k++) { $v = [int](Send $vista $SCI_GETFOLDLEVEL $k); $s = [string](($v -band 0xFFF) - 1024); if ($v -band 0x2000) { $s += 'H' }; $o += $s }
    $o -join ' '
}
$mal = 0
function Comprobar($nombre, $esperado) {
    $obt = Niveles
    $ok = ($obt -eq $esperado); if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-52} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  esperado=[$esperado] obtenido=[$obt]" }))
}
# Texto: "Titulo {\nuno\ndos\n}\nfuera\n"  -> "}" en la posición 17; fin de "uno" en 12.
Comprobar 'inicial (sin editar)' '0H 1 1 0 0 0'
[void](Send $vista $SCI_DELETERANGE 17 1)
Comprobar 'borrar la "}" -> "{" queda sin pareja y se ignora' '0 0 0 0 0 0'
[void](Send $vista $SCI_UNDO)
Comprobar 'deshacer -> vuelve la región' '0H 1 1 0 0 0'
[void](Send $vista $SCI_GOTOPOS 12); [void](Send $vista $WM_CHAR ([int][char]'{') 0)
Comprobar 'teclear "{" al final de "uno" (la "}" casa con esa)' '0 0H 1 0 0 0'
[void](Send $vista $SCI_UNDO)
Comprobar 'deshacer -> vuelve la región original' '0H 1 1 0 0 0'
[void](Send $vista $SCI_GOTOPOS 12); [void](Send $vista $WM_CHAR ([int][char]'}') 0)
Comprobar '"}" tecleada al final de "uno" (no es primer carácter)' '0H 1 1 0 0 0'
Write-Host "RESUMEN: $mal fallos"
# El documento quedó modificado (es una copia en build\editar, nunca se guarda): se termina el proceso
# propio en vez de pedir el cierre normal, que abriría un aviso de guardar.
Stop-Process -Id $p.Id -Force
if ($mal -gt 0) { exit 1 }
