# Verifica la contracción con { } del lexer stdoer: abre en el Notepad++ portátil cada
# tests\llaves\*.stdoer, fuerza el coloreado completo y compara el nivel de plegado
# (SCI_GETFOLDLEVEL) de CADA línea con tests\llaves\<caso>.esperado.
#
# Uso (desde la carpeta stdoer):   .\tests\verificar-llaves.ps1
#
# Formato de .esperado (una línea de texto, un token por línea del documento):
#   <profundidad>[H]     profundidad = nivel - 1024; H = cabecera de pliegue (se puede contraer).
# Los esperados están razonados a mano a partir de las reglas (src\Llaves.h), no sacados de
# la salida del programa. Un documento sin llaves con pareja conserva los niveles de Python
# (en un documento sin sangría, todos 0).
#
# - Usa SOLO el Notepad++ portátil (npp-portable), con -multiInst -nosession.
# - No se modifica ningún documento (se trabaja sobre copias en build\llaves\).

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $raiz 'npp-portable\notepad++.exe'
$work = Join-Path $raiz 'build\llaves'

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
$casos = @(Get-ChildItem (Join-Path $raiz 'tests\llaves') -Filter *.stdoer | Sort-Object Name)
$archivos = @()
foreach ($f in $casos) {
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $copia = Join-Path $work $f.Name
    Copy-Item $f.FullName $copia
    $esp = (Get-Content (Join-Path $raiz "tests\llaves\$base.esperado") -Raw).Trim()
    $archivos += [pscustomobject]@{ Base = $base; Ruta = $copia; Esperado = $esp }
}

$argsNpp = @('-multiInst', '-nosession') + ($archivos | ForEach-Object { '"' + $_.Ruta + '"' })
$p = Start-Process $exe -ArgumentList $argsNpp -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'No apareció la ventana de Notepad++ portátil' }

$esperados = $archivos.Count; $n = 0
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; $n = Send $h $NPPM_GETNBOPENFILES 0 0; if ($n -ge $esperados) { break } }
Start-Sleep -Seconds 2
Write-Host "Documentos abiertos: $n (esperados $esperados)"
if ($n -lt $esperados) { throw 'No se abrieron todos los archivos' }

$sci = [WinL]::Scintillas($h)
if ($sci.Count -lt 1) { throw 'No se encontró el Scintilla principal' }
$vista = $sci[0]

# Emparejar pestañas con archivos por longitud (puede haber una pestaña vacía extra).
$longitudes = @()
for ($i = 0; $i -lt $n; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 $i); Start-Sleep -Milliseconds 80
    $longitudes += (Send $vista $SCI_GETLENGTH)
}
$desp = -1
for ($d = 0; $d -le ($n - $esperados); $d++) {
    $coincide = $true
    for ($i = 0; $i -lt $esperados; $i++) { if ($longitudes[$i + $d] -ne (Get-Item $archivos[$i].Ruta).Length) { $coincide = $false; break } }
    if ($coincide) { $desp = $d; break }
}
if ($desp -lt 0) { throw 'No se pudo emparejar las pestañas con los archivos por longitud' }

function Fmt([int]$v) {
    $s = [string](($v -band 0xFFF) - 1024)
    if ($v -band 0x2000) { $s += 'H' }
    $s
}
$ok = 0; $mal = 0
$reporte = New-Object 'System.Collections.Generic.List[string]'
$reporte.Add("Verificación de llaves — " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
for ($i = 0; $i -lt $esperados; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 ($i + $desp)); Start-Sleep -Milliseconds 80
    [void](Send $vista $SCI_COLOURISE 0 -1)
    $a = $archivos[$i]
    $lang = Send $h $NPPM_GETBUFFERLANGTYPE (Send $h $NPPM_GETCURRENTBUFFERID) 0
    $lineas = Send $vista $SCI_GETLINECOUNT
    $obt = @(); for ($k = 0; $k -lt $lineas; $k++) { $obt += (Fmt ([int](Send $vista $SCI_GETFOLDLEVEL $k))) }
    $obtenido = $obt -join ' '
    $bien = ($obtenido -eq $a.Esperado) -and ($lang -eq 95)
    $estado = if ($bien) { 'OK' } else { 'MAL' }
    $linea = "{0,-36} {1}" -f $a.Base, $estado
    Write-Host $linea
    $reporte.Add($linea)
    if ($bien) { $ok++ } else {
        $mal++
        $reporte.Add("   lenguaje=$lang (esperado 95)")
        $reporte.Add("   esperado: $($a.Esperado)")
        $reporte.Add("   obtenido: $obtenido")
        Write-Host "   esperado: $($a.Esperado)"; Write-Host "   obtenido: $obtenido"
    }
}
$reporte.Add("RESUMEN: $ok bien, $mal mal, de $esperados casos")
$reporte | Set-Content -Encoding utf8 (Join-Path $work 'reporte.txt')
Write-Host "RESUMEN: $ok bien, $mal mal, de $esperados casos"

[void]$p.CloseMainWindow(); Start-Sleep -Seconds 2
if (-not $p.HasExited) { Write-Host 'El portátil sigue abierto; ciérralo a mano.' }
if ($mal -gt 0) { exit 1 }
