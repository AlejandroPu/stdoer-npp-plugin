# Comprueba que el ocultamiento de la ruta SOBREVIVE a lo que Notepad++ hace con los estilos:
# cambiar de pestaña, cambiar el lenguaje del documento y reiniciar todos los estilos (lo que
# hace al cambiar de tema, SCI_STYLECLEARALL). Y que, cuando el documento deja de ser .stdoer,
# los números de estilo 50-52 vuelven a ser normales (otro lexer podría usarlos).
#
# Uso (desde la carpeta stdoer):   .\tests\probar-persistencia-enlaces.ps1

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$work = Join-Path $Raiz 'build\persistencia'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$docA = Join-Path $work 'enlace.stdoer'; $docB = Join-Path $work 'otro.txt'
[IO.File]::WriteAllText($docA, "antes __link[ruta-secreta.txt] despues`n", (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText($docB, "documento de texto normal`n", (New-Object Text.UTF8Encoding $false))

$mal = 0
function Veredicto([string]$nombre, [bool]$ok, [string]$detalle = '') {
    if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-72} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  $detalle" }))
}
function Oculta { ((SciMapaEstilos (SciTexto)).Split("`n")[0]) -match '^\.{8}lllllh{16}l' }
function Atributos { "vis50=$(Sci 2491 50) chg50=$(Sci 2492 50) hot52=$(Sci 2493 52)" }
function Mover { [void](Sci 2025 0); Start-Sleep -Milliseconds 150 }

Npp-Abrir @($docA, $docB)
$a = (Npp-Documentos | Where-Object { $_.Ruta -eq $docA }).Indice
$b = (Npp-Documentos | Where-Object { $_.Ruta -eq $docB }).Indice
Npp-Activar $a; [void](Sci 4003 0 -1); Mover
Veredicto 'inicio: ruta oculta, estilos puestos' ((Oculta) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) (Atributos)

# 1) cambiar de pestaña y volver
Npp-Activar $b; Start-Sleep -Milliseconds 300
Veredicto 'en otra pestaña (.txt): los estilos 50-52 vuelven a ser normales' (((Sci 2491 50) -eq 1) -and ((Sci 2492 50) -eq 1) -and ((Sci 2493 52) -eq 0)) (Atributos)
Npp-Activar $a; Start-Sleep -Milliseconds 400; Mover
Veredicto 'al volver a la pestaña .stdoer: ruta oculta otra vez' ((Oculta) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) (Atributos + ' mapa=' + ((SciMapaEstilos (SciTexto)).Split("`n")[0]))
for ($i = 0; $i -lt 5; $i++) { Npp-Activar $b; Npp-Activar $a; Start-Sleep -Milliseconds 150 }
Mover
Veredicto '5 idas y vueltas rápidas entre pestañas: sigue oculta' ((Oculta) -and (Sci 2491 50) -eq 0) (Atributos)

# 2) reiniciar todos los estilos (lo que hace Notepad++ al cambiar de tema)
[void](Sci 2050)    # SCI_STYLECLEARALL
Start-Sleep -Milliseconds 100
$tras = Atributos
[void](Sci 2025 3); Start-Sleep -Milliseconds 300     # el siguiente movimiento del cursor repara los estilos
Mover
Veredicto 'tras reiniciar los estilos (STYLECLEARALL) y mover el cursor: oculta de nuevo' ((Oculta) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) ("inmediatamente tras reiniciar: $tras ; ahora: " + (Atributos))

# 3) cambiar el lenguaje del documento a Python y volver a Stdoer
$NPPM_SETCURRENTLANGTYPE = $NPPMSG + 6
[void](NppMsg $NPPM_SETCURRENTLANGTYPE 0 22)           # L_PYTHON
Start-Sleep -Milliseconds 600; [void](Sci 4003 0 -1); Mover
$m = (SciMapaEstilos (SciTexto)).Split("`n")[0]
Veredicto 'como Python: el texto se ve completo (nada oculto) y estilos normales' (($m -notmatch 'h') -and ((Sci 2491 50) -eq 1) -and ((Sci 2493 52) -eq 0)) ("mapa=$m " + (Atributos))
[void](NppMsg $NPPM_SETCURRENTLANGTYPE 0 95)           # L_EXTERNAL (Stdoer)
Start-Sleep -Milliseconds 800; [void](Sci 4003 0 -1); Mover
Veredicto 'de vuelta a Stdoer: ruta oculta otra vez' ((Oculta) -and (Sci 2491 50) -eq 0 -and (Sci 2492 50) -eq 0) ("mapa=" + ((SciMapaEstilos (SciTexto)).Split("`n")[0]) + ' ' + (Atributos))

Write-Host "RESUMEN: $mal fallos"
Npp-Cerrar
if ($mal -gt 0) { exit 1 }
