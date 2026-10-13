@echo off
rem Compila Stdoer.dll (x64, Unicode) en build\. Uso: compilar.cmd
rem Todo el codigo fuente es UTF-8 (/utf-8); sin eso cl lo lee con la pagina de
rem codigos local (1252) y los acentos de los textos salen mal.
setlocal
call "%~dp0buscar-vc.cmd"
if not exist "%VC%" ( echo No se encuentra Visual Studio con C++ x64: ver buscar-vc.cmd & exit /b 1 )
call "%VC%" >nul 2>&1
if errorlevel 1 ( echo Fallo al cargar el entorno del compilador & exit /b 1 )
cd /d "%~dp0"
if exist build\obj rmdir /s /q build\obj
if exist build\Stdoer.dll del /q build\Stdoer.dll
mkdir build\obj

set "COMUN=/nologo /std:c++17 /EHsc /O2 /utf-8 /validate-charset /DUNICODE /D_UNICODE /DWIN32_LEAN_AND_MEAN /c"
set "LX=third_party\lexilla"

rem 1) Plugin y enlaces (cabeceras de la plantilla de Notepad++). Propio: /W4 sin avisos.
cl %COMUN% /W4 /I third_party\plugintemplate /Fo:build\obj\ src\Stdoer.cpp src\EnlacesUI.cpp src\Enlaces.cpp
if errorlevel 1 ( echo COMPILACION FALLIDA & exit /b 1 )

rem 2) Lexer (Lexilla). StdoerLexer.cxx y Llaves.cpp son propios (/W4); el resto es de terceros.
cl %COMUN% /W4 /DSCI_LEXER /I %LX%\scintilla_include /I %LX%\include /I %LX%\lexlib /Fo:build\obj\ src\StdoerLexer.cxx src\Llaves.cpp
if errorlevel 1 ( echo COMPILACION FALLIDA & exit /b 1 )
cl %COMUN% /W3 /D_CRT_SECURE_NO_WARNINGS /DSCI_LEXER /I %LX%\scintilla_include /I %LX%\include /I %LX%\lexlib /Fo:build\obj\ %LX%\lexers\LexPython.cxx %LX%\lexlib\Accessor.cxx %LX%\lexlib\CharacterCategory.cxx %LX%\lexlib\CharacterSet.cxx %LX%\lexlib\DefaultLexer.cxx %LX%\lexlib\InList.cxx %LX%\lexlib\LexAccessor.cxx %LX%\lexlib\LexerBase.cxx %LX%\lexlib\LexerModule.cxx %LX%\lexlib\LexerSimple.cxx %LX%\lexlib\PropSetSimple.cxx %LX%\lexlib\StyleContext.cxx %LX%\lexlib\WordList.cxx
if errorlevel 1 ( echo COMPILACION FALLIDA & exit /b 1 )

link /nologo /DLL /OUT:build\Stdoer.dll build\obj\*.obj user32.lib shell32.lib shlwapi.lib comctl32.lib
if errorlevel 1 ( echo ENLACE FALLIDO & exit /b 1 )
del /q build\Stdoer.exp build\Stdoer.lib 2>nul
echo OK: build\Stdoer.dll
