# Stdoer — development

Notepad++ plugin (C++, x64 Unicode DLL) for the custom language of `.stdoer` files. What
it is and how to install it → [`README.md`](README.md). This guide is for anyone who
builds, tests or modifies it.

> **Note:** in 0.5.0 the plugin's menus and messages, the code comments, the test
> scripts and some file names are still in Spanish. Translating them is planned for the
> next version. Menu items are given below in English, with the current Spanish label in
> parentheses.

**Status: 0.5.0.** It does the following:

- Menu *Plugins → Stdoer → About Stdoer* (*Acerca de Stdoer*).
- **External lexer `stdoer`**, associated with the `.stdoer` extension, with no colors of
  its own (it uses those of the active Notepad++ theme, light, dark or any other):
  - folding by indentation identical to that of `.py` files;
  - **folding with `{ }`** (rules below).
- **Links `__link[path]`**: hidden path, tooltip on mouse hover and a click that opens
  (rules below). `http://` and `https://` addresses open in the browser.
- **Right-click menu on a link**: Open, Open containing folder, Disable link (on
  `_link[...]`: Enable link). Outside a link, the normal menu.

## Folding with `{ }`

- `{` as the **last** character of a line (not counting spaces or tabs) opens a region;
  `}` as the **first** character of a line closes it. Any other brace does nothing (so
  prose does not fold by accident). Only the text is looked at: quotes, `#` and
  apostrophes do not count. A line can close and open (`} else {`).
- **They are matched with a stack** (each `}` closes the most recent open `{`), without
  looking at indentation. An unmatched `}` is ignored. **An unmatched `{` is ignored
  too:** a brace mistake never hides more than it should, and an unclosed `{` cannot
  swallow the rest of the document. Only a `{` that already has its `}` counts.
- **The `}` line is hidden with its region:** when folded, only the `{` line is visible.
  Exception: in `} else {` (closes one region and opens another) the line cannot be hidden
  with the first region and be the header of the second at the same time; it stays
  **visible**, outside the first, and is the header of the second.
- Inside a region, folding by indentation works; indentation is compared only between
  lines of the same region (a line indented less than the `{` does not leave the region).
- A region with only the `}` below it folds by hiding that `}`.
- Without matched braces, the document folds exactly like a `.py` file.

## Links `__link[path]`

- **What a link is:** `__link[` + path + `]`, on a single line. The closing `]` is the one
  that balances the brackets (the path can contain `[ ]`). Several per line. With a single
  `_` (`_link[...]`) or unclosed, it is plain text: it does nothing. Only the text is
  looked at.
- **The path is hidden**: you see `__link[]` (invisible Scintilla style). While hidden,
  the path is **read-only** (Backspace, Delete, typing over a selection, cut and paste do
  not touch it).
- **The path shows up by itself** (in gray) while the cursor touches it (right after `[`,
  inside, or right before `]`) or a selection touches it. That way, any change to a path
  is made in plain view. To edit a path: delete one `_` (it becomes `_link[...]`, which is
  shown in full), edit, type the `_` again.
- **Tooltip on mouse hover** over the link: the full path; if it does not exist, it says
  so; if it is relative, it says so; if the check does not respond, it says so.
- **Left click on `link[]`** (not on the `__`) opens. With Shift, Ctrl or Alt it does not
  open (that is selecting). If the path does not exist or is relative, nothing happens.
  Only full paths are opened (`X:\...` or `\\server\...`).
  - `.stdoer .py .txt .md .js .json .xml .ini .log .csv` → Notepad++ tab.
  - Folder → File Explorer.
  - ⛔ **It never runs anything.** Executables, scripts, shortcuts and files with macros
    (`.exe .bat .cmd .ps1 .vbs .lnk .msi .jar .docm .xlsm` and many more; the full list
    is in `src\Enlaces.cpp`), and files without an extension, **show their folder** in
    File Explorer. Everything else (`.ods`, `.xlsx`, `.html`, `.pdf`...) uses the program
    Windows has assigned, unless that association runs the file itself or does not exist
    (then its folder is shown too).
- **Checking whether a path exists does not freeze Notepad++:** it runs on another thread
  with a limit of 300 ms (tooltip) and 1 s (click). A query that does not finish is not
  repeated for 60 s.
- **Warning after "Replace All":** that Notepad++ command ignores the read-only style and
  turns off modification notifications; when it finishes it sends `NPPN_GLOBALMODIFIED`.
  The plugin keeps the list of paths of each document and, if a different path shows up
  after a "Replace All", it **shows those links** and adds an annotation below the line
  (currently in Spanish: "the path of this link was changed without being visible...
  Ctrl+Z undoes it"). It is removed on the next text change or when switching documents.
  See "Known link limitations".
- **Web addresses:** `__link[https://...]` or `__link[http://...]` opens in the default
  browser. ⛔ **Only `http` and `https`.** Any other scheme (`javascript:`, `file:`,
  `ms-settings:`, `mailto:`, `ftp:`, `steam:`, `shell:`, ...) **is never opened**, not even
  from the menu: Windows could associate it with a program that runs something. An address
  is valid if it is `http(s)://` + something (with a host), with no spaces, control
  characters, or `"` `<` `>` `^` `` ` `` `\`, and shorter than 2048 characters; otherwise it
  is treated as a rejected scheme. A scheme is 2 or more characters (`C:` is a drive, not a
  scheme). The tooltip shows the address as is (without touching the network; whether it
  exists is not checked) or says that it is not opened because only http and https
  addresses are opened. The rules for hiding and showing on touch are the same.
- **Right-click menu** (the plugin intercepts `WM_CONTEXTMENU` in both Scintilla views; if
  there is no link under the mouse, the message goes on and the normal Notepad++ menu
  appears; with the Menu key / Shift+F10 the text cursor is used):
  - on `__link[...]` (any character of the link, from `_` to `]`): **Open** (*Abrir*;
    grayed out if it cannot open: relative or missing path, rejected scheme), **Open
    containing folder** (*Abrir carpeta contenedora*; paths only; if the file does not
    exist but its folder does, it opens the folder; grayed out if relative), **Disable
    link** (*Desactivar enlace*);
  - on `_link[...]` (a single `_` that does not follow another letter, digit or `_`, so
    that `my_link[0]` does not count): **Enable link** (*Activar enlace*);
  - **Open** follows the same rules as the click; it never runs anything;
  - **Enable / Disable** add or remove a `_` and are **the only thing the plugin writes to
    the document**: a single undo action (one Ctrl+Z), only on request, and only if the
    text is still the expected one; grayed out when the document is read-only. Limitation:
    a link attached to a letter (`see__link[x]`) can be disabled, but its `_link[x]` no
    longer counts as "disabled" for the menu (because of the letter rule above).
- Apart from Enable / Disable, the plugin **never writes to the document**: it only
  changes styles and annotations.
- **Colors:** `config\Stdoer.xml` declares no style. (In 0.4.0 it declared a `DEFAULT`
  style without colors, and Notepad++ gave it a white background: in dark mode the
  indentation and the end of each line looked white.) Text takes the theme colors; the
  visible path (style 51) is painted halfway between the theme's text and background
  colors; the color of `link[]` on mouse hover is a light blue on dark backgrounds and a
  dark one on light backgrounds. They are recalculated if the theme changes.
- Scintilla styles used: 50 hidden path, 51 visible path, 52 `link[` and `]` (clickable
  area, *hotspot*). They are applied only while the active document is `.stdoer` and are
  restored when leaving it (another lexer could use those numbers). Notepad++ resets the
  styles (`SCI_STYLECLEARALL`) when changing language or theme; the plugin reapplies them
  on the `NPPN_*` notifications and, as a safety net, on every `SCN_UPDATEUI`.

### Known link limitations

- **Cut / copy / paste** were tested with the real clipboard (the script saves it and
  restores it if it holds only text): 0 hidden changes (`tests\seguridad-enlaces.ps1`, 331
  scenarios in total; run it with `powershell -STA`, which the clipboard requires).
- **Another plugin** that replaces text programmatically (`SCI_REPLACETARGET`) without
  going through "Replace All" can change a hidden path without warning. "Replace in Files"
  and drag and drop were not tested either.
- Copying a selection that includes a link also copies its hidden path (it is part of the
  text).
- The path text counts for Find (a match inside a hidden path is shown when selected,
  because of the rule above).
- The tooltip depends on Scintilla's "mouse dwell" event (500 ms); the logic was tested
  by sending a message directly to the plugin, and it was checked by hand that it appears
  with the real mouse.
- The menu was tested with a "real" right click at the message level (`WM_CONTEXTMENU` →
  real popup menu → option chosen with the keyboard); a physical mouse click does the
  same, but that remains a manual test.
- It was not tested in the secondary Notepad++ view (the plugin hooks both).

## Requirements

- Visual Studio or its Build Tools, with C++ x64 (MSVC + Windows SDK); tested with Build
  Tools 2026. `compilar.cmd` finds it by itself with `vswhere` (see `buscar-vc.cmd`); to
  use another one: `set STDOER_VCVARS=<path to vcvars64.bat>`.
- Portable Notepad++ 8.8.2 x64 in `npp-portable\` (not in git; see below).

## Building

From this folder, in PowerShell or `cmd`:

```
.\compilar.cmd
```

It produces `build\Stdoer.dll` (it only deletes `build\obj\` and the previous DLL; the
rest of `build\`, where the tests leave their copies, is not touched). All source code is
**UTF-8** and is compiled with `/utf-8`; without it, `cl` reads it with the local code page
(1252) and accented characters come out wrong (`ó` → `Ã³`).

## Installing in the portable Notepad++

```
.\instalar.cmd
```

It copies two files to the portable copy; it **never** touches
`C:\Program Files\Notepad++` or `%AppData%\Notepad++`:

| Source | Destination | Purpose |
| --- | --- | --- |
| `build\Stdoer.dll` | `npp-portable\plugins\Stdoer\Stdoer.dll` | the plugin and the lexer |
| `config\Stdoer.xml` | `npp-portable\plugins\Config\Stdoer.xml` | registers the `stdoer` lexer and the `.stdoer` extension |

The XML is required: Notepad++ does not load an external lexer without a
`<DllName>.xml` in `plugins\Config\`. Its styles are empty on purpose (everything looks
like plain text).

## Opening the portable copy for testing

```
.\npp-portable\notepad++.exe -multiInst -nosession
```

- `-multiInst`: if your real Notepad++ is open, without this the portable copy hands
  control over to that instance instead of opening on its own.
- `-nosession`: does not restore or save a session.
- The portable copy is portable because of `doLocalConf.xml`: its settings live in
  `npp-portable\`, not in `%AppData%`.
- For testing, use **copies** of your documents, never the originals.

To see a `.py` file and its `.stdoer` copy side by side (left `.py`, right `.stdoer`):

```
.\tests\abrir-lado-a-lado.ps1 -Base pruebas\muestra-personal
```

(`-Base` is the path without extension; `<Base>.py` and `<Base>.stdoer` must exist. Also
`-Izq <file> -Der <file>` for any two files.)

Links and braces demo (generates `pruebas\demo-enlaces.stdoer` with paths to
`tests\objetivos\` and opens it next to the braces demo):

```
.\tests\abrir-demo-enlaces.ps1
```

## Tests

They all use **only the portable copy**, one instance at a time (`tests\herramientas-npp.ps1`
closes any stdoer portable copy left open and starts it without the Windows error dialog).
They write their copies to `build\<name>\`.

```
.\tests\comparar-plegado.ps1
```

Opens in the portable copy each case in `tests\casos\*.py` (made up) and each
`pruebas\*.py` (personal copies, outside git) as `.py` and as `.stdoer`, and compares,
line by line, the fold level Notepad++ gives (`SCI_GETFOLDLEVEL`). Everything must be
**identical** (exit code 0). It writes the details to `build\cmp\reporte.txt`. Any change
to the lexer must pass this test again. (The cases with **unmatched** braces, braces in
the middle of sentences or with links also go here: they must stay identical to Python.)

```
.\tests\verificar-llaves.ps1
```

Opens each `tests\llaves\*.stdoer` and compares the level of **every line** with its
`.esperado` (depth and `H` = header; reasoned by hand, not copied from the output; the one
for `L23_demo` was set by reviewing the output line by line). Everything must be OK.

```
.\tests\editar-llaves.ps1
```

Editing test on an in-memory copy: delete/type a brace and check that the whole document
is refolded, including the lines before the change.

```
.\tests\probar-enlaces.ps1
```

For each `tests\enlaces\*.stdoer`, the style of **every byte** against its `.esperado`
(hand-made map: `l` clickable area, `h` hidden path, `r` visible path, `.` other); style
attributes; and show/hide depending on the cursor and the selection.

```
.\tests\probar-clic-enlaces.ps1
```

Click (simulated mouse) and tooltip on links to the files in `tests\objetivos\`, reading
the plugin's log. With `STDOER_SIN_SHELL` the plugin logs what it would open **without**
calling Windows. It includes a network path that does not respond (the click must return
in ~1 s).

```
.\tests\seguridad-enlaces.ps1 [-SinPortapapeles]
```

Safety sweep of the hidden text (331 scenarios with the clipboard, 215 without it):
typing, Backspace, Delete with the cursor at every position of a link, selections,
replace, "Replace All" with the real dialog, Undo/Redo. Criterion: no action changes the
hidden path without it being visible.

```
.\tests\probar-persistencia-enlaces.ps1
```

Hiding survives switching tabs, switching language and resetting the styles.

```
.\tests\probar-temas.ps1
```

Theme colors: opens the portable copy with 8 configurations (light, dark mode with two
themes, Zenburn, Monokai, Obsidian, Solarized-light, Hello Kitty) and then **switches
theme live** from the Style Configurator with the document open. In each case it
**measures** (does not eyeball) that the background and text of every style used are the
theme's, that the visible path is the midpoint, and that the hover color contrasts. It
saves `npp-portable\config.xml` to `build\config-original.xml` and always restores it.

```
.\tests\probar-menu.ps1
```

Right-click menu through the real path (`WM_CONTEXTMENU`, real popup menu read with
`MN_GETHMENU`, option chosen with the keyboard): options by link type, normal menu
outside a link, each option, Enable/Disable with a single Undo, read-only, and the menu
from the keyboard.

```
.\tests\probar-web.ps1
```

Web addresses and schemes: ~70 cases (http/https that open; `javascript:`, `file:`,
`ms-settings:`, malformed addresses, with dangerous characters or too long, that do not).
With `STDOER_SIN_SHELL`: none actually opens anything.

`pruebas\` is in `.gitignore`: copies of personal documents go there. Nothing personal
goes into versioned files (no paths or names of personal documents). The files in
`tests\objetivos\` are made up; the scripts that create links to them compute the full
path at run time and write the result to `build\` or `pruebas\`.

Test environment variables (only the test scripts set them): `STDOER_LOG=<file>` (the
plugin logs what it does) and `STDOER_SIN_SHELL=1` (it does not call Windows; it also
enables the private `NPPM_MSGTOPLUGIN` message the tests use: 1 = tooltip, 2 = log the
menu options, 3 = left click, 11..14 = choose Open / Folder / Disable / Enable).

`tests\unit\correr.cmd` builds and runs unit tests of the link parser; it creates a
standalone `.exe` that some antivirus programs flag heuristically: it is not used in the
normal workflow (the same rules are tested through the portable copy).

## How the lexer works (for anyone modifying it)

- `src\StdoerLexer.cxx` exports `GetLexerCount`, `GetLexerName` and `CreateLexer` (the
  Lexilla interface Notepad++ looks for in plugins). `CreateLexer("stdoer")` returns a
  **layer** (`LexerStdoer`) that wraps Lexilla's Python lexer
  (`third_party\lexilla\lexers\LexPython.cxx`, unmodified) with the folding properties
  Notepad++ sets for Python (`fold`, `fold.compact=0`, `fold.quotes.python=1`). Nobody
  sets them for an external lexer, so they are set here. The layer delegates everything
  to Python except `Lex` and `Fold`.
- **Python does not see link paths:** the document it receives is a "shadow document"
  that forwards everything to the real one but replaces the bytes of each link path with
  `x`. That way quotes, `#` or `'''` inside a path do not change its coloring or folding.
- **`Lex`:** Python colors the range over the text without paths; then `EstilarEnlaces`
  gives each link in those lines style 52 for `link[` and `]`, and 50 or 51 for the path
  (51 if the cursor or the selection touches it, or it is "exposed"; state shared with the
  plugin in `Enlaces.cpp`). The "styled up to" position is returned at the end of the
  range so that Scintilla does not ask for the same thing again.
- **How folding is computed (`LexerStdoer::Fold`):** (1) Python computes folding by
  indentation for the whole document against the shadow document, which records the
  levels instead of writing them; (2) `src\Llaves.cpp` looks at the text, matches the
  braces and rewrites the levels with a stack of frames (a `{ }` region or an indentation
  block), giving each line the level 1024 + the frames around it; (3) they are written to
  the document. Without matched braces, Python's levels are written as they are. The
  **whole document is always** recomputed (linear in its size): whether a `{` has a match
  depends on distant text, and deleting a `}` changes the folding of earlier lines.
  Measured with 1.6 MB and 120,000 lines: ~70 ms per keystroke, the same as a `.py` file.
- Equivalence with Python without braces: the same Python lexer code, unmodified
  (`tests\comparar-plegado.ps1`). Note: the lexer always measures indentation with
  **tab = 8 columns**, regardless of the tab width set in Notepad++ (Python behaves the
  same way).
- If folding or links are modified, the tests in `tests\` must be passed again.
- Known limitation: brace matching is text-based. If you type a `{` at the end of a line
  inside an existing region and it has no `}` yet, that `{` is matched with the region's
  `}`, and the original region stops folding until the new one is closed.

## Rebuilding `npp-portable\`

It is a copy of the official zip `npp.8.8.2.portable.x64.zip` from
https://github.com/notepad-plus-plus/notepad-plus-plus/releases/tag/v8.8.2
(SHA-256 `26e480873fc2bdf39eaedf936bcaae75430089d802381abad2589060c0ef703d`),
extracted into `npp-portable\`. It is in `.gitignore`.

## Structure

- `src\Stdoer.cpp` — plugin: menu and plugin entry points (own code).
- `src\StdoerLexer.cxx` — external lexer entry points, the layer over Python and the
  shadow document (own code).
- `src\Llaves.h`, `src\Llaves.cpp` — `{ }` rules, independent of Scintilla (own code).
- `src\Enlaces.h`, `src\Enlaces.cpp` — link parser, file classification and shared state,
  independent of Scintilla (own code).
- `src\EnlacesUI.h`, `src\EnlacesUI.cpp` — view styles, showing the path, tooltip, click,
  opening and the warning after "Replace All" (own code).
- `config\Stdoer.xml` — lexer registration in Notepad++.
- `third_party\plugintemplate\` — plugin interface headers (GPL v2+, unmodified).
  `third_party\lexilla\` — Lexilla 5.4.5 (HPND, unmodified). Origin and licenses in
  [`third_party\ORIGIN.md`](third_party/ORIGIN.md).
- `compilar.cmd`, `instalar.cmd` — build and install in the portable copy;
  `buscar-vc.cmd` — finds the compiler.
- [`LICENSE`](LICENSE) — GNU GPL v2.
- `tests\` — the test scripts, `herramientas-npp.ps1` (helpers), the made-up cases
  `casos\`, `llaves\`, `enlaces\`, the test files `objetivos\` and `unit\`.
- `build\` — build and test output; `pruebas\` — personal copies and demos. Both outside
  git.
