// Stdoer — plugin de Notepad++ para el lenguaje propio .stdoer
// 0.5.0: además del menú, el lexer externo "stdoer" (ver StdoerLexer.cxx, Llaves.h y
// Enlaces.h) y la atención de los enlaces en la ventana, con su menú del clic derecho (EnlacesUI.cpp).
//
// Las cabeceras de interfaz de third_party/plugintemplate son de terceros
// (GPL v2+, ver third_party/ORIGIN.md). Este archivo es propio.

#include <windows.h>
#include "PluginInterface.h"
#include "EnlacesUI.h"

namespace
{
	const wchar_t kNombre[]  = L"Stdoer";
	const wchar_t kVersion[] = L"0.5.0";

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
	EnlacesUI::Iniciar(datos);
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

extern "C" __declspec(dllexport) void beNotified(SCNotification* notificacion)
{
	EnlacesUI::Notificar(notificacion);
}

extern "C" __declspec(dllexport) LRESULT messageProc(UINT mensaje, WPARAM, LPARAM lParam)
{
	if (mensaje == NPPM_MSGTOPLUGIN)
		return EnlacesUI::MensajeDePrueba(reinterpret_cast<const CommunicationInfo*>(lParam));
	return TRUE;
}

extern "C" __declspec(dllexport) BOOL isUnicode()
{
	return TRUE;
}
