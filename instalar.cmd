@echo off
rem Copia build\Stdoer.dll al Notepad++ PORTATIL (npp-portable\plugins\Stdoer\).
rem Nunca toca C:\Program Files\Notepad++. Uso: instalar.cmd
setlocal
cd /d "%~dp0"
if not exist build\Stdoer.dll ( echo Primero ejecuta compilar.cmd & exit /b 1 )
if not exist npp-portable\notepad++.exe ( echo No se encuentra npp-portable\notepad++.exe & exit /b 1 )
if not exist npp-portable\plugins\Stdoer mkdir npp-portable\plugins\Stdoer
copy /y build\Stdoer.dll npp-portable\plugins\Stdoer\Stdoer.dll >nul || exit /b 1
echo OK: instalado en npp-portable\plugins\Stdoer\Stdoer.dll
