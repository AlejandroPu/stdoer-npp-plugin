# Origin of third-party code

`plugintemplate/` contains **unmodified** copies of the interface headers of the official
Notepad++ plugin template:

- Repository: https://github.com/npp-plugins/plugintemplate
- Commit: `27b7077ba89766b3a5a136a3d71af3a0cccc7d2a` (2026-09-27)
- Files: `PluginInterface.h`, `Notepad_plus_msgs.h`, `Scintilla.h`, `Sci_Position.h`
- License: GNU GPL v2 or later (`plugintemplate/license.txt`). Copyright (C) Don HO and
  the Scintilla authors (Scintilla license in the header of `Scintilla.h`).

Nothing else from the template was copied; `src/Stdoer.cpp` is own code.

## `lexilla/` — Lexilla 5.4.5 / Scintilla (0.3.0)

**Unmodified** copies of the files used by the Python lexer, taken from the Notepad++
**v8.8.2** source code (the same Lexilla that ships with that version):

- Repository: https://github.com/notepad-plus-plus/notepad-plus-plus, tag `v8.8.2`
  (`lexilla/` and `scintilla/include/`). Lexilla version: see `lexilla/version.txt` (545).
- `lexilla/lexers/LexPython.cxx` — the Python lexer.
- `lexilla/lexlib/*` — common lexer library (all `.cxx`/`.h` files except
  `CatalogueModules.h`).
- `lexilla/include/{Lexilla.h,SciLexer.h}` and `lexilla/scintilla_include/{ILexer.h,
  Sci_Position.h,Scintilla.h,ScintillaTypes.h}`.
- License: HPND ("License for Lexilla, Scintilla, and SciTE", Neil Hodgson), in
  `lexilla/License.txt`. It allows use, copying and modification with a copyright notice.

The `stdoer` lexer (`src/StdoerLexer.cxx`, own code) **uses `LexPython.cxx` as is** and
only changes the name, the extension and the folding properties. If a copy in `lexilla/`
is ever modified, record it here.

History: in 0.2.0 it was taken from tag `v8.8.1` (Lexilla 5.4.4). When moving to 8.8.2
(0.3.0) the 37 files were downloaded again; 14 changed (lexlib, SciLexer.h, Scintilla*.h,
version.txt and LexPython.cxx, whose difference is code style).
