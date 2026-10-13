# Prueba de los estilos de los enlaces __link[ruta] en el Notepad++ portátil.
#
# Uso (desde la carpeta stdoer):   .\tests\probar-enlaces.ps1
#
# 1) Para cada tests\enlaces\<caso>.stdoer compara, byte a byte, el estilo con <caso>.esperado
#    (una línea de mapa por línea del documento):
#       l = "link[" o "]" (zona clicable)   h = ruta oculta   r = ruta visible   . = otro
#    Los mapas están hechos a mano, no copiados de la salida.
# 2) Atributos de los estilos de la vista (ruta oculta e inmodificable, zona clicable...).
# 3) Mostrar/ocultar la ruta según el cursor y la selección.
# Se trabaja sobre copias en build\enlaces\. No se guarda nada.

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$work = Join-Path $Raiz 'build\enlaces'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$casos = @(Get-ChildItem (Join-Path $Raiz 'tests\enlaces') -Filter *.stdoer | Sort-Object Name)
$copias = @()
foreach ($c in $casos) { $d = Join-Path $work $c.Name; Copy-Item $c.FullName $d; $copias += $d }

$mal = 0
function Veredicto([string]$nombre, [bool]$ok, [string]$detalle = '') {
    if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-62} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  $detalle" }))
}

Npp-Abrir $copias
$docs = Npp-Documentos

# --- 1) estilos por caso ---
foreach ($c in $casos) {
    $base = [IO.Path]::GetFileNameWithoutExtension($c.Name)
    $ruta = Join-Path $work $c.Name
    $d = $docs | Where-Object { $_.Ruta -eq $ruta }
    if (-not $d) { Veredicto "$base (abrir)" $false 'no se abrió'; continue }
    Npp-Activar $d.Indice
    [void](Sci 2025 0)          # SCI_GOTOPOS 0
    [void](Sci 4003 0 -1)       # SCI_COLOURISE
    Start-Sleep -Milliseconds 300
    $texto = SciTexto
    $obtenido = SciMapaEstilos $texto
    $esperado = ((Get-Content (Join-Path $Raiz "tests\enlaces\$base.esperado") -Raw -Encoding UTF8) -replace "`r", '')
    Veredicto "estilos: $base" ($obtenido.TrimEnd("`n") -eq $esperado.TrimEnd("`n")) "esperado=[$($esperado.Replace("`n",'|'))] obtenido=[$($obtenido.Replace("`n",'|'))]"
}

# --- 2) atributos de los estilos (con un documento .stdoer activo) ---
$d = $docs | Where-Object { $_.Ruta -like '*E01_basico*' }
Npp-Activar $d.Indice
Start-Sleep -Milliseconds 300
Veredicto 'estilo 50 (ruta oculta): invisible'        ((Sci 2491 50) -eq 0)
Veredicto 'estilo 50 (ruta oculta): no modificable'   ((Sci 2492 50) -eq 0)
Veredicto 'estilo 51 (ruta visible): visible'         ((Sci 2491 51) -eq 1)
Veredicto 'estilo 51 (ruta visible): modificable'     ((Sci 2492 51) -eq 1)
Veredicto 'estilo 52 (link[ y ]): zona clicable'      ((Sci 2493 52) -eq 1)

# --- 3) mostrar la ruta según el cursor / la selección. E01: "__link[a.txt]" (ruta en 7..11) ---
function MapaActual { SciMapaEstilos (SciTexto) }
function En([int64]$ini, [int64]$fin) { [void](Sci 2160 $ini $fin); Start-Sleep -Milliseconds 250 }   # SCI_SETSEL
$origen = '..lllllhhhhhl'
$visible = '..lllllrrrrrl'
foreach ($p in @(@('cursor al inicio de la línea', 0, 0, $origen),
                 @('cursor entre "k" y "["', 6, 6, $origen),
                 @('cursor justo después de "["', 7, 7, $visible),
                 @('cursor dentro de la ruta', 9, 9, $visible),
                 @('cursor justo antes de "]"', 12, 12, $visible),
                 @('cursor justo después de "]"', 13, 13, $origen),
                 @('selección que contiene todo el enlace', 0, 13, $visible),
                 @('selección que termina en la ruta', 0, 9, $visible),
                 @('selección que empieza en la ruta', 9, 13, $visible),
                 @('selección que termina antes de la ruta', 0, 6, $origen),
                 @('cursor otra vez al inicio', 0, 0, $origen))) {
    En $p[1] $p[2]
    $m = (MapaActual).Split("`n")[0]
    Veredicto "revelado: $($p[0])" ($m -eq $p[3]) "esperado=[$($p[3])] obtenido=[$m]"
}

Write-Host "RESUMEN: $mal fallos"
Npp-Cerrar
if ($mal -gt 0) { exit 1 }
