# Prueba del clic y del recuadro de los enlaces __link[ruta] en el Notepad++ portátil.
#
# Uso (desde la carpeta stdoer):   .\tests\probar-clic-enlaces.ps1
#
# Se crea un documento en build\clic\ con enlaces a archivos de tests\objetivos\ (inventados,
# dentro de stdoer). Se simulan el mouse (mover, clic izquierdo) con mensajes de Windows y se
# lee el registro de depuración del plugin (STDOER_LOG) para saber qué decidió. Con
# STDOER_SIN_SHELL el plugin NO llama a Windows (no abre programas ni el Explorador):
# solo anota lo que habría abierto. Lo que sí abre de verdad es "en Notepad++" (pestañas).
# Mide además cuánto tarda el clic en una ruta de red que no responde (debe quedar acotado).

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$work = Join-Path $Raiz 'build\clic'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Raiz 'tests\objetivos'
$doc = Join-Path $work 'enlaces.stdoer'
$lineas = @(
    "texto: __link[$obj\texto.txt]",
    "hoja: __link[$obj\hoja.ods]",
    "carpeta: __link[$obj\carpeta]",
    "ejecutable: __link[$obj\inofensivo.exe]",
    "roto: __link[$obj\no-existe.txt]",
    "desactivado: _link[$obj\texto.txt]",
    "corchetes: __link[$obj\archivo [1].txt]",
    "relativa: __link[tests\objetivos\texto.txt]",
    "sin extension: __link[$obj\sinextension]",
    "red lenta: __link[\\10.255.255.1\recurso\x.txt]",
    "Seccion {",
    "    en region: __link[$obj\texto.txt]",
    "}",
    "ruta vacia: __link[]",
    ""
)
[IO.File]::WriteAllText($doc, ($lineas -join "`n"), (New-Object Text.UTF8Encoding $false))
$log = Join-Path $work 'stdoer.log'

$mal = 0
function Veredicto([string]$nombre, [bool]$ok, [string]$detalle = '') {
    if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-64} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  $detalle" }))
}
function LogLineas { if (Test-Path $log) { @(Get-Content $log) } else { @() } }

Npp-Abrir @($doc) -Log $log -Entorno @{ STDOER_SIN_SHELL = '1' }
$d = Npp-Documentos | Where-Object { $_.Ruta -eq $doc }
Npp-Activar $d.Indice
[void](Sci 4003 0 -1)
Start-Sleep -Milliseconds 400

# posición de un texto dentro de una línea del documento
function PosDe([int]$linea, [string]$buscado, [int]$desplazamiento = 0) {
    $ini = Sci 2167 $linea            # SCI_POSITIONFROMLINE
    $txt = $lineas[$linea]
    $i = $txt.IndexOf($buscado)
    return $ini + [Text.Encoding]::UTF8.GetByteCount($txt.Substring(0, $i)) + $desplazamiento
}
function PuntoDe([int64]$pos) {
    $x = Sci 2164 0 $pos              # SCI_POINTXFROMPOSITION
    $y = Sci 2165 0 $pos              # SCI_POINTYFROMPOSITION
    return @([int]$x, [int]$y)
}
function Mover([int]$x, [int]$y) { [void][NppT]::SendMessage($script:VNpp, 0x0200, [IntPtr]0, (Npp-LParamMouse $x $y)) }
function Clic([int]$x, [int]$y, [int]$teclas = 0) {
    $lp = Npp-LParamMouse $x $y
    Mover $x $y
    [void][NppT]::SendMessage($script:VNpp, 0x0201, [IntPtr](1 -bor $teclas), $lp)   # WM_LBUTTONDOWN (+ Shift/Ctrl en $teclas)
    [void][NppT]::SendMessage($script:VNpp, 0x0202, [IntPtr]$teclas, $lp)            # WM_LBUTTONUP
}
# Clic en "link[" de la línea (en la 'l', no en los "__").
function ClicEnLinea([int]$linea, [int]$teclas = 0) {
    $p = PuntoDe (PosDe $linea 'link[' 1)
    Clic ($p[0] + 2) ($p[1] + 4) $teclas
}
$tipos = @{}   # nada
function Esperar-Log([int]$antes, [string]$patron, [int]$ms = 4000) {
    $t = [Diagnostics.Stopwatch]::StartNew()
    while ($t.ElapsedMilliseconds -lt $ms) {
        $nuevas = @(LogLineas)[$antes..9999] | Where-Object { $_ -match $patron }
        if ($nuevas) { return ($nuevas | Select-Object -First 1) }
        Start-Sleep -Milliseconds 80
    }
    return $null
}

# ---------- clics ----------
$casos = @(
    @{ n = 'clic en enlace a .txt  -> se abre en Notepad++';              l = 0;  esp = 'abrir: en Notepad\+\+ .*texto\.txt' },
    @{ n = 'clic en enlace a .ods  -> Windows (o su carpeta si no hay programa)'; l = 1; esp = 'abrir: (con Windows|carpeta contenedora de) .*hoja\.ods' },
    @{ n = 'clic en enlace a una carpeta -> la abre (Explorador)';        l = 2;  esp = 'abrir: carpeta .*carpeta' },
    @{ n = 'clic en enlace a .exe  -> NO se ejecuta: muestra su carpeta';  l = 3;  esp = 'abrir: carpeta contenedora de .*inofensivo\.exe' },
    @{ n = 'clic en enlace con ruta inexistente -> no hace nada';          l = 4;  esp = 'no existe, no se hace nada' },
    @{ n = 'clic en ruta con [ ] en el nombre -> se abre';                 l = 6;  esp = 'abrir: en Notepad\+\+ .*archivo \[1\]\.txt' },
    @{ n = 'clic en ruta relativa -> no se hace nada';                     l = 7;  esp = 'ruta no absoluta' },
    @{ n = 'clic en archivo sin extension -> solo su carpeta';             l = 8;  esp = 'abrir: carpeta contenedora de .*sinextension' },
    @{ n = 'clic en enlace dentro de una region { } -> se abre';           l = 11; esp = 'abrir: en Notepad\+\+ .*texto\.txt' }
)
foreach ($c in $casos) {
    $antes = (LogLineas).Count
    $docsAntes = NppMsg $NPPM_GETNBOPENFILES
    ClicEnLinea $c.l
    $r = Esperar-Log $antes $c.esp
    Veredicto $c.n ($r -ne $null) ("log: " + ((@(LogLineas)[$antes..9999]) -join ' || '))
    # volver al documento de enlaces para el siguiente clic
    $dd = Npp-Documentos | Where-Object { $_.Ruta -eq $doc }; Npp-Activar $dd.Indice
}
# pestañas abiertas por los clics en Notepad++: texto.txt y archivo [1].txt
$abiertas = (Npp-Documentos | Where-Object { $_.Ruta } | ForEach-Object { Split-Path -Leaf $_.Ruta })
Veredicto 'pestañas nuevas: texto.txt y archivo [1].txt' (($abiertas -contains 'texto.txt') -and ($abiertas -contains 'archivo [1].txt')) ("abiertas: " + ($abiertas -join ', '))
$dd = Npp-Documentos | Where-Object { $_.Ruta -eq $doc }; Npp-Activar $dd.Indice

# ---------- clics que no deben abrir ----------
$antes = (LogLineas).Count
ClicEnLinea 5                                          # enlace desactivado (_link[...])
Start-Sleep -Milliseconds 700
Veredicto 'clic en enlace desactivado (_link[...]) -> nada' (((@(LogLineas)[$antes..9999]) | Where-Object { $_ -match 'abrir: (en Notepad|con Windows|carpeta)' }).Count -eq 0)
$antes = (LogLineas).Count
$p = PuntoDe (PosDe 0 '__link[' 0)
Clic ($p[0] + 2) ($p[1] + 4)                           # clic sobre los "__": no es la zona clicable
Start-Sleep -Milliseconds 700
Veredicto 'clic sobre los "__" (no son zona clicable) -> nada' (((@(LogLineas)[$antes..9999]) | Where-Object { $_ -match 'abrir: (en Notepad|con Windows|carpeta)' }).Count -eq 0)
$antes = (LogLineas).Count
ClicEnLinea 0 4                                        # Shift (MK_SHIFT = 4) + clic: es seleccionar
Start-Sleep -Milliseconds 700
Veredicto 'Shift + clic en un enlace -> no abre (selecciona)' (((@(LogLineas)[$antes..9999]) | Where-Object { $_ -match 'abrir: (en Notepad|con Windows|carpeta)' }).Count -eq 0)
$antes = (LogLineas).Count
ClicEnLinea 13                                         # enlace de ruta vacía
Start-Sleep -Milliseconds 700
Veredicto 'clic en enlace de ruta vacía -> nada' (((@(LogLineas)[$antes..9999]) | Where-Object { $_ -match 'abrir: (en Notepad|con Windows|carpeta)' }).Count -eq 0)

# ---------- ruta de red que no responde: el clic no puede congelar ----------
$antes = (LogLineas).Count
$cron = [Diagnostics.Stopwatch]::StartNew()
ClicEnLinea 9
$ms = $cron.ElapsedMilliseconds
Veredicto "clic en ruta de red que no responde -> vuelve en $ms ms (límite ~1000)" ($ms -lt 2500)
$r = Esperar-Log $antes 'sin respuesta' 1500
Veredicto 'ese clic anota "sin respuesta" y no hace nada' ($r -ne $null)
# Notepad++ sigue vivo y responde
Veredicto 'Notepad++ sigue respondiendo tras el clic lento' ((Sci 2006) -gt 0)

# ---------- recuadro al pasar el mouse ----------
# El plugin recibe el aviso "mouse detenido" de Scintilla, que con mouse sintético no llega; aquí se
# le pide por NPPM_MSGTOPLUGIN (solo en modo de pruebas) que muestre el recuadro de esa posición.
function Recuadro([int]$linea, [string]$donde = '__link[') {
    [void](Sci 2201)    # SCI_CALLTIPCANCEL: como si el mouse se hubiera ido antes
    $antes = (LogLineas).Count
    $pos = PosDe $linea $donde 2
    [void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', 1, $pos)
    $r = Esperar-Log $antes 'recuadro:' 2500
    return $r
}
$r = Recuadro 0
Veredicto 'recuadro sobre enlace existente: muestra la ruta, sin avisos' (($r -match 'texto\.txt') -and ($r -notmatch 'no existe'))  $r
$r = Recuadro 4
Veredicto 'recuadro sobre enlace roto: dice que no existe' (($r -match 'no-existe\.txt') -and ($r -match 'no existe')) $r
$r = Recuadro 7
Veredicto 'recuadro sobre ruta relativa: dice que no se abre' ($r -match 'ruta relativa') $r
$r = Recuadro 13
Veredicto 'recuadro sobre ruta vacia' ($r -match 'ruta vacia') $r
$cron = [Diagnostics.Stopwatch]::StartNew()
$r = Recuadro 9
Veredicto 'recuadro sobre ruta de red que no responde: dice que no hubo respuesta' ($r -match 'sin respuesta') $r
Veredicto 'Notepad++ sigue respondiendo tras el recuadro lento' ((Sci 2006) -gt 0)
# fuera de un enlace no hay recuadro
$antes = (LogLineas).Count
[void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', 1, (PosDe 0 'texto:' 0))
Start-Sleep -Milliseconds 800
Veredicto 'recuadro fuera de un enlace: ninguno' ((@(LogLineas)[$antes..9999] | Where-Object { $_ -match 'recuadro:' }).Count -eq 0)

Write-Host "RESUMEN: $mal fallos"
Write-Host "(registro del plugin: $log)"
Npp-Cerrar
if ($mal -gt 0) { exit 1 }
