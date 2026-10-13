@echo off
rem Builds and runs the unit tests (they do not need Notepad++). Usage: tests\unit\run.cmd
setlocal
call "%~dp0..\..\find-vc.cmd"
if not exist "%VC%" ( echo Visual Studio with x64 C++ not found: see find-vc.cmd & exit /b 1 )
call "%VC%" >nul 2>&1
cd /d "%~dp0\..\.."
if not exist build\unit mkdir build\unit
cl /nologo /std:c++17 /EHsc /W4 /utf-8 /validate-charset /I src /Fo:build\unit\ /Fe:build\unit\links_test.exe tests\unit\links_test.cpp src\Links.cpp
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
build\unit\links_test.exe
