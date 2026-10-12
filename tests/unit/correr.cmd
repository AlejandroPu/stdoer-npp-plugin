@echo off
rem Compila y corre las pruebas unitarias (no necesitan Notepad++). Uso: tests\unit\correr.cmd
setlocal
set "VC=D:\VisualStudio\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
call "%VC%" >nul 2>&1
cd /d "%~dp0\..\.."
if not exist build\unit mkdir build\unit
cl /nologo /std:c++17 /EHsc /W4 /utf-8 /validate-charset /I src /Fo:build\unit\ /Fe:build\unit\enlaces_prueba.exe tests\unit\enlaces_prueba.cpp src\Enlaces.cpp
if errorlevel 1 ( echo COMPILACION FALLIDA & exit /b 1 )
build\unit\enlaces_prueba.exe
