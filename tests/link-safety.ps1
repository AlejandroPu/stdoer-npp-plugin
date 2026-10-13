# Pruebas de SEGURIDAD del texto oculto de los enlaces (diseño: "Seguridad del contenido").
#
# Criterio: ninguna acción común puede borrar o cambiar la ruta oculta sin que se vea. Si
# falla, lo aceptable es que el enlace quede visible; nunca que el texto cambie a escondidas.
#
# Uso (desde la carpeta stdoer):   .\tests\seguridad-enlaces.ps1  [-SinPortapapeles]
#
# Documento de prueba (inventado):   antes __link[SECRETO-123] despues
# Cada escenario: se prepara el cursor/selección, se anota si la ruta estaba MOSTRADA, se
# hace la acción (con los mismos comandos que las teclas: Retroceso, Suprimir, escribir...),
# y se juzga el resultado:
#   OK intacta     la ruta sigue igual
#   OK deshecho    ya no queda ningún enlace (todo el texto quedó a la vista o se borró entero)
#   OK visto       la ruta cambió, pero estaba mostrada cuando se hizo la acción
#   OK expuesto    la ruta cambió por una vía que no se ve (Reemplazar todo) y el plugin la dejó
#                  a la vista y/o puso un aviso (anotación bajo el enlace)
#   FALLA          la ruta cambió estando oculta
# Y se comprueba que Deshacer devuelve el texto original y Rehacer el resultado.
# Las acciones con el portapapeles lo pisan: se guarda y restaura el contenido si es texto
# (si no lo es, esas pruebas se omiten). Se trabaja en el portátil, sin guardar nada.

param([switch]$SinPortapapeles)
$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$work = Join-Path $Raiz 'build\seguridad'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$archivo = Join-Path $work 'S01.stdoer'
$D0 = "antes __link[SECRETO-123] despues`nfin`n"
$ORIG = 'SECRETO-123'
[IO.File]::WriteAllText($archivo, $D0, (New-Object Text.UTF8Encoding $false))

Npp-Abrir @($archivo) -Log (Join-Path $work 'stdoer.log')
$doc = Npp-Documentos | Where-Object { $_.Ruta -eq $archivo }
Npp-Activar $doc.Indice

$SCI_SETTEXT = 2181; $SCI_EMPTYUNDOBUFFER = 2175; $SCI_COLOURISE = 4003; $SCI_GOTOPOS = 2025
$SCI_SETSEL = 2160; $SCI_UNDO = 2176; $SCI_REDO = 2011; $SCI_DELETEBACK = 2326; $SCI_CLEAR = 2180
$SCI_CHARRIGHT = 2306; $SCI_CHARLEFT = 2304; $SCI_GETCURRENTPOS = 2008; $SCI_CUT = 2177
$SCI_COPY = 2178; $SCI_PASTE = 2179; $SCI_REPLACESEL = 2170; $SCI_SETTARGETRANGE = 2686
$SCI_SEARCHINTARGET = 2197; $SCI_REPLACETARGET = 2194; $SCI_GETLENGTH = 2006; $SCI_SETTARGETSTART = 2190; $SCI_SETTARGETEND = 2192
$WM_CHAR = 0x102

function Reiniciar {
    [void](SciCadena $SCI_SETTEXT 0 $D0)
    [void](Sci $SCI_EMPTYUNDOBUFFER)
    [void](Sci $SCI_COLOURISE 0 -1)
    [void](Sci $SCI_GOTOPOS 0)
    Start-Sleep -Milliseconds 30
}
function Ruta-Mostrada { (SciMapaEstilos (SciTexto)) -match 'r' }
function Enlaces-Del([string]$texto) { [regex]::Matches($texto, '__link\[([^\]]*)\]') | ForEach-Object { $_.Groups[1].Value } }

# Juzga el resultado de una acción.
function Juzgar([string]$antes, [bool]$mostrada, [string]$despues, [string]$mapaDespues, [bool]$avisoActivo) {
    if ($despues -eq $antes) { return 'OK igual' }
    $rutas = @(Enlaces-Del $despues)
    if ($rutas -contains $ORIG) { return 'OK intacta' }
    if ($rutas.Count -eq 0) { return 'OK deshecho' }
    if ($mostrada) { return 'OK visto' }
    if ($avisoActivo -or ($mapaDespues -match 'r' -and $mapaDespues -notmatch 'h')) { return 'OK expuesto' }
    return 'FALLA'
}

$resultados = New-Object 'System.Collections.Generic.List[object]'
$fallos = 0; $falloUndo = 0
function Escenario([string]$grupo, [string]$nombre, [scriptblock]$preparar, [scriptblock]$accion) {
    if ($grupo -like 'reemplaz*') { Write-Host ("  " + (Get-Date -Format 'HH:mm:ss') + " ... $nombre") }
    Reiniciar
    & $preparar
    Start-Sleep -Milliseconds 40
    $antes = SciTexto
    $mostrada = Ruta-Mostrada
    $script:mostradaAlCambiar = $null
    & $accion
    Start-Sleep -Milliseconds 40
    if ($script:mostradaAlCambiar -ne $null) { $mostrada = $script:mostradaAlCambiar }
    $despues = SciTexto
    $v = Juzgar $antes $mostrada $despues (SciMapaEstilos $despues) ((Sci 2546 0) -gt 0)   # SCI_ANNOTATIONGETLINES de la línea 0: aviso del plugin
    # Deshacer / rehacer
    $undoOk = $true; $redoOk = $true
    if ($despues -ne $antes) {
        for ($i = 0; $i -lt 6 -and (SciTexto) -ne $antes; $i++) { [void](Sci $SCI_UNDO) }
        $undoOk = ((SciTexto) -eq $antes)
        for ($i = 0; $i -lt 6 -and (SciTexto) -ne $despues; $i++) { [void](Sci $SCI_REDO) }
        $redoOk = ((SciTexto) -eq $despues)
    }
    if ($v -eq 'FALLA') { $script:fallos++ }
    if (-not $undoOk -or -not $redoOk) { $script:falloUndo++ }
    $resultados.Add([pscustomobject]@{ Grupo = $grupo; Nombre = $nombre; Veredicto = $v; Mostrada = $mostrada; Undo = $undoOk; Redo = $redoOk; Despues = ($despues -replace "`n", '\n') })
}

# ---------- 1) mover el cursor con las flechas a través del enlace ----------
Reiniciar
$malCursor = @()
[void](Sci $SCI_GOTOPOS 3)
for ($i = 0; $i -lt 30; $i++) {
    [void](Sci $SCI_CHARRIGHT); Start-Sleep -Milliseconds 20
    $pos = Sci $SCI_GETCURRENTPOS
    $esperadaMostrada = ($pos -ge 13 -and $pos -le 24)
    $m = (SciMapaEstilos (SciTexto)).Split("`n")[0]
    $hay = $m -match 'r'; $oculta = $m -match 'h'
    if ($esperadaMostrada -and (-not $hay -or $oculta)) { $malCursor += "pos $pos debía estar mostrada: $m" }
    if (-not $esperadaMostrada -and ($hay -or ($pos -ge 6 -and -not $oculta))) { $malCursor += "pos $pos debía estar oculta: $m" }
}
for ($i = 0; $i -lt 30; $i++) {
    [void](Sci $SCI_CHARLEFT); Start-Sleep -Milliseconds 20
    $pos = Sci $SCI_GETCURRENTPOS
    $esperadaMostrada = ($pos -ge 13 -and $pos -le 24)
    $m = (SciMapaEstilos (SciTexto)).Split("`n")[0]
    $hay = $m -match 'r'; $oculta = $m -match 'h'
    if ($esperadaMostrada -and (-not $hay -or $oculta)) { $malCursor += "(<-) pos $pos debía estar mostrada: $m" }
    if (-not $esperadaMostrada -and ($hay -or ($pos -ge 6 -and -not $oculta))) { $malCursor += "(<-) pos $pos debía estar oculta: $m" }
}
Write-Host ("flechas: recorrer el enlace con -> y <- (60 pasos): " + $(if ($malCursor.Count -eq 0) { 'OK (la ruta se muestra mientras el cursor la toca y se oculta fuera)' } else { 'MAL' }))
$malCursor | ForEach-Object { Write-Host "   $_" }

# ---------- 2) escribir, Retroceso y Suprimir con el cursor en cada posición ----------
foreach ($p in 3..27) {
    Escenario 'escribir'   "escribir Z con el cursor en $p"   { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $WM_CHAR ([int][char]'Z') 0) }
    Escenario 'retroceso'  "Retroceso con el cursor en $p"    { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $SCI_DELETEBACK) }
    Escenario 'suprimir'   "Suprimir con el cursor en $p"     { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $SCI_CLEAR) }
}

# ---------- 3) selecciones: escribir encima y suprimir ----------
$puntos = 4, 6, 8, 12, 13, 15, 20, 24, 25, 27
foreach ($a in $puntos) { foreach ($b in $puntos) { if ($b -gt $a) {
    Escenario 'sel-escribir' "escribir Z sobre la selección $a..$b" { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $WM_CHAR ([int][char]'Z') 0) }
    Escenario 'sel-suprimir' "Suprimir la selección $a..$b"        { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_CLEAR) }
    Escenario 'sel-retroceso' "Retroceso con la selección $a..$b"  { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_DELETEBACK) }
} } }

# ---------- 4) copiar / cortar / pegar / sobrescribir (usa el portapapeles) ----------
$sinPortapapeles = $SinPortapapeles.IsPresent
$respaldo = $null
if (-not $sinPortapapeles) {
    Add-Type -AssemblyName System.Windows.Forms
    $obj = [Windows.Forms.Clipboard]::GetDataObject()
    $formatos = if ($obj) { @($obj.GetFormats($false)) } else { @() }
    $soloTexto = ($formatos.Count -eq 0) -or (@($formatos | Where-Object { $_ -notin @('Text', 'UnicodeText', 'OEMText', 'System.String', 'Locale') }).Count -eq 0)
    if (-not $soloTexto) { Write-Host 'portapapeles: contiene datos que no son texto; se omiten las pruebas de portapapeles'; $sinPortapapeles = $true }
    elseif ($obj -and $obj.GetDataPresent([string])) { $respaldo = [Windows.Forms.Clipboard]::GetText() }
}
if (-not $sinPortapapeles) {
    foreach ($a in $puntos) { foreach ($b in $puntos) { if ($b -gt $a) {
        Escenario 'cortar' "Cortar la selección $a..$b" { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_CUT) }
    } } }
    # pegar sobre una selección y pegar con el cursor en cada posición; el texto pegado es "PEGADO"
    [Windows.Forms.Clipboard]::SetText('PEGADO')
    foreach ($a in $puntos) { foreach ($b in $puntos) { if ($b -gt $a) {
        Escenario 'pegar-sobre' "Pegar sobre la selección $a..$b" { [void](Sci $SCI_SETSEL $a $b) } { [void](Sci $SCI_PASTE) }
    } } }
    foreach ($p in 3..27) {
        Escenario 'pegar' "Pegar con el cursor en $p" { [void](Sci $SCI_GOTOPOS $p) } { [void](Sci $SCI_PASTE) }
    }
    # copiar no modifica: se comprueba que el texto no cambia y que se copia la ruta completa
    Escenario 'copiar' 'Copiar la selección 4..27' { [void](Sci $SCI_SETSEL 4 27) } { [void](Sci $SCI_COPY) }
    $copiado = [Windows.Forms.Clipboard]::GetText()
    Write-Host ("copiar: el portapapeles recibe '" + $copiado + "' " + $(if ($copiado -like '*SECRETO-123*') { '(incluye la ruta oculta, como el resto del texto)' } else { '(NO incluye la ruta)' }))
    if ($respaldo -ne $null) { [Windows.Forms.Clipboard]::SetText($respaldo) } else { [Windows.Forms.Clipboard]::Clear() }
}

# ---------- 5) buscar y reemplazar ----------
# Reemplazar (un botón): la búsqueda selecciona el hallazgo y luego se reemplaza el destino.
function Reemplazar-Uno([string]$buscar, [string]$por) {
    [void](Sci 2198 0)   # SCI_SETSEARCHFLAGS 0: el diálogo de Notepad++ deja opciones activas
    [void](Sci $SCI_SETTARGETRANGE 0 (Sci $SCI_GETLENGTH))
    $pos = SciCadena $SCI_SEARCHINTARGET ([Text.Encoding]::UTF8.GetByteCount($buscar)) $buscar
    if ($pos -ge 0) {
        $fin = $pos + [Text.Encoding]::UTF8.GetByteCount($buscar)
        [void](Sci $SCI_SETSEL $pos $fin)             # "Buscar siguiente" selecciona el hallazgo
        Start-Sleep -Milliseconds 40
        $script:mostradaAlCambiar = Ruta-Mostrada     # ¿se veía la ruta justo antes de reemplazar?
        [void](Sci $SCI_SETTARGETRANGE $pos $fin)
        [void](SciCadena $SCI_REPLACETARGET ([Text.Encoding]::UTF8.GetByteCount($por)) $por)
    }
}
Escenario 'reemplazar' 'Reemplazar (un hallazgo seleccionado) CRETO por XX' { } { Reemplazar-Uno 'CRETO' 'XX' }
Escenario 'reemplazar' 'Reemplazar el hallazgo "antes" (fuera de la ruta)'  { } { Reemplazar-Uno 'antes' 'ANTES' }
# Reemplazar todo con el diálogo REAL de Notepad++: no selecciona nada, usa SCI_REPLACETARGET y
# apaga los avisos de modificación. El plugin debe enterarse por NPPN_GLOBALMODIFIED.
Escenario 'reemplazar-todo' 'Reemplazar todo (diálogo real) CRETO por XX' { } { Npp-ReemplazarTodoDialogo 'CRETO' 'XX' }
Escenario 'reemplazar-todo' 'Reemplazar todo (diálogo real) "antes" por "ANTES" (fuera de la ruta)' { } { Npp-ReemplazarTodoDialogo 'antes' 'ANTES' }
Escenario 'reemplazar-todo' 'Reemplazar todo (diálogo real) SECRETO-123 por nada' { } { Npp-ReemplazarTodoDialogo 'SECRETO-123' '' }
# Por la vía de programación (otro plugin): sin aviso de Notepad++ no hay forma de enterarse. Se
# anota como limitación conocida; no cuenta como falla del plugin.
$limitacion = $null
Write-Host ('  ' + (Get-Date -Format 'HH:mm:ss') + ' ... REPLACETARGET directo')
Reiniciar
$antesL = SciTexto
[void](Sci 2198 0)   # SCI_SETSEARCHFLAGS 0
[void](Sci $SCI_SETTARGETRANGE 0 (Sci $SCI_GETLENGTH))
$posL = SciCadena $SCI_SEARCHINTARGET 5 'CRETO'
if ($posL -ge 0) {   # NUNCA usar -1 como posición: Scintilla se cae con un destino inválido
    [void](Sci $SCI_SETTARGETRANGE $posL ($posL + 5))
    [void](SciCadena $SCI_REPLACETARGET 2 'XX')
}
Start-Sleep -Milliseconds 100
$limitacion = 'REPLACETARGET directo (como haría otro plugin), sin aviso de Notepad++: ruta ' + $(if ($posL -lt 0) { 'no se pudo probar (la búsqueda no halló el texto)' } elseif ((SciTexto) -eq $antesL) { 'intacta' } else { 'CAMBIADA sin que se vea (limitación conocida)' })

# ---------- informe ----------
$grupos = $resultados | Group-Object Grupo
Write-Host ''
Write-Host ('{0,-16} {1,6} {2,9} {3,9} {4,9} {5,7}' -f 'grupo', 'casos', 'intacta', 'deshecho', 'visto', 'FALLA')
foreach ($g in $grupos) {
    $c = $g.Group
    Write-Host ('{0,-16} {1,6} {2,9} {3,9} {4,9} {5,7}' -f $g.Name, $c.Count,
        (@($c | Where-Object { $_.Veredicto -in 'OK intacta', 'OK igual' }).Count),
        (@($c | Where-Object { $_.Veredicto -eq 'OK deshecho' }).Count),
        (@($c | Where-Object { $_.Veredicto -in 'OK visto', 'OK expuesto' }).Count),
        (@($c | Where-Object { $_.Veredicto -eq 'FALLA' }).Count))
}
Write-Host ''
$malos = @($resultados | Where-Object { $_.Veredicto -eq 'FALLA' })
foreach ($m in $malos | Select-Object -First 40) { Write-Host ("FALLA [{0}] {1}  -> {2}" -f $m.Grupo, $m.Nombre, $m.Despues) }
$malUndo = @($resultados | Where-Object { -not $_.Undo -or -not $_.Redo })
foreach ($m in $malUndo | Select-Object -First 20) { Write-Host ("DESHACER/REHACER no coincide [{0}] {1} (undo={2} redo={3})" -f $m.Grupo, $m.Nombre, $m.Undo, $m.Redo) }
Write-Host ("nota: " + $limitacion)
Write-Host ("RESUMEN: {0} escenarios, {1} FALLAS (ruta cambiada estando oculta), {2} con Deshacer/Rehacer distinto, {3} fallos de cursor" -f $resultados.Count, $fallos, $falloUndo, $malCursor.Count)
$resultados | Export-Csv (Join-Path $work 'resultados.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('  ' + (Get-Date -Format 'HH:mm:ss') + ' ... cerrando; portatil vivo: ' + (-not $script:ProcNpp.HasExited))
Npp-Cerrar
if ($fallos -gt 0 -or $falloUndo -gt 0 -or $malCursor.Count -gt 0) { exit 1 }
