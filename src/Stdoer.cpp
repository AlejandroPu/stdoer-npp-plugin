// Stdoer — plugin de Notepad++ para el lenguaje propio .stdoer
// Entrega 1: plugin mínimo. Solo prueba que la DLL carga y aparece en el menú.
//
// Las cabeceras de interfaz de third_party/plugintemplate son de terceros
// (GPL v2+, ver third_party/ORIGEN.md). Este archivo es propio.

#include <windows.h>
#include "PluginInterface.h"

namespace
{
	const wchar_t kNombre[]  = L"Stdoer";
	const wchar_t kVersion[] = L"0.1.0";

	NppData  g_npp;
	FuncItem g_menu[1];

	void acercaDe()
	{
		wchar_t texto[128];
		wsprintfW(texto, L"%s versión %s", kNombre, kVersion);
		::MessageBoxW(g_npp._nppHandle, texto, L"Acerca de Stdoer", MB_OK | MB_ICONINFORMATION);
	}
}

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID)
{
	return TRUE;
}

extern "C" __declspec(dllexport) void setInfo(NppData datos)
{
	g_npp = datos;
	lstrcpynW(g_menu[0]._itemName, L"Acerca de Stdoer", menuItemSize);
	g_menu[0]._pFunc = acercaDe;
}

extern "C" __declspec(dllexport) const wchar_t* getName()
{
	return kNombre;
}

extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* cantidad)
{
	*cantidad = 1;
	return g_menu;
}

extern "C" __declspec(dllexport) void beNotified(SCNotification*)
{
}

extern "C" __declspec(dllexport) LRESULT messageProc(UINT, WPARAM, LPARAM)
{
	return TRUE;
}

extern "C" __declspec(dllexport) BOOL isUnicode()
{
	return TRUE;
}
