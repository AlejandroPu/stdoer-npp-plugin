# Genera pruebas\demo-enlaces.stdoer (con rutas absolutas a los archivos de tests\objetivos\,
# calculadas aquí: lo versionado no lleva rutas de nadie) y abre el Notepad++ portátil con él a
# la izquierda y la demostración de llaves (pruebas\demo-llaves.stdoer) a la derecha.
# Los clics SÍ abren de verdad (pestañas, Explorador, programa de Windows para .ods).
#
# Uso (desde la carpeta stdoer):   .\tests\abrir-demo-enlaces.ps1

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$obj = Join-Path $raiz 'tests\objetivos'
$pruebas = Join-Path $raiz 'pruebas'
if (-not (Test-Path $pruebas)) { New-Item -ItemType Directory $pruebas | Out-Null }

$demo = @"
Demostración de enlaces (stdoer 0.5.0)
Todo esto es inventado: los enlaces apuntan a archivos de prueba dentro de la carpeta del plugin.
Pasa el mouse sobre un enlace (recuadro con la ruta) y haz clic sobre «link[]» para abrirlo.
Clic DERECHO sobre un enlace: menú con Abrir, Abrir carpeta contenedora y Desactivar enlace
(sobre uno desactivado, Activar enlace). Ctrl+Z deshace cada cambio con un solo paso.

1. Texto: se abre en una pestaña de Notepad++
   __link[$obj\texto.txt]
2. Hoja de cálculo (.ods): con el programa que Windows tenga asignado (si no hay ninguno, se muestra su carpeta)
   __link[$obj\hoja.ods]
3. Carpeta: se abre en el Explorador
   __link[$obj\carpeta]
4. Ejecutable (.exe): NUNCA se ejecuta; se muestra su carpeta en el Explorador
   __link[$obj\inofensivo.exe]
5. Enlace roto (el archivo no existe): el recuadro lo dice y el clic no hace nada
   __link[$obj\no-existe.txt]
6. Enlace desactivado (un solo _ ): se ve completo y no hace nada
   _link[$obj\texto.txt]
7. Ruta con corchetes en el nombre: el último ] es el que cierra
   __link[$obj\archivo [1].txt]
8. Ruta relativa: no se abre (solo rutas completas)
   __link[tests\objetivos\texto.txt]
9. Sin extensión: solo se muestra su carpeta
   __link[$obj\sinextension]
10. Varios enlaces en una línea: __link[$obj\texto.txt] y __link[$obj\carpeta]
11. Ruta de red que no responde (puede tardar hasta un segundo, nunca más): el recuadro dice que no hubo respuesta
   __link[\\10.255.255.1\recurso\x.txt]
12. Un enlace dentro de una región { } (al contraer, se esconde también la llave de cierre) {
   Texto de la región.
   __link[$obj\texto.txt]
}
13. Dirección web (se abre en el navegador; el recuadro muestra la dirección sin tocar la red)
   __link[https://notepad-plus-plus.org/]
14. Otra dirección web, con http
   __link[http://example.com/]
15. Esquema NO permitido (solo http y https se abren): el recuadro lo dice y el clic no hace nada
   __link[javascript:alert(1)]
16. Otro esquema no permitido (protocolo de un programa de Windows)
   __link[ms-settings:network]

Para editar una ruta: borra un _ (queda _link[...] y la ruta se ve), edítala y vuelve a escribir el _.
Con el cursor dentro de los corchetes, o con una selección que toque el enlace, la ruta se muestra sola.
Al final de este archivo hay una línea con una { que no cierra nunca: no esconde nada. {
Fin.
"@
$demoLf = $demo -replace "`r`n", "`n"
$archivo = Join-Path $pruebas 'demo-enlaces.stdoer'
[IO.File]::WriteAllText($archivo, $demoLf, (New-Object Text.UTF8Encoding $false))

$llaves = Join-Path $pruebas 'demo-llaves.stdoer'
Copy-Item (Join-Path $raiz 'tests\llaves\L23_demo.stdoer') $llaves -Force

& (Join-Path $PSScriptRoot 'abrir-lado-a-lado.ps1') -Izq 'pruebas\demo-enlaces.stdoer' -Der 'pruebas\demo-llaves.stdoer'
