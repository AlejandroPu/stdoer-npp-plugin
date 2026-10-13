// Stdoer — Notepad++ plugin for the .stdoer language
// 0.6.0: besides the menu, the external lexer "stdoer" (see StdoerLexer.cxx, Braces.h and
// Links.h) and the handling of links in the window, with their right-click menu (LinksUI.cpp).
//
// The interface headers in third_party/plugintemplate are third-party
// (GPL v2+, see third_party/ORIGIN.md). This file is our own.

#include <windows.h>
#include "PluginInterface.h"
#include "LinksUI.h"

namespace
{
	const wchar_t kName[]    = L"Stdoer";
	const wchar_t kVersion[] = L"0.6.0";

	NppData  g_npp;
	FuncItem g_menu[1];

	void about()
	{
		wchar_t text[128];
		wsprintfW(text, L"%s version %s", kName, kVersion);
		::MessageBoxW(g_npp._nppHandle, text, L"About Stdoer", MB_OK | MB_ICONINFORMATION);
	}
}

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID)
{
	return TRUE;
}

extern "C" __declspec(dllexport) void setInfo(NppData data)
{
	g_npp = data;
	LinksUI::Init(data);
	lstrcpynW(g_menu[0]._itemName, L"About Stdoer", menuItemSize);
	g_menu[0]._pFunc = about;
}

extern "C" __declspec(dllexport) const wchar_t* getName()
{
	return kName;
}

extern "C" __declspec(dllexport) FuncItem* getFuncsArray(int* count)
{
	*count = 1;
	return g_menu;
}

extern "C" __declspec(dllexport) void beNotified(SCNotification* notification)
{
	LinksUI::Notify(notification);
}

extern "C" __declspec(dllexport) LRESULT messageProc(UINT message, WPARAM, LPARAM lParam)
{
	if (message == NPPM_MSGTOPLUGIN)
		return LinksUI::TestMessage(reinterpret_cast<const CommunicationInfo*>(lParam));
	return TRUE;
}

extern "C" __declspec(dllexport) BOOL isUnicode()
{
	return TRUE;
}
