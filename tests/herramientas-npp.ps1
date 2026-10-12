# Ayudantes comunes para las pruebas que manejan el Notepad++ PORTÁTIL desde fuera
# (se cargan con:  . "$PSScriptRoot\herramientas-npp.ps1").
#
# Los mensajes de Scintilla con punteros (leer texto, buscar, reemplazar...) no cruzan entre
# procesos tal cual; aquí se copian a memoria reservada dentro del proceso de Notepad++.
# Solo se usa el portátil de npp-portable (-multiInst -nosession); nunca la instalación real.

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class NppT {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr n, uint t, uint prot);
    [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr n, uint t);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr n, out UIntPtr w);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr n, out UIntPtr r);

    public static List<IntPtr> Scintillas(IntPtr parent) {
        var r = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => {
            var sb = new StringBuilder(64); GetClassName(h, sb, 64);
            if (sb.ToString() == "Scintilla" && IsWindowVisible(h)) r.Add(h);
            return true; }, IntPtr.Zero);
        return r;
    }
    static IntPtr proc = IntPtr.Zero;
    public static void Attach(IntPtr hwnd) {
        uint pid; GetWindowThreadProcessId(hwnd, out pid);
        proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid);
    }
    public static void Detach() { if (proc != IntPtr.Zero) { CloseHandle(proc); proc = IntPtr.Zero; } }
    // Envía un mensaje cuyo lParam es una cadena (bytes, terminada en cero) copiada al proceso remoto.
    public static long SendBytes(IntPtr h, uint m, long w, byte[] datos) {
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, (UIntPtr)(datos.Length + 1), 0x3000, 0x04);
        byte[] con = new byte[datos.Length + 1]; Array.Copy(datos, con, datos.Length);
        UIntPtr n; WriteProcessMemory(proc, mem, con, (UIntPtr)con.Length, out n);
        long r = (long)SendMessage(h, m, (IntPtr)w, mem);
        VirtualFreeEx(proc, mem, UIntPtr.Zero, 0x8000);
        return r;
    }
    // Envía un mensaje cuyo lParam es un búfer de salida de `tam` bytes; devuelve su contenido.
    public static byte[] RecibirBytes(IntPtr h, uint m, long w, int tam, out long retorno) {
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, (UIntPtr)(tam + 1), 0x3000, 0x04);
        retorno = (long)SendMessage(h, m, (IntPtr)w, mem);
        byte[] b = new byte[tam + 1]; UIntPtr n; ReadProcessMemory(proc, mem, b, (UIntPtr)(tam + 1), out n);
        VirtualFreeEx(proc, mem, UIntPtr.Zero, 0x8000);
        return b;
    }
}
'@

$script:NPPMSG = 0x400 + 1000
$script:NPPM_GETNBOPENFILES = $NPPMSG + 7
$script:NPPM_ACTIVATEDOC = $NPPMSG + 28
$script:NPPM_GETFULLPATHFROMBUFFERID = $NPPMSG + 58
$script:NPPM_GETBUFFERIDFROMPOS = $NPPMSG + 59
$script:NPPM_GETCURRENTBUFFERID = $NPPMSG + 60
$script:NPPM_GETBUFFERLANGTYPE = $NPPMSG + 64
$script:NPPM_MENUCOMMAND = $NPPMSG + 48
$script:P = $null; $script:H = [IntPtr]::Zero; $script:V = [IntPtr]::Zero

function Sci([uint32]$m, [int64]$w = 0, [int64]$l = 0) { [int64][NppT]::SendMessage($script:V, $m, [IntPtr]$w, [IntPtr]$l) }
function NppMsg([uint32]$m, [int64]$w = 0, [int64]$l = 0) { [int64][NppT]::SendMessage($script:H, $m, [IntPtr]$w, [IntPtr]$l) }
function SciCadena([uint32]$m, [int64]$w, [string]$s) { [NppT]::SendBytes($script:V, $m, $w, [Text.Encoding]::UTF8.GetBytes($s)) }

# Texto completo del documento activo, como cadena UTF-8.
function SciTexto {
    $n = Sci 2006   # SCI_GETLENGTH
    [long]$ret = 0
    $b = [NppT]::RecibirBytes($script:V, 2182, $n + 1, $n + 1, [ref]$ret)
    [Text.Encoding]::UTF8.GetString($b, 0, [int]$n)
}

# Mapa de estilos de cada byte del documento activo: cada estilo -> un carácter
# (l = enlace "link[" o "]" (52), h = ruta oculta (50), r = ruta visible (51), . = otro).
function SciMapaEstilos([string]$texto) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($texto)
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10 -or $bytes[$i] -eq 13) { [void]$sb.Append("`n"); continue }
        $e = Sci 2010 $i   # SCI_GETSTYLEAT
        switch ($e) { 50 { [void]$sb.Append('h') } 51 { [void]$sb.Append('r') } 52 { [void]$sb.Append('l') } default { [void]$sb.Append('.') } }
    }
    $sb.ToString()
}

function Npp-Abrir([string[]]$Archivos, [string]$Log = '', [hashtable]$Entorno = @{}) {
    $exe = Join-Path $script:Raiz 'npp-portable\notepad++.exe'
    $viejo = @{}
    if ($Log -ne '') { $Entorno['STDOER_LOG'] = $Log; Remove-Item $Log -ErrorAction SilentlyContinue }
    foreach ($k in $Entorno.Keys) { $viejo[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Entorno[$k]) }
    $argsNpp = @('-multiInst', '-nosession') + ($Archivos | ForEach-Object { '"' + $_ + '"' })
    $script:P = Start-Process $exe -ArgumentList $argsNpp -PassThru
    foreach ($k in $Entorno.Keys) { [Environment]::SetEnvironmentVariable($k, $viejo[$k]) }
    $script:H = [IntPtr]::Zero
    for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $script:P.Refresh(); if ($script:P.MainWindowHandle -ne [IntPtr]::Zero) { $script:H = $script:P.MainWindowHandle; break } }
    if ($script:H -eq [IntPtr]::Zero) { throw 'No apareció la ventana de Notepad++ portátil' }
    [NppT]::Attach($script:H)
    for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; if ((NppMsg $NPPM_GETNBOPENFILES) -ge $Archivos.Count) { break } }
    Start-Sleep -Seconds 2
    $sci = [NppT]::Scintillas($script:H)
    $script:V = $sci[0]
    # Los portátiles ven a veces una pestaña vacía "new 1" más: se ignora (se busca por ruta).
}

function Npp-Documentos {
    $n = NppMsg $NPPM_GETNBOPENFILES
    $r = @()
    for ($i = 0; $i -lt $n; $i++) {
        $id = NppMsg $NPPM_GETBUFFERIDFROMPOS $i 0
        [long]$ret = 0
        $b = [NppT]::RecibirBytes($script:H, $NPPM_GETFULLPATHFROMBUFFERID, $id, 1040, [ref]$ret)
        $ruta = if ($ret -gt 0) { [Text.Encoding]::Unicode.GetString($b, 0, [int]($ret * 2)) } else { '' }
        $r += [pscustomobject]@{ Indice = $i; Ruta = $ruta }
    }
    $r
}

function Npp-Activar([int]$indice) { [void](NppMsg $NPPM_ACTIVATEDOC 0 $indice); Start-Sleep -Milliseconds 150 }

# Cierra solo el portátil de stdoer que abrió este script (sin guardar nada).
function Npp-Cerrar {
    [NppT]::Detach()
    if ($script:P -and -not $script:P.HasExited) {
        if ($script:P.Path -like '*\stdoer\npp-portable\*') { Stop-Process -Id $script:P.Id -Force }
    }
}
