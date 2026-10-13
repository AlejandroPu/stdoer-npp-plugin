@echo off
rem Deja en VC la ruta de vcvars64.bat del Visual Studio (o Build Tools) mas reciente que
rem tenga el compilador de C++ x64. Lo busca con vswhere, que viene con el instalador de
rem Visual Studio. Para usar otro: set STDOER_VCVARS=<ruta de vcvars64.bat>.
rem Uso: call buscar-vc.cmd
set "VC=%STDOER_VCVARS%"
if defined VC goto :eof
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto :eof
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VC=%%i\VC\Auxiliary\Build\vcvars64.bat"
set "VSWHERE="
