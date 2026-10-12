# Stdoer

Plugin de Notepad++ (C++, DLL x64 Unicode) para el lenguaje propio de los archivos
`.stdoer`. Diseño completo en el proyecto de planeación: `diseno/lenguaje-notepad.md`.

**Estado: 0.1.0 — plugin mínimo.** Solo carga y agrega *Plugins → Stdoer → Acerca de
Stdoer*. Aún no hay lexer, contracción ni enlaces.

## Requisitos

- Visual Studio Build Tools 2026 en `D:\VisualStudio\BuildTools` (MSVC + Windows SDK).
- Notepad++ 8.8.1 x64 portátil en `npp-portable\` (no está en git; ver más abajo).

## Compilar

Desde esta carpeta, en PowerShell o `cmd`:

```
.\compilar.cmd
```

Deja `build\Stdoer.dll`. Falla con mensaje claro si algo no se encuentra.

## Instalar en el Notepad++ portátil

```
.\instalar.cmd
```

Copia la DLL a `npp-portable\plugins\Stdoer\Stdoer.dll`. **Nunca** toca
`C:\Program Files\Notepad++` ni `%AppData%\Notepad++`.

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

## Reconstruir `npp-portable\`

Es una copia del zip oficial `npp.8.8.1.portable.x64.zip` de
https://github.com/notepad-plus-plus/notepad-plus-plus/releases/tag/v8.8.1
(SHA-256 `a123ba8c547f62dcb48617acf8fff928117e7e8bc13b5fa5fd160d7bc9807817`),
extraída en `npp-portable\`. Está en `.gitignore`.

## Estructura

- `src/Stdoer.cpp` — código propio del plugin.
- `third_party/plugintemplate/` — cabeceras de interfaz de la plantilla oficial
  (GPL v2+, sin modificar); origen y licencia en `third_party/ORIGEN.md`.
- `compilar.cmd`, `instalar.cmd` — compilar e instalar en el portátil.
- `build/` — salida de compilación (ignorada por git).
