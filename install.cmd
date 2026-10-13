@echo off
rem Copies to the PORTABLE Notepad++: the DLL and the lexer's XML.
rem   build\Stdoer.dll   -> npp-portable\plugins\Stdoer\Stdoer.dll
rem   config\Stdoer.xml  -> npp-portable\plugins\Config\Stdoer.xml
rem It never touches C:\Program Files\Notepad++. Usage: install.cmd
setlocal
cd /d "%~dp0"
if not exist build\Stdoer.dll ( echo Run build.cmd first & exit /b 1 )
if not exist npp-portable\notepad++.exe ( echo npp-portable\notepad++.exe not found & exit /b 1 )
if not exist npp-portable\plugins\Stdoer mkdir npp-portable\plugins\Stdoer
if not exist npp-portable\plugins\Config mkdir npp-portable\plugins\Config
copy /y build\Stdoer.dll npp-portable\plugins\Stdoer\Stdoer.dll >nul || exit /b 1
copy /y config\Stdoer.xml npp-portable\plugins\Config\Stdoer.xml >nul || exit /b 1
echo OK: installed in npp-portable\plugins (Stdoer\Stdoer.dll and Config\Stdoer.xml)
