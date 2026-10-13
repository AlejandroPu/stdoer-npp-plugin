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
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint modo);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO {
        public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inh, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    // Lanza un proceso SIN la bandera CREATE_DEFAULT_ERROR_MODE (que usa Start-Process): así hereda el
    // modo de error de este proceso (sin cuadro "Depurar / Cerrar programa" si el portátil se cae).
    public static int Lanzar(string exe, string argumentos, string carpeta) {
        STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        PROCESS_INFORMATION pi;
        var linea = new StringBuilder("\"" + exe + "\" " + argumentos);
        if (!CreateProcessW(null, linea, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, carpeta, ref si, out pi)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr n, uint t, uint prot);
    [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr n, uint t);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr n, out UIntPtr w);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr n, out UIntPtr r);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
    [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageStr(IntPtr h, uint m, IntPtr w, string s);
    // Ventana de nivel superior del proceso que tiene un control con ese identificador (p. ej. un diálogo).
    public static string Ventanas(uint pid) {
        var sb2 = new StringBuilder();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid) { var c = new StringBuilder(64); var x = new StringBuilder(80); GetClassName(h, c, 64); GetWindowText(h, x, 80);
                sb2.Append(h.ToString() + " vis=" + IsWindowVisible(h) + " cls=" + c + " txt=" + x + "; "); }
            return true; }, IntPtr.Zero);
        return sb2.ToString();
    }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    public static IntPtr BuscarDialogo(uint pid, int idControl) {
        IntPtr hallado = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h) && GetDlgItem(h, idControl) != IntPtr.Zero) { hallado = h; return false; }
            return true; }, IntPtr.Zero);
        return hallado;
    }
    // NPPM_MSGTOPLUGIN: manda un mensaje privado a un plugin (struct CommunicationInfo en memoria remota).
    public static long MensajeAPlugin(IntPtr hNpp, string modulo, int internalMsg, long valor) {
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, (UIntPtr)512, 0x3000, 0x04);
        byte[] b = new byte[512];
        long baseAddr = (long)mem;
        Array.Copy(BitConverter.GetBytes(internalMsg), 0, b, 0, 4);           // internalMsg
        Array.Copy(BitConverter.GetBytes(baseAddr + 128), 0, b, 8, 8);         // srcModuleName
        Array.Copy(BitConverter.GetBytes(baseAddr + 64), 0, b, 16, 8);         // info -> valor
        Array.Copy(BitConverter.GetBytes(valor), 0, b, 64, 8);
        byte[] src = Encoding.Unicode.GetBytes("Pruebas.dll\0"); Array.Copy(src, 0, b, 128, src.Length);
        byte[] dst = Encoding.Unicode.GetBytes(modulo + "\0"); Array.Copy(dst, 0, b, 256, dst.Length);
        UIntPtr n; WriteProcessMemory(proc, mem, b, (UIntPtr)512, out n);
        long r = (long)SendMessage(hNpp, 0x400 + 1000 + 47, (IntPtr)(baseAddr + 256), mem);
        VirtualFreeEx(proc, mem, UIntPtr.Zero, 0x8000);
        return r;
    }
    public static List<IntPtr> Scintillas(IntPtr parent) {
        var r = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => {
            var sb = new StringBuilder(64); GetClassName(h, sb, 64);
            if (sb.ToString() == "Scintilla" && IsWindowVisible(h)) r.Add(h);
            return true; }, IntPtr.Zero);
        return r;
    }
    // --- menús (el de la ventana y los emergentes del propio proceso) ---
    [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetSubMenu(IntPtr m, int i);
    [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr m);
    [DllImport("user32.dll")] public static extern uint GetMenuItemID(IntPtr m, int i);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetMenuString(IntPtr m, uint pos, StringBuilder s, int n, uint flags);
    [DllImport("user32.dll")] static extern uint GetMenuState(IntPtr m, uint pos, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct PUNTO { public int x, y; }
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PUNTO p);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr contexto);
    // "id|texto|estado" por línea (estado: gris / ok), con la sangría del nivel.
    public static string ArbolMenu(IntPtr m, int nivel) {
        var sb = new StringBuilder();
        int n = GetMenuItemCount(m);
        for (int i = 0; i < n; i++) {
            var s = new StringBuilder(200); GetMenuString(m, (uint)i, s, 200, 0x400);
            uint est = GetMenuState(m, (uint)i, 0x400);
            IntPtr sub = GetSubMenu(m, i);
            sb.Append(new string(' ', nivel * 2) + GetMenuItemID(m, i) + "|" + s + "|" + (((est & 3) != 0) ? "gris" : "ok") + "\n");
            if (sub != IntPtr.Zero) sb.Append(ArbolMenu(sub, nivel + 1));
        }
        return sb.ToString();
    }
    // Menú emergente visible (clase #32768) del proceso, o cero.
    public static IntPtr VentanaPopup(uint pid) {
        IntPtr hallado = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(32); GetClassName(h, c, 32);
            if (c.ToString() == "#32768") { hallado = h; return false; }
            return true; }, IntPtr.Zero);
        return hallado;
    }
    public static IntPtr MenuDePopup(IntPtr hPopup) { return SendMessage(hPopup, 0x1E1, IntPtr.Zero, IntPtr.Zero); }  // MN_GETHMENU
    // Controles hijos de una ventana: "id|clase|texto" por línea.
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
    public static string Hijos(IntPtr padre) {
        var sb = new StringBuilder();
        EnumChildWindows(padre, (h, l) => {
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            var x = new StringBuilder(120); GetWindowText(h, x, 120);
            sb.Append(GetDlgCtrlID(h) + "|" + c + "|" + x + "|" + h.ToString() + "\n");
            return true; }, IntPtr.Zero);
        return sb.ToString();
    }
    // Control (a cualquier profundidad) con ese identificador dentro de una ventana, o cero.
    public static IntPtr HijoPorId(IntPtr padre, int id) {
        IntPtr hallado = IntPtr.Zero;
        EnumChildWindows(padre, (h, l) => { if (GetDlgCtrlID(h) == id) { hallado = h; return false; } return true; }, IntPtr.Zero);
        return hallado;
    }
    // Ventana de nivel superior visible del proceso con ese texto de título.
    public static IntPtr VentanaConTitulo(uint pid, string titulo) {
        IntPtr hallado = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            var x = new StringBuilder(200); GetWindowText(h, x, 200);
            if (x.ToString() == titulo) { hallado = h; return false; }
            return true; }, IntPtr.Zero);
        return hallado;
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
$script:ProcNpp = $null; $script:HNpp = [IntPtr]::Zero; $script:VNpp = [IntPtr]::Zero

function Sci([uint32]$m, [int64]$w = 0, [int64]$l = 0) { [int64][NppT]::SendMessage($script:VNpp, $m, [IntPtr]$w, [IntPtr]$l) }
function NppMsg([uint32]$m, [int64]$w = 0, [int64]$l = 0) { [int64][NppT]::SendMessage($script:HNpp, $m, [IntPtr]$w, [IntPtr]$l) }
function SciCadena([uint32]$m, [int64]$w, [string]$s) { [NppT]::SendBytes($script:VNpp, $m, $w, [Text.Encoding]::UTF8.GetBytes($s)) }

# Texto completo del documento activo, como cadena UTF-8.
function SciTexto {
    $n = Sci 2006   # SCI_GETLENGTH
    [long]$ret = 0
    $b = [NppT]::RecibirBytes($script:VNpp, 2182, $n + 1, $n + 1, [ref]$ret)
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

# Cierra cualquier portátil de stdoer que haya quedado abierto (solo los de npp-portable; nunca
# el Notepad++ instalado). Así una prueba que falló a medias no deja instancias acumuladas.
function Npp-CerrarRestos {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'notepad++*' -and $_.Path -like '*\stdoer\npp-portable\*' } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Npp-Abrir([string[]]$Archivos, [string]$Log = '', [hashtable]$Entorno = @{}) {
    Npp-CerrarRestos
    Start-Sleep -Milliseconds 500
    # Si el portátil de prueba se cae, que no muestre el cuadro "Depurar / Cerrar programa"
    # (el modo de error se hereda al proceso hijo; el evento queda en el registro de Windows).
    [void][NppT]::SetErrorMode(0x0001 -bor 0x0002)   # SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX
    $exe = Join-Path $script:Raiz 'npp-portable\notepad++.exe'
    $viejo = @{}
    if ($Log -ne '') { $Entorno['STDOER_LOG'] = $Log; Remove-Item $Log -ErrorAction SilentlyContinue }
    foreach ($k in $Entorno.Keys) { $viejo[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Entorno[$k]) }
    $argsNpp = @('-multiInst', '-nosession') + ($Archivos | ForEach-Object { '"' + $_ + '"' })
    $pidNpp = [NppT]::Lanzar($exe, ($argsNpp -join ' '), (Split-Path $exe))
    $script:ProcNpp = Get-Process -Id $pidNpp
    foreach ($k in $Entorno.Keys) { [Environment]::SetEnvironmentVariable($k, $viejo[$k]) }
    $script:HNpp = [IntPtr]::Zero
    for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $script:ProcNpp.Refresh(); if ($script:ProcNpp.MainWindowHandle -ne [IntPtr]::Zero) { $script:HNpp = $script:ProcNpp.MainWindowHandle; break } }
    if ($script:HNpp -eq [IntPtr]::Zero) { throw 'No apareció la ventana de Notepad++ portátil' }
    [NppT]::Attach($script:HNpp)
    # Aunque el script termine con un error, el portátil que abrió se cierra al salir.
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -MessageData $script:ProcNpp.Id -Action {
        $q = Get-Process -Id $Event.MessageData -ErrorAction SilentlyContinue
        if ($q -and $q.Path -like '*\stdoer\npp-portable\*') { Stop-Process -Id $q.Id -Force }
    } | Out-Null
    for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; if ((NppMsg $NPPM_GETNBOPENFILES) -ge $Archivos.Count) { break } }
    Start-Sleep -Seconds 2
    $sci = [NppT]::Scintillas($script:HNpp)
    $script:VNpp = $sci[0]
    # Los portátiles ven a veces una pestaña vacía "new 1" más: se ignora (se busca por ruta).
}

function Npp-Documentos {
    $n = NppMsg $NPPM_GETNBOPENFILES
    $r = @()
    for ($i = 0; $i -lt $n; $i++) {
        $id = NppMsg $NPPM_GETBUFFERIDFROMPOS $i 0
        [long]$ret = 0
        $b = [NppT]::RecibirBytes($script:HNpp, $NPPM_GETFULLPATHFROMBUFFERID, $id, 1040, [ref]$ret)
        $ruta = if ($ret -gt 0) { [Text.Encoding]::Unicode.GetString($b, 0, [int]($ret * 2)) } else { '' }
        $r += [pscustomobject]@{ Indice = $i; Ruta = $ruta }
    }
    $r
}

function Npp-Activar([int]$indice) { [void](NppMsg $NPPM_ACTIVATEDOC 0 $indice); Start-Sleep -Milliseconds 150 }

# Cierra solo el portátil de stdoer que abrió este script (sin guardar nada).
function Npp-Cerrar {
    [NppT]::Detach()
    if ($script:ProcNpp -and -not $script:ProcNpp.HasExited) {
        if ($script:ProcNpp.Path -like '*\stdoer\npp-portable\*') { Stop-Process -Id $script:ProcNpp.Id -Force }
    }
}


# Reemplazar todo con el diálogo REAL de Notepad++ (Buscar y reemplazar -> "Reemplazar todo"),
# no con mensajes sueltos: así se prueba el camino que usa el usuario.
function Npp-ReemplazarTodoDialogo([string]$buscar, [string]$por) {
    [void](NppMsg $NPPM_MENUCOMMAND 0 43003)    # IDM_SEARCH_REPLACE
    $dlg = [IntPtr]::Zero
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 150
        $dlg = [NppT]::BuscarDialogo([uint32]$script:ProcNpp.Id, 1609)
        if ($dlg -ne [IntPtr]::Zero) { break }
    }
    if ($dlg -eq [IntPtr]::Zero) { throw ('No apareció el diálogo de reemplazar. Ventanas: ' + [NppT]::Ventanas([uint32]$script:ProcNpp.Id)) }
    $cBuscar = [NppT]::GetDlgItem($dlg, 1601); $cPor = [NppT]::GetDlgItem($dlg, 1602); $boton = [NppT]::GetDlgItem($dlg, 1609)
    Start-Sleep -Milliseconds 500
    [void][NppT]::SendMessageStr($cBuscar, 0x000C, [IntPtr]::Zero, $buscar)   # WM_SETTEXT
    [void][NppT]::SendMessageStr($cPor, 0x000C, [IntPtr]::Zero, $por)
    Start-Sleep -Milliseconds 500
    # WM_COMMAND (BN_CLICKED) al diálogo, como un clic en "Reemplazar todo"
    [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr]1609, $boton)
    Start-Sleep -Milliseconds 1500
    # Cerrar como con Esc/Cancelar (IDCANCEL), no con un WM_CLOSE a la fuerza
    [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr]2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800
}


# Los mensajes de mouse sintéticos van en píxeles físicos, pero SCI_POINTXFROMPOSITION & co.
# devuelven píxeles "lógicos" de Scintilla: con la pantalla al 125 % un clic caería una fila
# más abajo. Esta función convierte un punto de la API de Scintilla al lParam de un mensaje de mouse.
function Npp-LParamMouse([int]$x, [int]$y) {
    $dpi = [NppT]::GetDpiForWindow($script:VNpp); if ($dpi -le 0) { $dpi = 96 }
    $f = 96.0 / $dpi
    $xs = [int][Math]::Round($x * $f); $ys = [int][Math]::Round($y * $f)
    [IntPtr](($ys -shl 16) -bor ($xs -band 0xFFFF))
}

# --- menús y clic derecho ---

# Todas las órdenes del menú principal ("id|texto|estado"), para hallar un identificador por su texto.
function Npp-ArbolMenu { [NppT]::ArbolMenu([NppT]::GetMenu($script:HNpp), 0) }

# lParam de un WM_CONTEXTMENU (coordenadas de PANTALLA físicas, que es lo que recibe Notepad++, que
# es consciente de DPI) sobre una posición del documento. Los puntos de la API de Scintilla son
# los del área de cliente; este proceso de pruebas NO es consciente de DPI, así que durante la
# conversión se declara consciente (por hilo) para que ClientToScreen devuelva píxeles físicos.
# Por defecto cae 3 píxeles dentro de la celda del carácter (justo en su borde izquierdo
# Scintilla elige el anterior).
function Npp-LParamPantalla([int64]$pos, [int]$dx = 3, [int]$dy = 3) {
    $p = New-Object NppT+PUNTO
    $p.x = [int](Sci 2164 0 $pos) + $dx     # SCI_POINTXFROMPOSITION
    $p.y = [int](Sci 2165 0 $pos) + $dy     # SCI_POINTYFROMPOSITION
    $antes = [NppT]::SetThreadDpiAwarenessContext([IntPtr](-4))     # PER_MONITOR_AWARE_V2
    [void][NppT]::ClientToScreen($script:VNpp, [ref]$p)
    [void][NppT]::SetThreadDpiAwarenessContext($antes)
    [IntPtr](([int64]($p.y -band 0xFFFF) -shl 16) -bor [int64]($p.x -band 0xFFFF))
}

# Pide el menú contextual de verdad (WM_CONTEXTMENU a la vista) y espera el emergente.
# Devuelve las opciones ("id|texto|estado" por línea) o $null si no apareció ninguno.
# Sin -Elegir se cierra el emergente (WM_CANCELMODE); con -Elegir -Bajar N se pulsa Abajo N veces y Intro.
function Npp-MenuContextual([int64]$pos, [int]$dx = 3, [int]$dy = 3, [int]$Bajar = 0, [switch]$Elegir, [switch]$Teclado) {
    # El envío también se hace con el hilo declarado consciente de DPI: si no, Windows reescala las
    # coordenadas de pantalla del mensaje al pasar de un proceso "no consciente" a uno consciente.
    $lp = if ($Teclado) { [IntPtr](-1) } else { Npp-LParamPantalla $pos $dx $dy }     # -1 = desde el teclado (en el cursor)
    $antes = [NppT]::SetThreadDpiAwarenessContext([IntPtr](-4))
    [void][NppT]::PostMessage($script:VNpp, 0x007B, $script:VNpp, $lp)    # WM_CONTEXTMENU
    [void][NppT]::SetThreadDpiAwarenessContext($antes)
    $pop = [IntPtr]::Zero
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Milliseconds 100; $pop = [NppT]::VentanaPopup([uint32]$script:ProcNpp.Id); if ($pop -ne [IntPtr]::Zero) { break } }
    if ($pop -eq [IntPtr]::Zero) { return $null }
    $items = [NppT]::ArbolMenu([NppT]::MenuDePopup($pop), 0)
    if ($Elegir) {
        for ($k = 0; $k -lt $Bajar; $k++) { [void][NppT]::PostMessage($pop, 0x0100, [IntPtr]0x28, [IntPtr]::Zero); Start-Sleep -Milliseconds 120 }   # VK_DOWN
        [void][NppT]::PostMessage($pop, 0x0100, [IntPtr]0x0D, [IntPtr]::Zero)                                                                         # VK_RETURN
    } else {
        [void][NppT]::SendMessage($script:HNpp, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)                                                              # WM_CANCELMODE a Notepad++: cierra el emergente
    }
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Milliseconds 100; if ([NppT]::VentanaPopup([uint32]$script:ProcNpp.Id) -eq [IntPtr]::Zero) { break } }
    if ([NppT]::VentanaPopup([uint32]$script:ProcNpp.Id) -ne [IntPtr]::Zero) { $items += "(el emergente NO se cerró)`n" }
    Start-Sleep -Milliseconds 200
    return $items
}
