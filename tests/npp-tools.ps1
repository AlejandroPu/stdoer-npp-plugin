# Common helpers for the tests that drive the PORTABLE Notepad++ from outside
# (loaded with:  . "$PSScriptRoot\npp-tools.ps1").
#
# Scintilla messages with pointers (reading text, searching, replacing...) do not cross between
# processes as they are; here they are copied to memory allocated inside the Notepad++ process.
# Only the portable copy in npp-portable is used (-multiInst -nosession); never the real installation.

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
    [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO {
        public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inh, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    // Starts a process WITHOUT the CREATE_DEFAULT_ERROR_MODE flag (which Start-Process uses): that way it
    // inherits this process's error mode (no "Debug / Close program" box if the portable copy crashes).
    public static int Launch(string exe, string arguments, string folder) {
        STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        PROCESS_INFORMATION pi;
        var line = new StringBuilder("\"" + exe + "\" " + arguments);
        if (!CreateProcessW(null, line, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, folder, ref si, out pi)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
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
    // Lists the top-level windows of the process: "handle vis=... cls=... txt=...".
    public static string Windows(uint pid) {
        var sb2 = new StringBuilder();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid) { var c = new StringBuilder(64); var x = new StringBuilder(80); GetClassName(h, c, 64); GetWindowText(h, x, 80);
                sb2.Append(h.ToString() + " vis=" + IsWindowVisible(h) + " cls=" + c + " txt=" + x + "; "); }
            return true; }, IntPtr.Zero);
        return sb2.ToString();
    }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    // Visible top-level window of the process that has a control with that identifier (e.g. a dialog).
    public static IntPtr FindDialog(uint pid, int controlId) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h) && GetDlgItem(h, controlId) != IntPtr.Zero) { found = h; return false; }
            return true; }, IntPtr.Zero);
        return found;
    }
    // NPPM_MSGTOPLUGIN: sends a private message to a plugin (CommunicationInfo struct in remote memory).
    public static long MessageToPlugin(IntPtr hNpp, string module, int internalMsg, long value) {
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, (UIntPtr)512, 0x3000, 0x04);
        byte[] b = new byte[512];
        long baseAddr = (long)mem;
        Array.Copy(BitConverter.GetBytes(internalMsg), 0, b, 0, 4);           // internalMsg
        Array.Copy(BitConverter.GetBytes(baseAddr + 128), 0, b, 8, 8);         // srcModuleName
        Array.Copy(BitConverter.GetBytes(baseAddr + 64), 0, b, 16, 8);         // info -> value
        Array.Copy(BitConverter.GetBytes(value), 0, b, 64, 8);
        byte[] src = Encoding.Unicode.GetBytes("Tests.dll\0"); Array.Copy(src, 0, b, 128, src.Length);
        byte[] dst = Encoding.Unicode.GetBytes(module + "\0"); Array.Copy(dst, 0, b, 256, dst.Length);
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
    // --- menus (the window's and the popups of the process itself) ---
    [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetSubMenu(IntPtr m, int i);
    [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr m);
    [DllImport("user32.dll")] public static extern uint GetMenuItemID(IntPtr m, int i);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetMenuString(IntPtr m, uint pos, StringBuilder s, int n, uint flags);
    [DllImport("user32.dll")] static extern uint GetMenuState(IntPtr m, uint pos, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    // "id|text|state" per line (state: gray / ok), indented by level.
    public static string MenuTree(IntPtr m, int level) {
        var sb = new StringBuilder();
        int n = GetMenuItemCount(m);
        for (int i = 0; i < n; i++) {
            var s = new StringBuilder(200); GetMenuString(m, (uint)i, s, 200, 0x400);
            uint st = GetMenuState(m, (uint)i, 0x400);
            IntPtr sub = GetSubMenu(m, i);
            sb.Append(new string(' ', level * 2) + GetMenuItemID(m, i) + "|" + s + "|" + (((st & 3) != 0) ? "gray" : "ok") + "\n");
            if (sub != IntPtr.Zero) sb.Append(MenuTree(sub, level + 1));
        }
        return sb.ToString();
    }
    // Visible popup menu (class #32768) of the process, or zero.
    public static IntPtr PopupWindow(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(32); GetClassName(h, c, 32);
            if (c.ToString() == "#32768") { found = h; return false; }
            return true; }, IntPtr.Zero);
        return found;
    }
    public static IntPtr PopupMenu(IntPtr hPopup) { return SendMessage(hPopup, 0x1E1, IntPtr.Zero, IntPtr.Zero); }  // MN_GETHMENU
    // Child controls of a window: "id|class|text|handle" per line.
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
    public static string Children(IntPtr parent) {
        var sb = new StringBuilder();
        EnumChildWindows(parent, (h, l) => {
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            var x = new StringBuilder(120); GetWindowText(h, x, 120);
            sb.Append(GetDlgCtrlID(h) + "|" + c + "|" + x + "|" + h.ToString() + "\n");
            return true; }, IntPtr.Zero);
        return sb.ToString();
    }
    // Control (at any depth) with that identifier inside a window, or zero.
    public static IntPtr ChildById(IntPtr parent, int id) {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, l) => { if (GetDlgCtrlID(h) == id) { found = h; return false; } return true; }, IntPtr.Zero);
        return found;
    }
    // Visible top-level window of the process with that title text.
    public static IntPtr WindowWithTitle(uint pid, string title) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            var x = new StringBuilder(200); GetWindowText(h, x, 200);
            if (x.ToString() == title) { found = h; return false; }
            return true; }, IntPtr.Zero);
        return found;
    }
    static IntPtr proc = IntPtr.Zero;
    public static void Attach(IntPtr hwnd) {
        uint pid; GetWindowThreadProcessId(hwnd, out pid);
        proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid);
    }
    public static void Detach() { if (proc != IntPtr.Zero) { CloseHandle(proc); proc = IntPtr.Zero; } }
    // Sends a message whose lParam is a string (bytes, zero-terminated) copied to the remote process.
    public static long SendBytes(IntPtr h, uint m, long w, byte[] data) {
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, (UIntPtr)(data.Length + 1), 0x3000, 0x04);
        byte[] padded = new byte[data.Length + 1]; Array.Copy(data, padded, data.Length);
        UIntPtr n; WriteProcessMemory(proc, mem, padded, (UIntPtr)padded.Length, out n);
        long r = (long)SendMessage(h, m, (IntPtr)w, mem);
        VirtualFreeEx(proc, mem, UIntPtr.Zero, 0x8000);
        return r;
    }
    // Sends a message whose lParam is an output buffer of `size` bytes; returns its contents.
    public static byte[] ReceiveBytes(IntPtr h, uint m, long w, int size, out long returned) {
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, (UIntPtr)(size + 1), 0x3000, 0x04);
        returned = (long)SendMessage(h, m, (IntPtr)w, mem);
        byte[] b = new byte[size + 1]; UIntPtr n; ReadProcessMemory(proc, mem, b, (UIntPtr)(size + 1), out n);
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
function SciString([uint32]$m, [int64]$w, [string]$s) { [NppT]::SendBytes($script:VNpp, $m, $w, [Text.Encoding]::UTF8.GetBytes($s)) }

# Full text of the active document, as a UTF-8 string.
function SciText {
    $n = Sci 2006   # SCI_GETLENGTH
    [long]$ret = 0
    $b = [NppT]::ReceiveBytes($script:VNpp, 2182, $n + 1, $n + 1, [ref]$ret)
    [Text.Encoding]::UTF8.GetString($b, 0, [int]$n)
}

# Style map of each byte of the active document: each style -> one character
# (l = link "link[" or "]" (52), h = hidden path (50), r = visible path (51), . = other).
function SciStyleMap([string]$text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10 -or $bytes[$i] -eq 13) { [void]$sb.Append("`n"); continue }
        $e = Sci 2010 $i   # SCI_GETSTYLEAT
        switch ($e) { 50 { [void]$sb.Append('h') } 51 { [void]$sb.Append('r') } 52 { [void]$sb.Append('l') } default { [void]$sb.Append('.') } }
    }
    $sb.ToString()
}

# Closes any stdoer portable copy left open (only those in npp-portable; never the installed
# Notepad++). That way a test that failed halfway does not leave instances piling up.
function Npp-CloseLeftovers {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'notepad++*' -and $_.Path -like '*\stdoer\npp-portable\*' } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Npp-Open([string[]]$Files, [string]$Log = '', [hashtable]$Env = @{}) {
    Npp-CloseLeftovers
    Start-Sleep -Milliseconds 500
    # If the test portable copy crashes, it must not show the "Debug / Close program" box
    # (the error mode is inherited by the child process; the event stays in the Windows log).
    [void][NppT]::SetErrorMode(0x0001 -bor 0x0002)   # SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX
    $exe = Join-Path $script:Root 'npp-portable\notepad++.exe'
    $old = @{}
    if ($Log -ne '') { $Env['STDOER_LOG'] = $Log; Remove-Item $Log -ErrorAction SilentlyContinue }
    foreach ($k in $Env.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    $nppArgs = @('-multiInst', '-nosession') + ($Files | ForEach-Object { '"' + $_ + '"' })
    $nppPid = [NppT]::Launch($exe, ($nppArgs -join ' '), (Split-Path $exe))
    $script:ProcNpp = Get-Process -Id $nppPid
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k]) }
    $script:HNpp = [IntPtr]::Zero
    for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Milliseconds 500; $script:ProcNpp.Refresh(); if ($script:ProcNpp.MainWindowHandle -ne [IntPtr]::Zero) { $script:HNpp = $script:ProcNpp.MainWindowHandle; break } }
    if ($script:HNpp -eq [IntPtr]::Zero) { throw 'The portable Notepad++ window did not appear' }
    [NppT]::Attach($script:HNpp)
    # Even if the script ends with an error, the portable copy it opened is closed on exit.
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -MessageData $script:ProcNpp.Id -Action {
        $q = Get-Process -Id $Event.MessageData -ErrorAction SilentlyContinue
        if ($q -and $q.Path -like '*\stdoer\npp-portable\*') { Stop-Process -Id $q.Id -Force }
    } | Out-Null
    for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Milliseconds 500; if ((NppMsg $NPPM_GETNBOPENFILES) -ge $Files.Count) { break } }
    Start-Sleep -Seconds 2
    $sci = [NppT]::Scintillas($script:HNpp)
    $script:VNpp = $sci[0]
    # The portable copies sometimes show one more empty tab "new 1": it is ignored (lookup is by path).
}

function Npp-Documents {
    $n = NppMsg $NPPM_GETNBOPENFILES
    $r = @()
    for ($i = 0; $i -lt $n; $i++) {
        $id = NppMsg $NPPM_GETBUFFERIDFROMPOS $i 0
        [long]$ret = 0
        $b = [NppT]::ReceiveBytes($script:HNpp, $NPPM_GETFULLPATHFROMBUFFERID, $id, 1040, [ref]$ret)
        $path = if ($ret -gt 0) { [Text.Encoding]::Unicode.GetString($b, 0, [int]($ret * 2)) } else { '' }
        $r += [pscustomobject]@{ Index = $i; Path = $path }
    }
    $r
}

function Npp-Activate([int]$index) { [void](NppMsg $NPPM_ACTIVATEDOC 0 $index); Start-Sleep -Milliseconds 150 }

# Closes only the stdoer portable copy that this script opened (without saving anything).
function Npp-Close {
    [NppT]::Detach()
    if ($script:ProcNpp -and -not $script:ProcNpp.HasExited) {
        if ($script:ProcNpp.Path -like '*\stdoer\npp-portable\*') { Stop-Process -Id $script:ProcNpp.Id -Force }
    }
}


# Replace All with Notepad++'s REAL dialog (Find and Replace -> "Replace All"), not with loose
# messages: that way the path the user takes is the one tested.
function Npp-ReplaceAllDialog([string]$find, [string]$with) {
    [void](NppMsg $NPPM_MENUCOMMAND 0 43003)    # IDM_SEARCH_REPLACE
    $dlg = [IntPtr]::Zero
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 150
        $dlg = [NppT]::FindDialog([uint32]$script:ProcNpp.Id, 1609)
        if ($dlg -ne [IntPtr]::Zero) { break }
    }
    if ($dlg -eq [IntPtr]::Zero) { throw ('The replace dialog did not appear. Windows: ' + [NppT]::Windows([uint32]$script:ProcNpp.Id)) }
    $findBox = [NppT]::GetDlgItem($dlg, 1601); $withBox = [NppT]::GetDlgItem($dlg, 1602); $button = [NppT]::GetDlgItem($dlg, 1609)
    Start-Sleep -Milliseconds 500
    [void][NppT]::SendMessageStr($findBox, 0x000C, [IntPtr]::Zero, $find)   # WM_SETTEXT
    [void][NppT]::SendMessageStr($withBox, 0x000C, [IntPtr]::Zero, $with)
    Start-Sleep -Milliseconds 500
    # WM_COMMAND (BN_CLICKED) to the dialog, like a click on "Replace All"
    [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr]1609, $button)
    Start-Sleep -Milliseconds 1500
    # Close as with Esc/Cancel (IDCANCEL), not with a forced WM_CLOSE
    [void][NppT]::SendMessage($dlg, 0x0111, [IntPtr]2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800
}


# Synthetic mouse messages are in physical pixels, but SCI_POINTXFROMPOSITION & co. return
# Scintilla's "logical" pixels: with the screen at 125 % a click would land one row lower. This
# function converts a point of the Scintilla API to the lParam of a mouse message.
function Npp-LParamMouse([int]$x, [int]$y) {
    $dpi = [NppT]::GetDpiForWindow($script:VNpp); if ($dpi -le 0) { $dpi = 96 }
    $f = 96.0 / $dpi
    $xs = [int][Math]::Round($x * $f); $ys = [int][Math]::Round($y * $f)
    [IntPtr](($ys -shl 16) -bor ($xs -band 0xFFFF))
}

# --- menus and right click ---

# All the commands of the main menu ("id|text|state"), to find an identifier by its text.
function Npp-MenuTree { [NppT]::MenuTree([NppT]::GetMenu($script:HNpp), 0) }

# lParam of a WM_CONTEXTMENU (physical SCREEN coordinates, which is what Notepad++ receives, as
# it is DPI aware) over a position of the document. The points of the Scintilla API are those
# of the client area; this test process is NOT DPI aware, so during the conversion the thread
# is declared aware (per thread) so that ClientToScreen returns physical pixels.
# By default it lands 3 pixels inside the character's cell (right on its left edge Scintilla
# picks the previous one).
function Npp-LParamScreen([int64]$pos, [int]$dx = 3, [int]$dy = 3) {
    $p = New-Object NppT+POINT
    $p.x = [int](Sci 2164 0 $pos) + $dx     # SCI_POINTXFROMPOSITION
    $p.y = [int](Sci 2165 0 $pos) + $dy     # SCI_POINTYFROMPOSITION
    $before = [NppT]::SetThreadDpiAwarenessContext([IntPtr](-4))     # PER_MONITOR_AWARE_V2
    [void][NppT]::ClientToScreen($script:VNpp, [ref]$p)
    [void][NppT]::SetThreadDpiAwarenessContext($before)
    [IntPtr](([int64]($p.y -band 0xFFFF) -shl 16) -bor [int64]($p.x -band 0xFFFF))
}

# Requests the context menu for real (WM_CONTEXTMENU to the view) and waits for the popup.
# Returns the options ("id|text|state" per line) or $null if none appeared.
# Without -Choose the popup is closed (WM_CANCELMODE); with -Choose -Down N, Down is pressed N times and then Enter.
function Npp-ContextMenu([int64]$pos, [int]$dx = 3, [int]$dy = 3, [int]$Down = 0, [switch]$Choose, [switch]$Keyboard) {
    # The send is also done with the thread declared DPI aware: otherwise Windows rescales the
    # message's screen coordinates when going from an "unaware" process to an aware one.
    $lp = if ($Keyboard) { [IntPtr](-1) } else { Npp-LParamScreen $pos $dx $dy }     # -1 = from the keyboard (at the cursor)
    $before = [NppT]::SetThreadDpiAwarenessContext([IntPtr](-4))
    [void][NppT]::PostMessage($script:VNpp, 0x007B, $script:VNpp, $lp)    # WM_CONTEXTMENU
    [void][NppT]::SetThreadDpiAwarenessContext($before)
    $pop = [IntPtr]::Zero
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Milliseconds 100; $pop = [NppT]::PopupWindow([uint32]$script:ProcNpp.Id); if ($pop -ne [IntPtr]::Zero) { break } }
    if ($pop -eq [IntPtr]::Zero) { return $null }
    $items = [NppT]::MenuTree([NppT]::PopupMenu($pop), 0)
    if ($Choose) {
        for ($k = 0; $k -lt $Down; $k++) { [void][NppT]::PostMessage($pop, 0x0100, [IntPtr]0x28, [IntPtr]::Zero); Start-Sleep -Milliseconds 120 }   # VK_DOWN
        [void][NppT]::PostMessage($pop, 0x0100, [IntPtr]0x0D, [IntPtr]::Zero)                                                                         # VK_RETURN
    } else {
        [void][NppT]::SendMessage($script:HNpp, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)                                                              # WM_CANCELMODE to Notepad++: closes the popup
    }
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Milliseconds 100; if ([NppT]::PopupWindow([uint32]$script:ProcNpp.Id) -eq [IntPtr]::Zero) { break } }
    if ([NppT]::PopupWindow([uint32]$script:ProcNpp.Id) -ne [IntPtr]::Zero) { $items += "(the popup did NOT close)`n" }
    Start-Sleep -Milliseconds 200
    return $items
}
