# Origen de código de terceros

`plugintemplate/` contiene copias **sin modificar** de las cabeceras de interfaz de
la plantilla oficial de plugins de Notepad++:

- Repositorio: https://github.com/npp-plugins/plugintemplate
- Commit: `27b7077ba89766b3a5a136a3d71af3a0cccc7d2a` (2026-09-27)
- Archivos: `PluginInterface.h`, `Notepad_plus_msgs.h`, `Scintilla.h`, `Sci_Position.h`
- Licencia: GNU GPL v2 o posterior (`plugintemplate/license.txt`). Copyright (C) Don HO
  y los autores de Scintilla (licencia de Scintilla en la cabecera de `Scintilla.h`).

Nada más de la plantilla se copió; `src/Stdoer.cpp` es código propio.

## `lexilla/` — Lexilla 5.4.4 / Scintilla (0.2.0)

Copias **sin modificar** de los archivos que usa el lexer de Python, tomadas del código
fuente de Notepad++ **v8.8.1** (el mismo Lexilla que trae esa versión):

- Repositorio: https://github.com/notepad-plus-plus/notepad-plus-plus, etiqueta `v8.8.1`
  (`lexilla/` y `scintilla/include/`). Versión de Lexilla: ver `lexilla/version.txt` (544).
- `lexilla/lexers/LexPython.cxx` — el lexer de Python.
- `lexilla/lexlib/*` — biblioteca común de lexers (todos los `.cxx`/`.h` salvo
  `CatalogueModules.h`).
- `lexilla/include/{Lexilla.h,SciLexer.h}` y `lexilla/scintilla_include/{ILexer.h,
  Sci_Position.h,Scintilla.h,ScintillaTypes.h}`.
- Licencia: HPND ("License for Lexilla, Scintilla, and SciTE", Neil Hodgson), en
  `lexilla/License.txt`. Permite usar, copiar y modificar con aviso de copyright.

El lexer `stdoer` (`src/StdoerLexer.cxx`, código propio) **usa `LexPython.cxx` tal cual**
y solo cambia el nombre, la extensión y las propiedades de plegado. Si algún día se
modifica una copia de `lexilla/`, anotarlo aquí.
