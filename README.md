# Stdoer

Plugin de Notepad++ (C++, DLL x64 Unicode) para el lenguaje propio de los archivos
`.stdoer`. Diseño completo en el proyecto de planeación: `diseno/lenguaje-notepad.md`.

**Estado: 0.2.0.** Hace dos cosas:

- Menú *Plugins → Stdoer → Acerca de Stdoer*.
- **Lexer externo `stdoer`**, asociado a la extensión `.stdoer`: contracción por sangría
  idéntica a la de los `.py` y sin colores. Aún no hay contracción con `{ }` ni enlaces.

## Requisitos

- Visual Studio Build Tools 2026 en `D:\VisualStudio\BuildTools` (MSVC + Windows SDK).
- Notepad++ 8.8.2 x64 portátil en `npp-portable\` (no está en git; ver más abajo).

## Compilar

Desde esta carpeta, en PowerShell o `cmd`:

```
.\compilar.cmd
```

Deja `build\Stdoer.dll` (borra y rehace todo `build\`). Todo el código fuente es
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
Un archivo `.stdoer` abierto en el portátil queda con el lexer `stdoer` (comprobado por
mensajes: el tipo de lenguaje del documento es el del primer lexer externo, distinto del
de Python).

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

(`-Base` es la ruta sin extensión; deben existir `<Base>.py` y `<Base>.stdoer`.)

## Pruebas

```
.\tests\comparar-plegado.ps1
```

Abre en el portátil cada caso de `tests\casos\*.py` (inventados) y cada `pruebas\*.py`
(copias personales, fuera del git) como `.py` y como `.stdoer`, y compara línea por línea
el nivel de plegado que da Notepad++ (`SCI_GETFOLDLEVEL`). Debe dar **todo idéntico**
(código de salida 0). Escribe el detalle en `build\cmp\reporte.txt`. Cualquier cambio al
lexer debe volver a pasar esta prueba.

`pruebas\` está en `.gitignore`: ahí van copias de documentos personales.

## Cómo funciona el lexer (para quien lo modifique)

- `src\StdoerLexer.cxx` exporta `GetLexerCount`, `GetLexerName` y `CreateLexer` (la
  interfaz de Lexilla que Notepad++ busca en los plugins). `CreateLexer("stdoer")`
  devuelve el lexer de Python de Lexilla (`third_party\lexilla\lexers\LexPython.cxx`,
  sin modificar) con las propiedades de plegado que Notepad++ fija para Python
  (`fold`, `fold.compact=0`, `fold.quotes.python=1`). A un lexer externo nadie se las
  fija, por eso van aquí.
- Equivalencia con Python **por construcción**: es el mismo código. Ojo: el lexer mide
  la sangría con **tab = 8 columnas** siempre, sin importar el ancho de tab configurado
  en Notepad++ (así también se comporta Python).
- Si se modifica la contracción (p. ej. para añadir `{ }`), hay que volver a justificar la
  equivalencia con `tests\comparar-plegado.ps1`.

## Reconstruir `npp-portable\`

Es una copia del zip oficial `npp.8.8.2.portable.x64.zip` de
https://github.com/notepad-plus-plus/notepad-plus-plus/releases/tag/v8.8.2
(SHA-256 `26e480873fc2bdf39eaedf936bcaae75430089d802381abad2589060c0ef703d`),
extraída en `npp-portable\`. Está en `.gitignore`.

## Estructura

- `src\Stdoer.cpp` — plugin: menú y puntos de entrada de plugin (propio).
- `src\StdoerLexer.cxx` — puntos de entrada del lexer externo (propio).
- `config\Stdoer.xml` — registro del lexer en Notepad++.
- `third_party\plugintemplate\` — cabeceras de interfaz de plugins (GPL v2+, sin
  modificar). `third_party\lexilla\` — Lexilla 5.4.5 (HPND, sin modificar). Origen y
  licencias en `third_party\ORIGEN.md`.
- `compilar.cmd`, `instalar.cmd` — compilar e instalar en el portátil.
- `tests\` — `comparar-plegado.ps1`, `abrir-lado-a-lado.ps1` y `casos\` (inventados).
- `build\` — salida de compilación; `pruebas\` — copias personales. Ambas fuera del git.
