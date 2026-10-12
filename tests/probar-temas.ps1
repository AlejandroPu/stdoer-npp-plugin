# Comprueba que un documento .stdoer toma los colores del TEMA activo de Notepad++ (el defecto
# de 0.4.0: sangría y fin de línea con fondo blanco en temas oscuros). Se MIDE, no se mira:
#   - fondo de cada estilo usado por el documento == fondo del estilo por defecto del tema;
#   - color de texto de cada estilo (salvo la ruta visible) == color por defecto del tema;
#   - la ruta visible (51) == punto medio entre texto y fondo; el color al pasar el mouse
#     contrasta con el fondo; ningún estilo con relleno de fin de línea;
#   - el estilo 0 coincide con el de un .txt abierto en la misma ventana.
# Parte A: arranque con cada configuración (claro, modo oscuro, temas de los que trae Notepad++).
# Parte B: cambio de tema EN CALIENTE con el documento abierto, desde el Configurador de estilos
#          (lo que hace el usuario), con ida y vuelta entre pestañas.
# Parte C: modo oscuro / modo claro EN CALIENTE desde Preferencias (Light mode / Dark mode).
#
# Toca npp-portable\config.xml (copia portátil, NO %AppData%): guarda el original en
# build\config-original.xml y lo restaura al terminar, pase lo que pase.
#
# Uso (desde la carpeta stdoer):   .\tests\probar-temas.ps1

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$cfg = Join-Path $Raiz 'npp-portable\config.xml'
$respaldo = Join-Path $Raiz 'build\config-original.xml'
$work = Join-Path $Raiz 'build\temas'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Raiz 'tests\objetivos'
$docS = Join-Path $work 'tema.stdoer'; $docT = Join-Path $work 'tema.txt'
$contenido = @"
def f():
    x = 1  # comentario
    y = "texto"
    __link[$obj\texto.txt] y _link[x] muerto
    __link[https://notepad-plus-plus.org/]

    {
        z = 2
    }
"@ -replace "`r`n", "`n"
[IO.File]::WriteAllText($docS, $contenido + "`n", (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText($docT, "texto plano`n    con sangria`n", (New-Object Text.UTF8Encoding $false))

if (-not (Test-Path $respaldo)) { Copy-Item $cfg $respaldo }   # el original, una sola vez

$mal = 0
function Veredicto([string]$nombre, [bool]$ok, [string]$detalle = '') {
    if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-86} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  $detalle" }))
}
function Hex([int64]$c) { '{0:X2}{1:X2}{2:X2}' -f ($c -band 0xFF), (($c -shr 8) -band 0xFF), (($c -shr 16) -band 0xFF) }   # BGR de Scintilla -> RRGGBB
function Canal([int64]$c, [int]$i) { ($c -shr (8 * $i)) -band 0xFF }
function Medio([int]$x, [int]$y) { [int][Math]::Floor(($x + $y) / 2) }      # división entera, como en el plugin (C++)
function Mezcla([int64]$a, [int64]$b) { (Medio (Canal $a 0) (Canal $b 0)) -bor ((Medio (Canal $a 1) (Canal $b 1)) -shl 8) -bor ((Medio (Canal $a 2) (Canal $b 2)) -shl 16) }
function Brillo([int64]$c) { ((Canal $c 0) * 299 + (Canal $c 1) * 587 + (Canal $c 2) * 114) / 1000 }

function Config([string]$modoOscuro, [string]$tema = '', [string]$oscuroNombre = '') {
    $x = Get-Content $respaldo -Raw -Encoding UTF8
    $x = $x -replace '(<GUIConfig name="DarkMode" enable=")(yes|no)', ('${1}' + $modoOscuro)
    if ($oscuroNombre -ne '') { $x = $x -replace 'darkThemeName="[^"]*"', ('darkThemeName="' + $oscuroNombre + '"') }
    if ($tema -ne '') { $x = $x -replace 'lightThemeName="[^"]*"', ('lightThemeName="' + $tema + '"') }
    [IO.File]::WriteAllText($cfg, $x, (New-Object Text.UTF8Encoding $false))
}

# Mide el documento .stdoer (pestaña $iS) y compara con el .txt (pestaña $iT).
function Medir([string]$etiqueta, [int]$iS, [int]$iT) {
    Npp-Activar $iS; Start-Sleep -Milliseconds 500
    [void](Sci 4003 0 -1); [void](Sci 2025 0); Start-Sleep -Milliseconds 400     # colorear todo; cursor al inicio
    $texto = SciTexto
    $bytes = [Text.Encoding]::UTF8.GetByteCount($texto)
    $usados = @{}
    for ($i = 0; $i -lt $bytes; $i++) { $usados[[int](Sci 2010 $i)] = $true }
    $db = Sci 2482 32; $df = Sci 2481 32                                           # fondo y texto del estilo por defecto
    $malos = @()
    foreach ($e in ($usados.Keys | Sort-Object)) {
        if ($e -eq 50) { continue }                                                # la ruta oculta no se dibuja
        $b = Sci 2482 $e; $f = Sci 2481 $e
        if ($b -ne $db) { $malos += "estilo ${e}: fondo $(Hex $b) != tema $(Hex $db)" }
        if ($e -ne 51 -and $f -ne $df) { $malos += "estilo ${e}: texto $(Hex $f) != tema $(Hex $df)" }
        if ((Sci 2487 $e) -ne 0) { $malos += "estilo ${e}: con relleno de fin de línea" }
    }
    Veredicto "$etiqueta | fondo y texto de los $($usados.Count) estilos usados = tema (fondo $(Hex $db), texto $(Hex $df))" ($malos.Count -eq 0) ($malos -join '; ')
    # ruta visible (51): medio camino entre texto y fondo (se fuerza a mostrarse con el cursor sobre la ruta)
    $iniRuta = [Text.Encoding]::UTF8.GetByteCount($texto.Substring(0, $texto.IndexOf('texto.txt')))
    [void](Sci 2025 $iniRuta); Start-Sleep -Milliseconds 400
    $f51 = Sci 2481 51; $esp = Mezcla $df $db
    Veredicto "$etiqueta | ruta visible (51) = medio camino texto/fondo ($(Hex $esp)) y se ve ahí (estilo $(Sci 2010 $iniRuta))" (($f51 -eq $esp) -and ((Sci 2010 $iniRuta) -eq 51)) "51=$(Hex $f51)"
    $hot = Sci 2494 0    # SCI_GETHOTSPOTACTIVEFORE
    $claro = (Brillo $db) -ge 128
    $contraste = [Math]::Abs((Brillo $hot) - (Brillo $db))
    Veredicto "$etiqueta | color al pasar el mouse $(Hex $hot) contrasta con el fondo (diferencia $([int]$contraste) de 255)" ($contraste -ge 60 -and ((Sci 2493 52) -eq 1)) ''
    # el .txt de la misma ventana
    Npp-Activar $iT; Start-Sleep -Milliseconds 400
    $b0t = Sci 2482 0; $f0t = Sci 2481 0
    Npp-Activar $iS; Start-Sleep -Milliseconds 400
    Veredicto "$etiqueta | el estilo 0 del .stdoer ($(Hex (Sci 2482 0))/$(Hex (Sci 2481 0))) = el del .txt ($(Hex $b0t)/$(Hex $f0t))" (((Sci 2482 0) -eq $b0t) -and ((Sci 2481 0) -eq $f0t)) ''
}

function Abrir-Doc([string]$etiqueta) {
    Npp-Abrir @($docS, $docT)
    $iS = (Npp-Documentos | Where-Object { $_.Ruta -eq $docS }).Indice
    $iT = (Npp-Documentos | Where-Object { $_.Ruta -eq $docT }).Indice
    return @($iS, $iT)
}

try {
    Write-Host '=== Parte A: arranque con distintas configuraciones ==='
    $variantes = @(
        @{ n = 'tema por defecto (claro)';          modo = 'no';  tema = '' },
        @{ n = 'modo oscuro (Deep Black)';          modo = 'yes'; tema = ''; osc = 'Deep Black.xml' },
        @{ n = 'modo oscuro (DarkModeDefault)';     modo = 'yes'; tema = ''; osc = 'DarkModeDefault.xml' },
        @{ n = 'tema oscuro Zenburn (sin modo oscuro)'; modo = 'no'; tema = 'Zenburn.xml' },
        @{ n = 'tema oscuro Monokai';               modo = 'no';  tema = 'Monokai.xml' },
        @{ n = 'tema oscuro Obsidian';              modo = 'no';  tema = 'Obsidian.xml' },
        @{ n = 'tema claro con fondo de color: Solarized-light'; modo = 'no'; tema = 'Solarized-light.xml' },
        @{ n = 'tema de colores raros: Hello Kitty'; modo = 'no'; tema = 'Hello Kitty.xml' }
    )
    foreach ($v in $variantes) {
        Write-Host "--- $($v.n)"
        Config $v.modo $v.tema $v.osc
        $ix = Abrir-Doc $v.n
        Medir $v.n $ix[0] $ix[1]
        Npp-Cerrar
    }

    Write-Host '=== Parte B: cambio de tema en caliente (Configurador de estilos) ==='
    Config 'no' ''
    $ix = Abrir-Doc 'caliente'
    Medir 'inicio (por defecto)' $ix[0] $ix[1]
    [void](NppMsg $NPPM_MENUCOMMAND 0 46001)       # Configuración > Configurador de estilos
    $dlg = [IntPtr]::Zero
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 150; $dlg = [NppT]::VentanaConTitulo([uint32]$script:ProcNpp.Id, 'Style Configurator'); if ($dlg -ne [IntPtr]::Zero) { break } }
    if ($dlg -eq [IntPtr]::Zero) { throw 'No apareció el Configurador de estilos' }
    $combo = [NppT]::GetDlgItem($dlg, 2307)
    function Tema([string]$nombre) {
        $idx = [int][NppT]::SendMessageStr($combo, 0x014C, [IntPtr](-1), $nombre)      # CB_FINDSTRING
        if ($idx -lt 0) { throw "No hay tema '$nombre' en el Configurador" }
        [void][NppT]::SendMessage($combo, 0x014E, [IntPtr]$idx, [IntPtr]::Zero)         # CB_SETCURSEL
        [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr](2307 + (1 -shl 16)), $combo)   # WM_COMMAND, CBN_SELCHANGE
        Start-Sleep -Milliseconds 1200
    }
    foreach ($t in 'Zenburn', 'Obsidian', 'Default', 'Solarized-light', 'Hello Kitty', 'Black board', 'Default') {
        Tema $t
        Medir "en caliente -> $t" $ix[0] $ix[1]
    }
    # Cancelar el Configurador (deja el tema como estaba)
    [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr]2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800
    Npp-Cerrar

    Write-Host '=== Parte C: modo oscuro / claro en caliente (Preferencias) ==='
    Config 'no' ''
    $ix = Abrir-Doc 'modo en caliente'
    Medir 'inicio (claro)' $ix[0] $ix[1]
    [void](NppMsg $NPPM_MENUCOMMAND 0 48011)       # Configuración > Preferencias
    $pref = [IntPtr]::Zero
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 150; $pref = [NppT]::VentanaConTitulo([uint32]$script:ProcNpp.Id, 'Preferences'); if ($pref -ne [IntPtr]::Zero) { break } }
    if ($pref -eq [IntPtr]::Zero) { throw 'No apareció Preferencias' }
    $rClaro = [NppT]::HijoPorId($pref, 7131); $rOscuro = [NppT]::HijoPorId($pref, 7132)
    if ($rClaro -eq [IntPtr]::Zero -or $rOscuro -eq [IntPtr]::Zero) { throw 'No se encontraron los botones Light mode / Dark mode' }
    foreach ($paso in 'oscuro', 'claro', 'oscuro', 'claro') {
        $boton = if ($paso -eq 'oscuro') { $rOscuro } else { $rClaro }
        [void][NppT]::SendMessage($boton, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)      # BM_CLICK
        Start-Sleep -Milliseconds 1800
        Medir "modo $paso en caliente" $ix[0] $ix[1]
    }
    [void][NppT]::SendMessage($pref, 0x0111, [IntPtr]6001, [NppT]::GetDlgItem($pref, 6001))    # Cerrar
    Start-Sleep -Milliseconds 600
    Npp-Cerrar
}
finally {
    Copy-Item $respaldo $cfg -Force      # la configuración original del portátil, siempre
}
Write-Host "RESUMEN: $mal fallos"
if ($mal -gt 0) { exit 1 }
