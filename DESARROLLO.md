# Stdoer — desarrollo

Plugin de Notepad++ (C++, DLL x64 Unicode) para el lenguaje propio de los archivos
`.stdoer`. Diseño completo en el proyecto de planeación: `diseno/lenguaje-notepad.md`.

**Estado: 0.5.0.** Hace estas cosas:

- Menú *Plugins → Stdoer → Acerca de Stdoer*.
- **Lexer externo `stdoer`**, asociado a la extensión `.stdoer`, sin colores propios (usa los
  del tema activo de Notepad++, claro, oscuro o el que sea):
  - contracción por sangría idéntica a la de los `.py`;
  - **contracción con `{ }`** (reglas abajo).
- **Enlaces `__link[ruta]`**: ruta oculta, recuadro al pasar el mouse y clic que abre
  (reglas abajo). Las direcciones `http://` y `https://` se abren en el navegador.
- **Menú del clic derecho sobre un enlace**: Abrir, Abrir carpeta contenedora, Desactivar
  enlace (sobre `_link[...]`: Activar enlace). Fuera de un enlace, el menú normal.

## Contracción con `{ }`

- `{` como **último** carácter de una línea (sin contar espacios ni tabs) abre una región;
  `}` como **primer** carácter de una línea la cierra. Cualquier otra llave no hace nada
  (así la prosa no se contrae por accidente). Solo se mira el texto: comillas, `#` y
  apóstrofes no cuentan. Una línea puede cerrar y abrir (`} sino {`).
- **Se emparejan por pila** (cada `}` cierra la `{` abierta más reciente), sin mirar la
  sangría. Una `}` sin pareja se ignora. **Una `{` sin `}` pareja también se ignora:** un
  error de llaves nunca esconde más de la cuenta, y una `{` sin cerrar no puede tragarse el
  resto del documento. Solo cuenta una `{` que ya tenga su `}`.
- **La línea `}` se esconde con su región:** al contraer solo se ve la línea `{`.
  Excepción: en `} sino {` (cierra una región y abre otra) la línea no puede esconderse con
  la primera y ser cabecera de la segunda a la vez; queda **visible**, fuera de la primera,
  y es la cabecera de la segunda.
- Dentro de una región la contracción por sangría funciona; la sangría se compara solo
  entre líneas de la misma región (una línea menos sangrada que la `{` no saca de la región).
- Una región con solo la `}` debajo se contrae escondiendo esa `}`.
- Sin llaves con pareja, el documento se contrae exactamente como un `.py`.

## Enlaces `__link[ruta]`

- **Qué es un enlace:** `__link[` + ruta + `]`, en una sola línea. El `]` que cierra es el
  que equilibra los corchetes (la ruta puede tener `[ ]`). Varios por línea. Con un solo `_`
  (`_link[...]`) o sin cerrar, es texto normal: no hace nada. Solo se mira el texto.
- **La ruta se oculta**: se ve `__link[]` (estilo de Scintilla invisible). Esa ruta es
  **inmodificable** mientras está oculta (Retroceso, Suprimir, escribir sobre una selección,
  cortar y pegar no la tocan).
- **La ruta se muestra sola** (en gris) mientras el cursor la toca (justo después de `[`,
  dentro, o justo antes de `]`) o una selección la toca. Así, cualquier cambio a una ruta se
  hace a la vista. Para editar una ruta: borrar un `_` (queda `_link[...]`, que se ve
  completo), editar, volver a escribir el `_`.
- **Recuadro al pasar el mouse** sobre el enlace: la ruta completa; si no existe, lo dice;
  si es relativa, lo dice; si la comprobación no responde, lo dice.
- **Clic izquierdo sobre `link[]`** (no sobre los `__`) abre. Con Shift, Ctrl o Alt no abre
  (es seleccionar). Si la ruta no existe o es relativa, no hace nada. Solo se abren rutas
  completas (`X:\...` o `\\servidor\...`).
  - `.stdoer .py .txt .md .js .json .xml .ini .log .csv` → pestaña de Notepad++.
  - Carpeta → Explorador.
  - ⛔ **Nunca ejecuta nada.** Ejecutables, scripts, accesos directos y archivos con macros
    (`.exe .bat .cmd .ps1 .vbs .lnk .msi .jar .docm .xlsm` y muchos más; la lista completa
    está en `src\Enlaces.cpp`), y los archivos sin extensión, **muestran su carpeta** en el
    Explorador. Para el resto (`.ods`, `.xlsx`, `.html`, `.pdf`...) se usa el programa que
    Windows tenga asignado, salvo que esa asociación ejecute el propio archivo o no exista
    (entonces también se muestra su carpeta).
- **Comprobar si existe no congela Notepad++:** se hace en otro hilo con límite de 300 ms
  (recuadro) y 1 s (clic). Una consulta que no termina no se repite durante 60 s.
- **Aviso tras «Reemplazar todo»:** ese comando de Notepad++ no respeta el estilo no
  modificable y apaga los avisos de edición; al terminar manda `NPPN_GLOBALMODIFIED`. El
  plugin guarda la lista de rutas de cada documento y, si tras un «Reemplazar todo» aparece
  una ruta distinta, **muestra esos enlaces** y pone una anotación bajo la línea («Se cambió la
  ruta de este enlace sin que se viera... Ctrl+Z deshace»). Se quita al siguiente cambio del
  texto o al cambiar de documento. Ver «Límites conocidos».
- **Direcciones web:** `__link[https://...]` o `__link[http://...]` se abre en el navegador
  predeterminado. ⛔ **Solo `http` y `https`.** Cualquier otro esquema (`javascript:`, `file:`,
  `ms-settings:`, `mailto:`, `ftp:`, `steam:`, `shell:`, ...) **nunca se abre**, tampoco desde
  el menú: Windows podría asociarlo a un programa que ejecute algo. Una dirección es válida si
  es `http(s)://` + algo (con servidor), sin espacios, caracteres de control, ni `"` `<` `>` `^`
  `` ` `` `\`, y de menos de 2048 caracteres; si no, se trata como esquema rechazado. Un
  esquema son 2 o más caracteres (`C:` es una unidad, no un esquema). El recuadro muestra la
  dirección tal cual (sin tocar la red, no se comprueba si existe) o dice «no se abre: solo
  se abren direcciones http y https». Reglas de ocultar y de mostrar al tocar, las mismas.
- **Menú del clic derecho** (el plugin intercepta `WM_CONTEXTMENU` en las dos vistas de
  Scintilla; si no hay enlace bajo el mouse, el mensaje sigue y sale el menú normal de
  Notepad++; con la tecla Menú / Mayús+F10 se usa el cursor de texto):
  - sobre `__link[...]` (cualquier carácter del enlace, de `_` a `]`): **Abrir** (en gris si
    no se puede: ruta relativa o inexistente, esquema rechazado), **Abrir carpeta
    contenedora** (solo rutas; si el archivo no existe pero su carpeta sí, abre la carpeta;
    en gris si es relativa), **Desactivar enlace**;
  - sobre `_link[...]` (un solo `_` que no sigue a otra letra, cifra ni `_`, para que
    `mi_link[0]` no cuente): **Activar enlace**;
  - **Abrir** sigue las mismas reglas que el clic; nunca ejecuta nada;
  - **Activar / Desactivar** agregan o quitan un `_` y son **lo único que el plugin escribe en
    el documento**: una sola acción de deshacer (un Ctrl+Z), solo a pedido, y solo si el texto
    sigue siendo el esperado; en gris con el documento de solo lectura. Límite: un enlace
    pegado a una letra (`ver__link[x]`) se puede desactivar pero su `_link[x]` ya no cuenta
    como «desactivado» para el menú (por la regla de la letra de antes).
- Salvo Activar / Desactivar, el plugin **no escribe nunca en el documento**: solo cambia
  estilos y anotaciones.
- **Colores:** `config\Stdoer.xml` no declara ningún estilo. (En 0.4.0 declaraba un estilo
  `DEFAULT` sin colores y Notepad++ le ponía fondo blanco: en modo oscuro, la sangría y el fin
  de cada línea se veían blancos.) El texto toma los colores del tema; la ruta visible
  (estilo 51) se pinta a medio camino entre el color de texto y el de fondo del tema; el
  color de `link[]` al pasar el mouse es un azul claro sobre fondos oscuros y uno oscuro
  sobre claros. Se recalculan si el tema cambia.
- Estilos de Scintilla usados: 50 ruta oculta, 51 ruta visible, 52 `link[` y `]` (zona
  clicable, *hotspot*). Se aplican solo mientras el documento activo es `.stdoer` y se
  devuelven a la normalidad al salir de él (otro lexer podría usar esos números). Notepad++
  reinicia los estilos (`SCI_STYLECLEARALL`) al cambiar de lenguaje o de tema; el plugin los
  reaplica con los avisos `NPPN_*` y, como red de seguridad, en cada `SCN_UPDATEUI`.

### Límites conocidos de los enlaces

- **Cortar / copiar / pegar** se probaron con el portapapeles real (el script lo guarda y lo
  restaura si es solo texto): 0 cambios ocultos (`tests\seguridad-enlaces.ps1`, 331
  escenarios en total; ejecutarlo con `powershell -STA`, que el portapapeles lo exige).
- **Otro plugin** que reemplace texto por programa (`SCI_REPLACETARGET`) sin pasar por
  «Reemplazar todo» puede cambiar una ruta oculta sin aviso. «Reemplazar en archivos» y
  arrastrar y soltar tampoco se probaron.
- Copiar una selección que incluye un enlace copia también su ruta oculta (es parte del texto).
- El texto de la ruta cuenta para Buscar (un hallazgo dentro de una ruta oculta se muestra
  al seleccionarse, por la regla de arriba).
- El recuadro depende del evento de «mouse detenido» de Scintilla (500 ms); la lógica se
  probó por mensaje directo al plugin y el usuario confirmó que aparece con el mouse real
  (2026-10-12).
- El menú se probó con el clic derecho «de verdad» a nivel de mensaje (`WM_CONTEXTMENU` →
  menú emergente real → opción elegida con el teclado); un clic físico del mouse lo hace
  igual, pero queda para prueba manual.
- No se probó en la vista secundaria de Notepad++ (el plugin engancha las dos).

## Requisitos

- Visual Studio Build Tools 2026 en `D:\VisualStudio\BuildTools` (MSVC + Windows SDK).
- Notepad++ 8.8.2 x64 portátil en `npp-portable\` (no está en git; ver más abajo).

## Compilar

Desde esta carpeta, en PowerShell o `cmd`:

```
.\compilar.cmd
```

Deja `build\Stdoer.dll` (borra solo `build\obj\` y la DLL anterior; el resto de `build\`,
donde las pruebas dejan sus copias, no se toca). Todo el código fuente es
**UTF-8** y se compila con `/utf-8`; sin eso `cl` lo lee con la página de códigos local
(1252) y los acentos salen mal (`ó` → `Ã³`).

## Instalar en el Notepad++ portátil

```
.\instalar.cmd
```

Copia dos archivos al portátil; **nunca** toca `C:\Program Files\Notepad++` ni
`%AppData%\Notepad++`:

| Origen | Destino | Para qué |
| --- | --- | --- |
| `build\Stdoer.dll` | `npp-portable\plugins\Stdoer\Stdoer.dll` | el plugin y el lexer |
| `config\Stdoer.xml` | `npp-portable\plugins\Config\Stdoer.xml` | registra el lexer `stdoer` y la extensión `.stdoer` |

El XML es obligatorio: Notepad++ no carga un lexer externo sin un `<NombreDeLaDll>.xml`
en `plugins\Config\`. Sus estilos están vacíos a propósito (todo se ve como texto plano).

## Abrir el portátil para probar

```
.\npp-portable\notepad++.exe -multiInst -nosession
```

- `-multiInst`: si tu Notepad++ real está abierto, sin esto el portátil le pasa el
  control a esa instancia en vez de abrirse solo.
- `-nosession`: no restaura ni guarda sesión.
- El portátil es portátil por `doLocalConf.xml`: su configuración vive en
  `npp-portable\`, no en `%AppData%`.
- Para probar, usa **copias** de tus documentos, nunca los originales.

Para ver un `.py` y su copia `.stdoer` lado a lado (izquierda `.py`, derecha `.stdoer`):

```
.\tests\abrir-lado-a-lado.ps1 -Base pruebas\muestra-personal
```

(`-Base` es la ruta sin extensión; deben existir `<Base>.py` y `<Base>.stdoer`. También
`-Izq <archivo> -Der <archivo>` para dos archivos cualesquiera.)

Demostración de enlaces y de llaves (genera `pruebas\demo-enlaces.stdoer` con rutas a
`tests\objetivos\` y lo abre junto a la demostración de llaves):

```
.\tests\abrir-demo-enlaces.ps1
```

## Pruebas

Todas usan **solo el portátil**, una instancia a la vez (`tests\herramientas-npp.ps1` cierra
cualquier portátil de stdoer que haya quedado abierto y lo arranca sin el cuadro de error de
Windows). Escriben sus copias en `build\<nombre>\`.

```
.\tests\comparar-plegado.ps1
```

Abre en el portátil cada caso de `tests\casos\*.py` (inventados) y cada `pruebas\*.py`
(copias personales, fuera del git) como `.py` y como `.stdoer`, y compara línea por línea
el nivel de plegado que da Notepad++ (`SCI_GETFOLDLEVEL`). Debe dar **todo idéntico**
(código de salida 0). Escribe el detalle en `build\cmp\reporte.txt`. Cualquier cambio al
lexer debe volver a pasar esta prueba. (Los casos con llaves **sin pareja**, en medio de
frases o con enlaces también van aquí: deben seguir idénticos a Python.)

```
.\tests\verificar-llaves.ps1
```

Abre cada `tests\llaves\*.stdoer` y compara el nivel de **cada línea** con su
`.esperado` (profundidad y `H` = cabecera; razonados a mano, no copiados de la salida; el de
`L23_demo` se fijó revisando la salida línea por línea). Debe dar todo OK.

```
.\tests\editar-llaves.ps1
```

Prueba de edición sobre una copia en memoria: borrar/teclear una llave y comprobar que se
re-pliega todo el documento, también las líneas anteriores al cambio.

```
.\tests\probar-enlaces.ps1
```

Por cada `tests\enlaces\*.stdoer`, el estilo de **cada byte** contra su `.esperado` (mapa a
mano: `l` zona clicable, `h` ruta oculta, `r` ruta visible, `.` otro); atributos de los
estilos; y mostrar/ocultar según el cursor y la selección.

```
.\tests\probar-clic-enlaces.ps1
```

Clic (mouse simulado) y recuadro sobre enlaces a los archivos de `tests\objetivos\`, leyendo
el registro del plugin. Con `STDOER_SIN_SHELL` el plugin anota lo que abriría **sin** llamar a
Windows. Incluye una ruta de red que no responde (el clic debe volver en ~1 s).

```
.\tests\seguridad-enlaces.ps1 [-SinPortapapeles]
```

Barrido de seguridad del texto oculto (331 escenarios con portapapeles, 215 sin él): escribir, Retroceso, Suprimir con el
cursor en cada posición de un enlace, selecciones, reemplazar, «Reemplazar todo» con el diálogo
real, Deshacer/Rehacer. Criterio: ninguna acción cambia la ruta oculta sin que se vea.

```
.\tests\probar-persistencia-enlaces.ps1
```

El ocultamiento sobrevive a cambiar de pestaña, de lenguaje y a reiniciar los estilos.

```
.\tests\probar-temas.ps1
```

Colores del tema: abre el portátil con 8 configuraciones (claro, modo oscuro con dos temas,
Zenburn, Monokai, Obsidian, Solarized-light, Hello Kitty) y luego **cambia de tema en caliente**
desde el Configurador de estilos con el documento abierto. En cada caso **mide** (no mira)
que el fondo y el texto de todos los estilos usados sean los del tema, que la ruta visible sea
el punto medio y que el color al pasar el mouse contraste. Guarda `npp-portable\config.xml` en
`build\config-original.xml` y lo restaura siempre.

```
.\tests\probar-menu.ps1
```

Menú del clic derecho con el camino real (`WM_CONTEXTMENU`, menú emergente de verdad leído
con `MN_GETHMENU`, opción elegida con el teclado): opciones según el tipo de enlace, menú
normal fuera de un enlace, cada opción, Activar/Desactivar con un solo Deshacer, solo lectura
y menú desde el teclado.

```
.\tests\probar-web.ps1
```

Direcciones web y esquemas: ~70 casos (http/https que se abren; `javascript:`, `file:`,
`ms-settings:`, direcciones mal formadas, con caracteres peligrosos o demasiado largas, que
no). Con `STDOER_SIN_SHELL`: ninguna abre nada de verdad.

`pruebas\` está en `.gitignore`: ahí van copias de documentos personales. Nada personal
va en archivos versionados (ni rutas ni nombres de mis documentos). Los archivos de
`tests\objetivos\` son inventados; los scripts que hacen enlaces a ellos calculan la ruta
completa al ejecutarse y escriben el resultado en `build\` o `pruebas\`.

Variables de entorno de prueba (solo las pone el script de pruebas): `STDOER_LOG=<archivo>`
(el plugin anota lo que hace) y `STDOER_SIN_SHELL=1` (no llama a Windows; además habilita el
mensaje privado `NPPM_MSGTOPLUGIN` que usan los tests: 1 = recuadro, 2 = anotar las opciones
del menú, 3 = clic izquierdo, 11..14 = elegir Abrir / Carpeta / Desactivar / Activar).

`tests\unit\correr.cmd` compila y corre pruebas unitarias del analizador de enlaces; hace un
`.exe` suelto que algunos antivirus marcan por heurística: no se usa en el flujo normal (las
mismas reglas se prueban por el portátil).

## Cómo funciona el lexer (para quien lo modifique)

- `src\StdoerLexer.cxx` exporta `GetLexerCount`, `GetLexerName` y `CreateLexer` (la
  interfaz de Lexilla que Notepad++ busca en los plugins). `CreateLexer("stdoer")`
  devuelve una **capa** (`LexerStdoer`) que envuelve el lexer de Python de Lexilla
  (`third_party\lexilla\lexers\LexPython.cxx`, sin modificar) con las propiedades de plegado
  que Notepad++ fija para Python (`fold`, `fold.compact=0`, `fold.quotes.python=1`). A un
  lexer externo nadie se las fija, por eso van aquí. La capa delega todo en Python salvo
  `Lex` y `Fold`.
- **Python no ve las rutas de los enlaces:** el documento que se le entrega es un «documento
  sombra» que reenvía todo al real pero sustituye por `x` los bytes de cada ruta de enlace.
  Así comillas, `#` o `'''` dentro de una ruta no cambian su coloreado ni su plegado.
- **`Lex`:** Python colorea el rango sobre el texto sin rutas; después `EstilarEnlaces` da a
  cada enlace de esas líneas el estilo 52 a `link[` y `]`, y 50 ó 51 a la ruta (51 si el
  cursor o la selección la tocan, o está «expuesta»; estado compartido con el plugin en
  `Enlaces.cpp`). Se devuelve el «estilado hasta» al final del rango para que Scintilla no
  vuelva a pedir lo mismo.
- **Cómo se calcula el plegado (`LexerStdoer::Fold`):** (1) Python calcula el plegado por
  sangría de todo el documento contra el documento sombra, que además anota los niveles en
  vez de escribirlos; (2) `src\Llaves.cpp` mira el texto, empareja las llaves y reescribe los
  niveles con una pila de marcos (región `{ }` o bloque por sangría), dando a cada línea el
  nivel 1024 + marcos que la rodean; (3) se escriben al documento. Sin llaves con pareja se
  escriben los niveles de Python tal cual. Se recalcula **siempre el documento entero**
  (lineal en su tamaño): que una `{` tenga pareja depende de texto lejano, y borrar una
  `}` cambia el plegado de líneas anteriores. Medido con 1,6 MB y 120 000 líneas: ~70 ms por
  tecla, igual que un `.py`.
- Equivalencia con Python sin llaves: el mismo código del lexer de Python, sin modificar
  (`tests\comparar-plegado.ps1`). Ojo: el lexer mide la sangría con **tab = 8 columnas**
  siempre, sin importar el ancho de tab configurado en Notepad++ (así también se comporta
  Python).
- Si se modifica la contracción o los enlaces, hay que volver a pasar las pruebas de `tests\`.
- Límite conocido: el emparejado de llaves es por texto. Si se teclea una `{` al final de una
  línea dentro de una región existente y aún sin su `}`, esa `{` se empareja con la `}` de la
  región y la región original deja de plegarse hasta que se cierre la nueva.

## Reconstruir `npp-portable\`

Es una copia del zip oficial `npp.8.8.2.portable.x64.zip` de
https://github.com/notepad-plus-plus/notepad-plus-plus/releases/tag/v8.8.2
(SHA-256 `26e480873fc2bdf39eaedf936bcaae75430089d802381abad2589060c0ef703d`),
extraída en `npp-portable\`. Está en `.gitignore`.

## Estructura

- `src\Stdoer.cpp` — plugin: menú y puntos de entrada de plugin (propio).
- `src\StdoerLexer.cxx` — puntos de entrada del lexer externo, la capa sobre Python y el
  documento sombra (propio).
- `src\Llaves.h`, `src\Llaves.cpp` — reglas de `{ }`, sin depender de Scintilla (propio).
- `src\Enlaces.h`, `src\Enlaces.cpp` — analizador de enlaces, clasificación de archivos y
  estado compartido, sin depender de Scintilla (propio).
- `src\EnlacesUI.h`, `src\EnlacesUI.cpp` — estilos de la vista, mostrar la ruta, recuadro,
  clic, apertura y aviso tras «Reemplazar todo» (propio).
- `config\Stdoer.xml` — registro del lexer en Notepad++.
- `third_party\plugintemplate\` — cabeceras de interfaz de plugins (GPL v2+, sin
  modificar). `third_party\lexilla\` — Lexilla 5.4.5 (HPND, sin modificar). Origen y
  licencias en `third_party\ORIGEN.md`.
- `compilar.cmd`, `instalar.cmd` — compilar e instalar en el portátil.
- `tests\` — los scripts de prueba, `herramientas-npp.ps1` (ayudantes), los casos inventados
  `casos\`, `llaves\`, `enlaces\`, los archivos de prueba `objetivos\` y `unit\`.
- `build\` — salida de compilación y de pruebas; `pruebas\` — copias personales y demos.
  Ambas fuera del git.
