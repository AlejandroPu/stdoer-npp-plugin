@echo off
rem Builds Stdoer.dll (x64, Unicode) in build\. Usage: build.cmd
rem All the source code is UTF-8 (/utf-8); without it cl reads it with the local code page
rem (1252) and accented characters in the texts come out wrong.
setlocal
call "%~dp0find-vc.cmd"
if not exist "%VC%" ( echo Visual Studio with x64 C++ not found: see find-vc.cmd & exit /b 1 )
call "%VC%" >nul 2>&1
if errorlevel 1 ( echo Failed to load the compiler environment & exit /b 1 )
cd /d "%~dp0"
if exist build\obj rmdir /s /q build\obj
if exist build\Stdoer.dll del /q build\Stdoer.dll
mkdir build\obj

set "COMMON=/nologo /std:c++17 /EHsc /O2 /utf-8 /validate-charset /DUNICODE /D_UNICODE /DWIN32_LEAN_AND_MEAN /c"
set "LX=third_party\lexilla"

rem 1) Plugin and links (Notepad++ template headers). Our own code: /W4 with no warnings.
cl %COMMON% /W4 /I third_party\plugintemplate /Fo:build\obj\ src\Stdoer.cpp src\LinksUI.cpp src\Links.cpp
if errorlevel 1 ( echo COMPILATION FAILED & exit /b 1 )

rem 2) Lexer (Lexilla). StdoerLexer.cxx and Braces.cpp are our own (/W4); the rest is third-party.
cl %COMMON% /W4 /DSCI_LEXER /I %LX%\scintilla_include /I %LX%\include /I %LX%\lexlib /Fo:build\obj\ src\StdoerLexer.cxx src\Braces.cpp
if errorlevel 1 ( echo COMPILATION FAILED & exit /b 1 )
cl %COMMON% /W3 /D_CRT_SECURE_NO_WARNINGS /DSCI_LEXER /I %LX%\scintilla_include /I %LX%\include /I %LX%\lexlib /Fo:build\obj\ %LX%\lexers\LexPython.cxx %LX%\lexlib\Accessor.cxx %LX%\lexlib\CharacterCategory.cxx %LX%\lexlib\CharacterSet.cxx %LX%\lexlib\DefaultLexer.cxx %LX%\lexlib\InList.cxx %LX%\lexlib\LexAccessor.cxx %LX%\lexlib\LexerBase.cxx %LX%\lexlib\LexerModule.cxx %LX%\lexlib\LexerSimple.cxx %LX%\lexlib\PropSetSimple.cxx %LX%\lexlib\StyleContext.cxx %LX%\lexlib\WordList.cxx
if errorlevel 1 ( echo COMPILATION FAILED & exit /b 1 )

link /nologo /DLL /OUT:build\Stdoer.dll build\obj\*.obj user32.lib shell32.lib shlwapi.lib comctl32.lib
if errorlevel 1 ( echo LINK FAILED & exit /b 1 )
del /q build\Stdoer.exp build\Stdoer.lib 2>nul
echo OK: build\Stdoer.dll
