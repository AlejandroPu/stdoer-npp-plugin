@echo off
rem Sets VC to the path of vcvars64.bat of the most recent Visual Studio (or Build Tools) that
rem has the x64 C++ compiler. It looks for it with vswhere, which comes with the Visual
rem Studio installer. To use another one: set STDOER_VCVARS=<path of vcvars64.bat>.
rem Usage: call find-vc.cmd
set "VC=%STDOER_VCVARS%"
if defined VC goto :eof
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto :eof
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VC=%%i\VC\Auxiliary\Build\vcvars64.bat"
set "VSWHERE="
