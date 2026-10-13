# Prueba el menú del clic derecho con el Notepad++ PORTÁTIL, con el camino real: se manda
# WM_CONTEXTMENU a la vista (como lo hace Windows al hacer clic derecho), se espera el menú
# emergente de verdad, se lee su contenido y se elige con el teclado (Abajo + Intro).
#   - Sobre un enlace activo / desactivado / web / roto...: las opciones correctas (y cuáles en gris).
#   - Fuera de un enlace (texto, tras el final del enlace, tras el final de la línea, "mi_link[0]",
#     "___link[x]", otra pestaña .txt): el menú NORMAL de Notepad++ (trae "Cut").
#   - Cada opción hace lo que dice (se mira el registro del plugin, con STDOER_SIN_SHELL: nada se
#     abre de verdad); Activar / Desactivar cambian UN "_" y se deshacen con UN solo Deshacer.
#   - Un menú cancelado no cambia nada; solo lectura; menú desde el teclado.
#
# Uso (desde la carpeta stdoer):   .\tests\probar-menu.ps1

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$work = Join-Path $Raiz 'build\menu'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Raiz 'tests\objetivos'
$docS = Join-Path $work 'menu.stdoer'; $docT = Join-Path $work 'otro.txt'; $log = Join-Path $work 'menu.log'
$lineas = @(
    'texto normal aqui',
    "__link[$obj\texto.txt] fin",
    "__link[$obj\carpeta]",
    "__link[$obj\inofensivo.exe]",
    "__link[$obj\no-existe.txt]",
    "_link[$obj\texto.txt] apagado",
    '__link[https://notepad-plus-plus.org/]',
    '__link[javascript:alert(1)]',
    '__link[tests\objetivos\texto.txt]',
    'mi_link[0] y x_link[ruta] y ___link[x.txt]',
    '',
    '{',
    "    __link[$obj\texto.txt]",
    '}',
    'zz'
)
$original = ($lineas -join "`n") + "`n"
[IO.File]::WriteAllText($docS, $original, (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText($docT, "__link[$obj\texto.txt] en un txt`n", (New-Object Text.UTF8Encoding $false))

$mal = 0
function Veredicto([string]$nombre, [bool]$ok, [string]$detalle = '') {
    if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-88} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  $detalle" }))
}
function LogLineas { if (Test-Path $log) { @(Get-Content $log) } else { @() } }
function Resumen($items) {
    if ($null -eq $items) { return 'SIN MENU' }
    if ($items -match '42001\|Cut') { return 'NORMAL' }
    $r = @()
    foreach ($l in ($items -split "`n")) {
        if ($l -match '^(\d+)\|([^|]*)\|(\w+)$') { $r += $Matches[2] + $(if ($Matches[3] -eq 'gris') { ' (gris)' } else { '' }) }
    }
    $r -join ' | '
}
function Ini([int]$linea) { [int](Sci 2167 $linea) }          # SCI_POSITIONFROMLINE
function Texto { (SciTexto) }

Npp-Abrir @($docS, $docT) $log @{ STDOER_SIN_SHELL = '1' }
$iS = (Npp-Documentos | Where-Object { $_.Ruta -eq $docS }).Indice
$iT = (Npp-Documentos | Where-Object { $_.Ruta -eq $docT }).Indice
Npp-Activar $iS; Start-Sleep -Milliseconds 600
[void](Sci 4003 0 -1)
Veredicto 'el documento está tal cual (inicio)' ((Texto) -eq $original)

$A3 = 'Abrir | Abrir carpeta contenedora | Desactivar enlace'
Write-Host '--- opciones según el enlace'
$casos = @(
    @{ n = 'enlace a un texto';                    l = 1;  k = 2; e = $A3 },
    @{ n = 'enlace a una carpeta';                 l = 2;  k = 2; e = $A3 },
    @{ n = 'enlace a un .exe (Abrir muestra su carpeta)'; l = 3; k = 2; e = $A3 },
    @{ n = 'enlace roto (no existe)';              l = 4;  k = 2; e = 'Abrir (gris) | Abrir carpeta contenedora | Desactivar enlace' },
    @{ n = 'enlace desactivado (_link[)';          l = 5;  k = 1; e = 'Activar enlace' },
    @{ n = 'dirección web https';                  l = 6;  k = 2; e = 'Abrir | Desactivar enlace' },
    @{ n = 'esquema rechazado (javascript:)';      l = 7;  k = 2; e = 'Abrir (gris) | Desactivar enlace' },
    @{ n = 'ruta relativa';                        l = 8;  k = 2; e = 'Abrir (gris) | Abrir carpeta contenedora (gris) | Desactivar enlace' },
    @{ n = 'enlace dentro de una región { }';      l = 12; k = 6; e = $A3 }
)
foreach ($c in $casos) {
    $obtenido = Resumen (Npp-MenuContextual ((Ini $c.l) + $c.k))
    Veredicto "$($c.n)" ($obtenido -eq $c.e) "obtuvo: $obtenido"
}

Write-Host '--- cualquier punto del enlace (línea 1) abre el menú del enlace; fuera de él, el normal'
$t = Texto
$lin1 = $lineas[1]; $cierra = $lin1.IndexOf(']')
foreach ($k in 0, 1, 2, 6) {
    Veredicto "sobre el carácter $k del enlace (`"$($lin1.Substring($k, 1))`")" ((Resumen (Npp-MenuContextual ((Ini 1) + $k))) -eq $A3)
}
Veredicto 'sobre el "]" que cierra' ((Resumen (Npp-MenuContextual ((Ini 1) + $cierra))) -eq $A3)
Veredicto 'justo después del "]" (el espacio): menú normal' ((Resumen (Npp-MenuContextual ((Ini 1) + $cierra + 1))) -eq 'NORMAL')
Veredicto 'sobre el texto de después ("fin"): menú normal' ((Resumen (Npp-MenuContextual ((Ini 1) + $cierra + 3))) -eq 'NORMAL')
Veredicto 'en el vacío a la derecha del final de la línea: menú normal' ((Resumen (Npp-MenuContextual ((Ini 1) + $lin1.Length) 120 3)) -eq 'NORMAL')
Veredicto 'sobre texto normal (línea 0): menú normal' ((Resumen (Npp-MenuContextual ((Ini 0) + 3))) -eq 'NORMAL')
$l9 = $lineas[9]
foreach ($par in @(@('mi_link[0]', 'mi_link[0] (letra antes del _)'), @('x_link[ruta]', 'x_link[ruta] (letra antes del _)'), @('___link[x.txt]', '___link[x.txt] (tres _: no es enlace)'))) {
    Veredicto "$($par[1]): menú normal" ((Resumen (Npp-MenuContextual ((Ini 9) + $l9.IndexOf($par[0]) + 4))) -eq 'NORMAL')
}
Npp-Activar $iT; Start-Sleep -Milliseconds 500
Veredicto 'en un .txt con "__link[...]": menú normal (el plugin solo actúa en .stdoer)' ((Resumen (Npp-MenuContextual 4)) -eq 'NORMAL')
Npp-Activar $iS; Start-Sleep -Milliseconds 500
Veredicto 'tras todo eso el documento sigue idéntico' ((Texto) -eq $original)

Write-Host '--- un menú cancelado no cambia nada (ya cancelado arriba); elegir con el teclado'
function Elegir([int]$linea, [int]$k, [int]$n) {
    $antes = @(LogLineas).Count
    $r = Npp-MenuContextual ((Ini $linea) + $k) -Elegir -Bajar $n
    Start-Sleep -Milliseconds 700
    $nuevo = @(LogLineas)[$antes..99999] | Where-Object { $_ }
    return [pscustomobject]@{ Items = (Resumen $r); Log = ($nuevo -join ' ¦ ') }
}

# Abrir
$nDocs = (Npp-Documentos).Count
$r = Elegir 1 2 1
Veredicto 'Abrir en un texto: lo abre en una pestaña de Notepad++' (($r.Log -match 'abrir: en Notepad\+\+ .*texto\.txt') -and ((Npp-Documentos).Count -eq $nDocs + 1)) $r.Log
Npp-Activar $iS; Start-Sleep -Milliseconds 400
$r = Elegir 2 2 1
Veredicto 'Abrir en una carpeta: abre la carpeta' ($r.Log -match 'abrir: carpeta .*carpeta') $r.Log
$r = Elegir 3 2 1
Veredicto 'Abrir en un .exe: NO lo ejecuta, muestra su carpeta' (($r.Log -match 'abrir: carpeta contenedora de .*inofensivo\.exe') -and ($r.Log -notmatch 'con Windows')) $r.Log
$r = Elegir 6 2 1
Veredicto 'Abrir en una dirección https: la abre en el navegador' ($r.Log -match 'abrir: navegador https://notepad-plus-plus\.org/') $r.Log
# Abrir carpeta contenedora
$r = Elegir 1 2 2
Veredicto 'Abrir carpeta contenedora (archivo existente): lo muestra en su carpeta' ($r.Log -match 'abrir: carpeta contenedora de .*texto\.txt') $r.Log
$r = Elegir 4 2 2
Veredicto 'Abrir carpeta contenedora (archivo roto): abre la carpeta que sí existe' ($r.Log -match 'abrir: carpeta .*objetivos \(el archivo no existe\)') $r.Log
# opciones en gris: aunque se pidan por el canal de pruebas, no hacen nada
Write-Host '--- opciones en gris no hacen nada (pedidas por el canal de pruebas)'
foreach ($c in @(@(4, 11, 'Abrir en un enlace roto'), @(7, 11, 'Abrir en un esquema rechazado'), @(8, 11, 'Abrir en una ruta relativa'), @(8, 12, 'Abrir carpeta contenedora en una ruta relativa'))) {
    $antes = @(LogLineas).Count
    [void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', $c[1], [int64]((Ini $c[0]) + 3))
    Start-Sleep -Milliseconds 500
    $nuevo = (@(LogLineas)[$antes..99999] | Where-Object { $_ }) -join ' ¦ '
    Veredicto "$($c[2]): no está disponible, no se hace nada" (($nuevo -match 'no esta disponible') -and ($nuevo -notmatch 'abrir:')) $nuevo
}

# Desactivar / Activar: un "_", un solo Deshacer
Write-Host '--- Desactivar / Activar'
Npp-Activar $iS; Start-Sleep -Milliseconds 400
[void](Sci 2175)                 # SCI_EMPTYUNDOBUFFER: el historial de deshacer parte vacío
$antes = Texto
$r = Elegir 1 2 3
$desp = Texto
$esperado = $antes.Remove((Ini 1), 1)
Veredicto 'Desactivar enlace: quita exactamente UN "_" (y nada más)' ($desp -eq $esperado) $r.Log
Veredicto '   la línea ahora empieza con "_link[" y la ruta se ve completa' ($desp.Split("`n")[1].StartsWith('_link['))
Veredicto '   el menú del enlace desactivado ofrece "Activar enlace"' ((Resumen (Npp-MenuContextual ((Ini 1) + 2))) -eq 'Activar enlace')
[void](Sci 2176)                 # SCI_UNDO: UN Ctrl+Z
Veredicto '   UN solo Deshacer devuelve el documento tal cual estaba' ((Texto) -eq $antes)
Veredicto '   y no queda nada más que deshacer' ((Sci 2174) -eq 0)       # SCI_CANUNDO
[void](Sci 2011)                 # SCI_REDO
Veredicto '   Rehacer lo vuelve a desactivar' ((Texto) -eq $desp)
[void](Sci 2176)

$antes = Texto
$r = Elegir 5 2 1
$desp = Texto
Veredicto 'Activar enlace: agrega exactamente UN "_" (y nada más)' ($desp -eq $antes.Insert((Ini 5), '_')) $r.Log
Veredicto '   la línea ahora empieza con "__link[" y la ruta vuelve a ocultarse' (($desp.Split("`n")[5].StartsWith('__link[')) -and ((Resumen (Npp-MenuContextual ((Ini 5) + 2))) -eq $A3))
[void](Sci 2176)
Veredicto '   UN solo Deshacer devuelve el documento tal cual estaba' ((Texto) -eq $antes)
Veredicto '   y no queda nada más que deshacer' ((Sci 2174) -eq 0)

# varias veces seguidas, ida y vuelta
$antes = Texto
foreach ($i in 1..3) { [void](Elegir 1 2 3); [void](Elegir 1 2 1) }
Veredicto '3 veces Desactivar+Activar seguidas: queda igual que al principio' ((Texto) -eq $antes)
foreach ($i in 1..6) { [void](Sci 2176) }
Veredicto '   y 6 Deshacer (uno por acción) lo dejan igual que al principio' ((Texto) -eq $original)

# web: Desactivar y Activar una dirección
$antes = Texto
[void](Elegir 6 2 2)
Veredicto 'Desactivar una dirección web: quita un "_"' ((Texto) -eq $antes.Remove((Ini 6), 1))
[void](Elegir 6 2 1)
Veredicto 'y Activar la deja como estaba' ((Texto) -eq $antes)

# el menú no cambia el documento si se cancela
$antes = Texto
foreach ($l in 1, 4, 5, 6, 7) { [void](Npp-MenuContextual ((Ini $l) + 2)) }
Veredicto 'menús cancelados (5 enlaces): el documento no cambia' ((Texto) -eq $antes)

Write-Host '--- solo lectura'
[void](Sci 2171 1)              # SCI_SETREADONLY
Veredicto 'sólo lectura: Desactivar sale en gris' ((Resumen (Npp-MenuContextual ((Ini 1) + 2))) -eq 'Abrir | Abrir carpeta contenedora | Desactivar enlace (gris)')
Veredicto 'sólo lectura: Activar sale en gris' ((Resumen (Npp-MenuContextual ((Ini 5) + 2))) -eq 'Activar enlace (gris)')
$antes = Texto
[void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', 13, [int64]((Ini 1) + 3))
Start-Sleep -Milliseconds 400
Veredicto 'sólo lectura: pedir Desactivar por el canal de pruebas no cambia nada' ((Texto) -eq $antes)
[void](Sci 2171 0)

Write-Host '--- menú desde el teclado (tecla Menú / Mayús+F10)'
[void](Sci 2025 ((Ini 1) + 3))   # cursor sobre el enlace
Veredicto 'cursor sobre un enlace: aparece el menú del enlace' ((Resumen (Npp-MenuContextual 0 -Teclado)) -eq $A3)
[void](Sci 2025 ((Ini 0) + 3))
Veredicto 'cursor fuera de un enlace: menú normal' ((Resumen (Npp-MenuContextual 0 -Teclado)) -eq 'NORMAL')

Veredicto 'al final, el documento sigue idéntico al original' ((Texto) -eq $original)
Write-Host '--- registro del plugin: sin errores'
$todo = LogLineas
Veredicto 'el registro no menciona errores' (@($todo | Where-Object { $_ -match 'error|excepci' }).Count -eq 0)
Write-Host "RESUMEN: $mal fallos"
Npp-Cerrar
if ($mal -gt 0) { exit 1 }
