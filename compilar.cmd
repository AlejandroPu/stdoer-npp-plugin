@echo off
rem Compila Stdoer.dll (x64, Unicode) en build\. Uso: compilar.cmd
setlocal
set "VC=D:\VisualStudio\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VC%" ( echo No se encuentra %VC% & exit /b 1 )
call "%VC%" >nul 2>&1
if errorlevel 1 ( echo Fallo al cargar el entorno del compilador & exit /b 1 )
cd /d "%~dp0"
if not exist build mkdir build
cl /nologo /std:c++17 /EHsc /O2 /W4 /DUNICODE /D_UNICODE /DWIN32_LEAN_AND_MEAN ^
   /I third_party\plugintemplate /LD src\Stdoer.cpp ^
   /Fo:build\ /Fe:build\Stdoer.dll /link /NOLOGO user32.lib
if errorlevel 1 ( echo COMPILACION FALLIDA & exit /b 1 )
del /q build\Stdoer.exp build\Stdoer.lib 2>nul
echo OK: build\Stdoer.dll
