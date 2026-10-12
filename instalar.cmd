@echo off
rem Copia al Notepad++ PORTATIL: la DLL y el XML del lexer.
rem   build\Stdoer.dll   -> npp-portable\plugins\Stdoer\Stdoer.dll
rem   config\Stdoer.xml  -> npp-portable\plugins\Config\Stdoer.xml
rem Nunca toca C:\Program Files\Notepad++. Uso: instalar.cmd
setlocal
cd /d "%~dp0"
if not exist build\Stdoer.dll ( echo Primero ejecuta compilar.cmd & exit /b 1 )
if not exist npp-portable\notepad++.exe ( echo No se encuentra npp-portable\notepad++.exe & exit /b 1 )
if not exist npp-portable\plugins\Stdoer mkdir npp-portable\plugins\Stdoer
if not exist npp-portable\plugins\Config mkdir npp-portable\plugins\Config
copy /y build\Stdoer.dll npp-portable\plugins\Stdoer\Stdoer.dll >nul || exit /b 1
copy /y config\Stdoer.xml npp-portable\plugins\Config\Stdoer.xml >nul || exit /b 1
echo OK: instalado en npp-portable\plugins (Stdoer\Stdoer.dll y Config\Stdoer.xml)
