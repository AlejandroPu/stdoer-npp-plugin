# Stdoer

Plugin de Notepad++ (C++, DLL x64 Unicode) para el lenguaje propio de los archivos
`.stdoer`. Diseño completo en el proyecto de planeación: `diseno/lenguaje-notepad.md`.

**Estado: 0.3.0.** Hace dos cosas:

- Menú *Plugins → Stdoer → Acerca de Stdoer*.
- **Lexer externo `stdoer`**, asociado a la extensión `.stdoer`, sin colores:
  - contracción por sangría idéntica a la de los `.py`;
  - **contracción con `{ }`** (reglas abajo).
  Aún no hay enlaces.

## Contracción con `{ }`

- `{` como **último** carácter de una línea (sin contar espacios ni tabs) abre una región;
  `}` como **primer** carácter de una línea la cierra. Cualquier otra llave no hace nada
  (así la prosa no se contrae por accidente). Solo se mira el texto: comillas, `#` y
  apóstrofes no cuentan. Una línea puede cerrar y abrir (`} sino {`).
- **Se emparejan por pila** (cada `}` cierra la `{` abierta más reciente), sin mirar la
  sangría. Una `}` sin pareja se ignora. **Una `{` sin `}` pareja también se ignora:** un
  error de llaves nunca esconde más de la cuenta, y una `{` sin cerrar no puede tragarse el
  resto del documento. Solo cuenta una `{` que ya tenga su `}`.
- La línea `}` queda **fuera** de la región: al contraer se ve `Titulo {` y luego `}`.
- Dentro de una región la contracción por sangría funciona; la sangría se compara solo
  entre líneas de la misma región (una línea menos sangrada que la `{` no saca de la región).
- Una región vacía (`{` y `}` seguidas) no deja un pliegue sin nada que esconder.
- Sin llaves con pareja, el documento se contrae exactamente como un `.py`.

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
lexer debe volver a pasar esta prueba. (Los casos con llaves **sin pareja** o en medio de
frases también van aquí: deben seguir idénticos a Python.)

```
.\tests\verificar-llaves.ps1
```

Abre cada `tests\llaves\*.stdoer` y compara el nivel de **cada línea** con su
`.esperado` (profundidad y `H` = cabecera; razonados a mano, no copiados de la salida).
Debe dar todo OK. Escribe `build\llaves\reporte.txt`.

```
.\tests\editar-llaves.ps1
```

Prueba de edición sobre una copia en memoria: borrar/teclear una llave y comprobar que se
re-pliega todo el documento, también las líneas anteriores al cambio. Al terminar cierra
su propio portátil sin guardar (es una copia en `build\`).

`pruebas\` está en `.gitignore`: ahí van copias de documentos personales. Nada personal
va en archivos versionados (ni rutas ni nombres de mis documentos).

## Cómo funciona el lexer (para quien lo modifique)

- `src\StdoerLexer.cxx` exporta `GetLexerCount`, `GetLexerName` y `CreateLexer` (la
  interfaz de Lexilla que Notepad++ busca en los plugins). `CreateLexer("stdoer")`
  devuelve el lexer de Python de Lexilla (`third_party\lexilla\lexers\LexPython.cxx`,
  sin modificar) con las propiedades de plegado que Notepad++ fija para Python
  (`fold`, `fold.compact=0`, `fold.quotes.python=1`). A un lexer externo nadie se las
  fija, por eso van aquí.
  Lo que devuelve `CreateLexer` no es el lexer de Python directo sino una **capa**
  (`LexerStdoer`) que lo envuelve y le delega todo salvo `Fold`.
- **Cómo se calcula el plegado (`LexerStdoer::Fold`):** (1) Python calcula el plegado por
  sangría de todo el documento contra un documento «sombra» que anota los niveles en vez de
  escribirlos; (2) `src\Llaves.cpp` mira el texto, empareja las llaves y reescribe los
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
- Si se modifica la contracción, hay que volver a pasar las tres pruebas de `tests\`.
- Límite conocido: el emparejado es por texto. Si se teclea una `{` al final de una línea
  dentro de una región existente y aún sin su `}`, esa `{` se empareja con la `}` de la
  región y la región original deja de plegarse hasta que se cierre la nueva.

## Reconstruir `npp-portable\`

Es una copia del zip oficial `npp.8.8.2.portable.x64.zip` de
https://github.com/notepad-plus-plus/notepad-plus-plus/releases/tag/v8.8.2
(SHA-256 `26e480873fc2bdf39eaedf936bcaae75430089d802381abad2589060c0ef703d`),
extraída en `npp-portable\`. Está en `.gitignore`.

## Estructura

- `src\Stdoer.cpp` — plugin: menú y puntos de entrada de plugin (propio).
- `src\StdoerLexer.cxx` — puntos de entrada del lexer externo y la capa sobre Python (propio).
- `src\Llaves.h`, `src\Llaves.cpp` — reglas de `{ }`, sin depender de Scintilla (propio).
- `config\Stdoer.xml` — registro del lexer en Notepad++.
- `third_party\plugintemplate\` — cabeceras de interfaz de plugins (GPL v2+, sin
  modificar). `third_party\lexilla\` — Lexilla 5.4.5 (HPND, sin modificar). Origen y
  licencias en `third_party\ORIGEN.md`.
- `compilar.cmd`, `instalar.cmd` — compilar e instalar en el portátil.
- `tests\` — `comparar-plegado.ps1`, `verificar-llaves.ps1`, `editar-llaves.ps1`,
  `abrir-lado-a-lado.ps1`, y los casos inventados `casos\` y `llaves\`.
- `build\` — salida de compilación; `pruebas\` — copias personales. Ambas fuera del git.
