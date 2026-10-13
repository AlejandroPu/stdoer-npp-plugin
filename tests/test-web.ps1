# Enlaces web: SOLO http y https se abren (en el navegador). Todo lo demás —otros esquemas
# (javascript:, file:, ms-settings:, protocolos de programas...), direcciones http mal formadas,
# con caracteres peligrosos o demasiado largas— NO se abre, y el recuadro lo dice.
# Se prueba con el modo de pruebas del plugin (STDOER_SIN_SHELL): el plugin anota qué haría y
# no llama a Windows, así que ninguna prueba abre un navegador ni un programa de verdad.
# Cada caso es un enlace de un documento .stdoer: se pide "Abrir" (como el clic o el menú) y el
# recuadro (como el mouse detenido) y se lee el registro.
#
# Uso (desde la carpeta stdoer):   .\tests\probar-web.ps1

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'herramientas-npp.ps1')

$work = Join-Path $Raiz 'build\web'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$obj = Join-Path $Raiz 'tests\objetivos'
$docS = Join-Path $work 'web.stdoer'; $log = Join-Path $work 'web.log'

$larga = 'https://example.com/' + ('a' * 2100)
# tipo: web = se abre en el navegador; no = rechazado (no se abre nada); rel = no es dirección web
# ni ruta absoluta (no se abre); ruta = una ruta de archivo de verdad (regla de siempre).
$casos = @(
    @{ t = 'http://example.com';                         k = 'web' },
    @{ t = 'https://example.com/a/b?c=d&e=f#frag';        k = 'web' },
    @{ t = 'HTTPS://EXAMPLE.COM';                        k = 'web' },
    @{ t = 'Http://Example.com/Path';                    k = 'web' },
    @{ t = 'http://localhost:8080/x';                    k = 'web' },
    @{ t = 'https://notepad-plus-plus.org/';             k = 'web' },
    @{ t = 'http://[::1]/ruta';                          k = 'web' },
    @{ t = 'https://user@example.com:8443/p%20q';        k = 'web' },
    @{ t = 'http://192.168.0.1/';                        k = 'web' },
    @{ t = '   https://example.com/espacios-alrededor   '; k = 'web' },
    @{ t = 'https://ejemplo.com/ñandú';                  k = 'web'; ascii = $false },
    @{ t = 'javascript:alert(1)';                        k = 'no' },
    @{ t = 'JavaScript:alert(1)';                        k = 'no' },
    @{ t = 'JAVASCRIPT:void(0)';                         k = 'no' },
    @{ t = '  javascript:alert(1)';                      k = 'no' },
    @{ t = 'file:///C:/Windows/System32/calc.exe';       k = 'no' },
    @{ t = 'FILE://servidor/recurso/x.exe';              k = 'no' },
    @{ t = 'ms-settings:network';                        k = 'no' },
    @{ t = 'ms-calculator:';                             k = 'no' },
    @{ t = 'mailto:alguien@example.com';                 k = 'no' },
    @{ t = 'tel:+56912345678';                           k = 'no' },
    @{ t = 'ftp://example.com/x';                        k = 'no' },
    @{ t = 'sftp://example.com/x';                       k = 'no' },
    @{ t = 'ssh://host';                                 k = 'no' },
    @{ t = 'telnet://host';                              k = 'no' },
    @{ t = 'ws://host/x';                                k = 'no' },
    @{ t = 'wss://host/x';                               k = 'no' },
    @{ t = 'data:text/html,hola';                        k = 'no' },
    @{ t = 'vbscript:msgbox(1)';                         k = 'no' },
    @{ t = 'steam://run/1';                              k = 'no' },
    @{ t = 'zoommtg://zoom.us/join?confno=1';            k = 'no' },
    @{ t = 'search-ms:query=x';                          k = 'no' },
    @{ t = 'shell:startup';                              k = 'no' },
    @{ t = 'ms-msdt:/id PCWDiagnostic';                  k = 'no' },
    @{ t = 'onenote:https://example.com/x';              k = 'no' },
    @{ t = 'chrome://settings';                          k = 'no' },
    @{ t = 'edge://settings';                            k = 'no' },
    @{ t = 'about:blank';                                k = 'no' },
    @{ t = 'view-source:https://example.com';            k = 'no' },
    @{ t = 'blob:https://example.com/uuid';              k = 'no' },
    @{ t = 'cmd:/c calc';                                k = 'no' },
    @{ t = 'powershell:iex';                             k = 'no' },
    @{ t = 'httpx://example.com';                        k = 'no' },
    @{ t = 'http+evil://example.com';                    k = 'no' },
    @{ t = 'http:/example.com';                          k = 'no' },
    @{ t = 'http:example.com';                           k = 'no' },
    @{ t = 'http://';                                    k = 'no' },
    @{ t = 'https:///x';                                 k = 'no' },
    @{ t = 'http://?x';                                  k = 'no' },
    @{ t = 'http://#x';                                  k = 'no' },
    @{ t = 'https://a.b/c d';                            k = 'no' },
    @{ t = 'https://a.b/c"d';                            k = 'no' },
    @{ t = 'https://a.b/c<d';                            k = 'no' },
    @{ t = 'https://a.b/c>d';                            k = 'no' },
    @{ t = 'https://a.b/c^d';                            k = 'no' },
    @{ t = 'https://a.b/c`d';                            k = 'no' },
    @{ t = 'https://a.b\c';                              k = 'no' },
    @{ t = "https://a.b/c`td";                           k = 'no' },
    @{ t = $larga;                                       k = 'no'; corta = $true },
    @{ t = 'http//example.com';                          k = 'rel' },
    @{ t = 'www.example.com';                            k = 'rel' },
    @{ t = '//example.com/x';                            k = 'rel' },
    @{ t = 'c:calc.exe';                                 k = 'rel' },
    @{ t = 'h ttp://a.b';                                k = 'rel' },
    @{ t = "java`tscript:alert(1)";                      k = 'rel' },
    @{ t = 'јavascript:alert(1)';                        k = 'rel' },      # la "ј" es cirílica
    @{ t = "$obj\texto.txt";                             k = 'ruta' }
)
$lineas = $casos | ForEach-Object { "__link[$($_.t)]" }
[IO.File]::WriteAllText($docS, (($lineas -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

$mal = 0
function Veredicto([string]$nombre, [bool]$ok, [string]$detalle = '') {
    if (-not $ok) { $script:mal++ }
    Write-Host ("{0,-90} {1}" -f $nombre, $(if ($ok) { 'OK' } else { "MAL  $detalle" }))
}
function LogLineas { if (Test-Path $log) { @(Get-Content $log -Encoding UTF8) } else { @() } }

Npp-Abrir @($docS) $log @{ STDOER_SIN_SHELL = '1' }
[void](Sci 4003 0 -1)
$docsAntes = (Npp-Documentos).Count

for ($i = 0; $i -lt $casos.Count; $i++) {
    $c = $casos[$i]
    $pos = [int64]((Sci 2167 $i) + 3)
    $mostrar = $c.t -replace "`t", '<TAB>'
    if ($mostrar.Length -gt 60) { $mostrar = $mostrar.Substring(0, 57) + '...' }
    $antes = @(LogLineas).Count
    [void](Sci 2201)                                               # SCI_CALLTIPCANCEL
    [void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', 1, $pos)    # recuadro
    Start-Sleep -Milliseconds 150
    [void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', 3, $pos)    # clic izquierdo
    Start-Sleep -Milliseconds 250
    if ($c.k -eq 'web') { [void][NppT]::MensajeAPlugin($script:HNpp, 'Stdoer.dll', 11, $pos); Start-Sleep -Milliseconds 250 }   # y "Abrir" del menú
    $nuevo = @(LogLineas)[$antes..99999] | Where-Object { $_ }
    $texto = $nuevo -join ' ¦ '
    $recuadro = ($nuevo | Where-Object { $_ -match '^recuadro:' }) -join ''
    $abrirTodos = @($nuevo | Where-Object { $_ -match '^abrir:' })
    $abrir = $abrirTodos[0]
    switch ($c.k) {
        'web' {
            $esperado = $c.t.Trim()
            if ($c.ascii -eq $false) {
                $ok = ($abrir -like 'abrir: navegador https://ejemplo.com/*') -and ($recuadro -like 'recuadro: https://ejemplo.com/*') -and ($recuadro -notmatch 'no se abre')
            } else {
                $ok = ($abrir -eq "abrir: navegador $esperado") -and ($recuadro -eq "recuadro: $esperado")
            }
            $ok = $ok -and ($abrirTodos.Count -eq 2) -and ($abrirTodos[0] -eq $abrirTodos[1])      # clic y "Abrir" del menú hacen lo mismo
            Veredicto "SE ABRE en el navegador (clic y menú): $mostrar" $ok $texto
        }
        'no' {
            $ok = ($abrir -like 'abrir: esquema o direccion no permitidos*') -and ($recuadro -match 'no se abre: solo se abren direcciones http y https') -and ($abrir -notmatch 'navegador|en Notepad|con Windows|carpeta')
            Veredicto "NO SE ABRE (rechazado): $mostrar" $ok $texto
        }
        'rel' {
            $ok = ($abrir -like 'abrir: ruta no absoluta*') -and ($recuadro -match 'ruta relativa: no se abre')
            Veredicto "NO SE ABRE (no es web ni ruta absoluta): $mostrar" $ok $texto
        }
        'ruta' {
            $ok = (@($abrirTodos | Where-Object { $_ -like 'abrir: en Notepad++ *texto.txt' }).Count -eq 1) -and ($recuadro -notmatch 'no se abre')
            Veredicto "una ruta de archivo sigue igual (se abre en Notepad++): $mostrar" $ok $texto
        }
    }
}

# Nada se abrió de verdad: ninguna pestaña nueva salvo la del enlace de ruta (texto.txt)
$docsDespues = (Npp-Documentos).Count
Veredicto 'solo se abrió UNA pestaña nueva en total (la del enlace a texto.txt)' ($docsDespues -eq $docsAntes + 1) "antes=$docsAntes despues=$docsDespues"
Veredicto 'ningún caso web llamó a Windows (modo de pruebas): el registro no tiene "con Windows"' (@(LogLineas | Where-Object { $_ -match 'con Windows' }).Count -eq 0)
Write-Host "RESUMEN: $mal fallos de $($casos.Count + 2) comprobaciones"
Npp-Cerrar
if ($mal -gt 0) { exit 1 }
