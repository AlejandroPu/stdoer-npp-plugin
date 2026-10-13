# Compara, línea por línea, el nivel de plegado (SCI_GETFOLDLEVEL) que da Notepad++ al
# mismo texto abierto como Python (.py) y como Stdoer (.stdoer). Es la prueba objetiva
# de la contracción por sangría: debe dar IDÉNTICO.
#
# Uso (desde la carpeta stdoer):   .\tests\comparar-plegado.ps1
#
# - Usa SOLO el Notepad++ portátil (npp-portable), con -multiInst -nosession.
# - Casos: tests\casos\*.py (inventados) y, si existen, pruebas\*.py (copias personales,
#   fuera del git). De cada .py se hace una copia idéntica .stdoer en build\cmp\.
# - Mensajes a Notepad++/Scintilla: solo con argumentos numéricos (funcionan entre
#   procesos). No se modifica ningún documento.

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $raiz 'npp-portable\notepad++.exe'
$work = Join-Path $raiz 'build\cmp'

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

# --- preparar los pares .py / .stdoer ---
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$fuentes = @(Get-ChildItem (Join-Path $raiz 'tests\casos') -Filter *.py | Sort-Object Name)
$personal = Join-Path $raiz 'pruebas'
if (Test-Path $personal) { $fuentes += @(Get-ChildItem $personal -Filter *.py | Sort-Object Name) }
$archivos = @()
foreach ($f in $fuentes) {
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $py = Join-Path $work ($base + '.py'); $st = Join-Path $work ($base + '.stdoer')
    Copy-Item $f.FullName $py; Copy-Item $f.FullName $st
    $archivos += [pscustomobject]@{ Base = $base; Py = $py; St = $st; Bytes = (Get-Item $py).Length; Personal = ($f.DirectoryName -eq $personal) }
}
$lista = @(); foreach ($a in $archivos) { $lista += $a.Py; $lista += $a.St }

# --- abrir el portátil con todos los archivos ---
$argsNpp = @('-multiInst', '-nosession') + ($lista | ForEach-Object { '"' + $_ + '"' })
$p = Start-Process $exe -ArgumentList $argsNpp -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
if ($h -eq [IntPtr]::Zero) { throw 'No apareció la ventana de Notepad++ portátil' }

$esperados = $lista.Count; $n = 0
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; $n = Send $h $NPPM_GETNBOPENFILES 0 0; if ($n -ge $esperados) { break } }
Start-Sleep -Seconds 2
Write-Host "Documentos abiertos: $n (esperados $esperados)"
if ($n -lt $esperados) { throw 'No se abrieron todos los archivos' }

$sci = [Win]::Scintillas($h)
if ($sci.Count -lt 1) { throw 'No se encontró el Scintilla principal' }
$vista = $sci[0]

# Notepad++ puede dejar una pestaña vacía "new 1" además de los archivos. Se recorren
# todas las pestañas y se busca el desplazamiento para el que la longitud en bytes de
# cada pestaña (SCI_GETLENGTH) coincide con la del archivo correspondiente.
$longitudes = @()
for ($i = 0; $i -lt $n; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 $i)
    Start-Sleep -Milliseconds 80
    $longitudes += (Send $vista $SCI_GETLENGTH)
}
$desp = -1
for ($d = 0; $d -le ($n - $esperados); $d++) {
    $coincide = $true
    for ($i = 0; $i -lt $esperados; $i++) { if ($longitudes[$i + $d] -ne (Get-Item $lista[$i]).Length) { $coincide = $false; break } }
    if ($coincide) { $desp = $d; break }
}
if ($desp -lt 0) { throw 'No se pudo emparejar las pestañas con los archivos por longitud' }
Write-Host "Pestañas extra antes de los archivos: $desp"

$resultados = @{}
$problemas = @()
for ($i = 0; $i -lt $esperados; $i++) {
    [void](Send $h $NPPM_ACTIVATEDOC 0 ($i + $desp))
    Start-Sleep -Milliseconds 80
    [void](Send $vista $SCI_COLOURISE 0 -1)
    $archivo = $lista[$i]
    $lang = Send $h $NPPM_GETBUFFERLANGTYPE (Send $h $NPPM_GETCURRENTBUFFERID) 0
    $lineas = Send $vista $SCI_GETLINECOUNT
    $niveles = New-Object 'System.Collections.Generic.List[int]'
    for ($k = 0; $k -lt $lineas; $k++) { $niveles.Add([int](Send $vista $SCI_GETFOLDLEVEL $k)) }
    $resultados[$archivo] = [pscustomobject]@{ Lang = $lang; Niveles = $niveles }
}
# --- comparar ---
function Fmt([int]$v) {
    $base = $v -band 0x3FF
    $s = "$base"
    if ($v -band 0x2000) { $s += 'H' }
    if ($v -band 0x1000) { $s += 'b' }
    $s
}
$ok = 0; $dif = 0
$reporte = New-Object 'System.Collections.Generic.List[string]'
$reporte.Add("Comparación de plegado .py vs .stdoer — " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$reporte.Add('Niveles: número = nivel; H = cabecera de pliegue; b = línea en blanco (bandera).')
foreach ($a in $archivos) {
    $r1 = $resultados[$a.Py]; $r2 = $resultados[$a.St]
    $mismo = ($r1.Niveles.Count -eq $r2.Niveles.Count)
    $diffs = @()
    if ($mismo) { for ($k = 0; $k -lt $r1.Niveles.Count; $k++) { if ($r1.Niveles[$k] -ne $r2.Niveles[$k]) { $diffs += $k } } }
    $identico = $mismo -and ($diffs.Count -eq 0)
    $total = $r1.Niveles.Count
    $estado = if ($identico) { 'IDENTICO' } else { 'DIFERENTE' }
    $linea = "{0,-34} lenguaje py={1} stdoer={2}  líneas={3}  {4}" -f $a.Base, $r1.Lang, $r2.Lang, $total, $estado
    Write-Host $linea
    $reporte.Add($linea)
    if ($identico) { $ok++ } else {
        $dif++
        if (-not $mismo) { $reporte.Add("   distinto número de líneas: py=$($r1.Niveles.Count) stdoer=$($r2.Niveles.Count)") }
        foreach ($k in $diffs) { $reporte.Add("   línea $($k+1): py=$(Fmt $r1.Niveles[$k])  stdoer=$(Fmt $r2.Niveles[$k])") }
    }
    if (-not $a.Personal) {   # detalle solo de los casos inventados (las copias personales no se vuelcan)
        $reporte.Add('   py     : ' + (($r1.Niveles | ForEach-Object { Fmt $_ }) -join ' '))
        $reporte.Add('   stdoer : ' + (($r2.Niveles | ForEach-Object { Fmt $_ }) -join ' '))
    }
}
$reporte.Add("RESUMEN: $ok idénticos, $dif diferentes, de $($archivos.Count) pares")
foreach ($m in $problemas) { $reporte.Add("AVISO: $m"); Write-Host "AVISO: $m" }
$reporte | Set-Content -Encoding utf8 (Join-Path $work 'reporte.txt')
Write-Host "RESUMEN: $ok idénticos, $dif diferentes, de $($archivos.Count) pares"
Write-Host "Reporte: $(Join-Path $work 'reporte.txt')"

# --- cerrar (cierre normal; no hay nada modificado) ---
[void]$p.CloseMainWindow(); Start-Sleep -Seconds 2
if (-not $p.HasExited) { Write-Host 'El portátil sigue abierto; ciérralo a mano.' }
if ($dif -gt 0 -or $problemas.Count -gt 0) { exit 1 }
