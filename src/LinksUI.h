// Stdoer — the part of the plugin that serves the __link[path] links in the Notepad++ window:
// view styles (path hidden and not modifiable), showing the path while the cursor or the
// selection touch it, the tooltip on mouse hover, and the click that opens.
//
// The coloring of each link is done by the lexer (StdoerLexer.cxx); this module never writes
// to the document except for the Enable / Disable menu items: otherwise it only changes
// Scintilla styles.

#pragma once

#include <windows.h>
#include "PluginInterface.h"

namespace LinksUI
{
	void Init(const NppData& data);
	void Notify(const SCNotification* n);

	// Message from another program (NPPM_MSGTOPLUGIN). Only in test mode (environment variable
	// STDOER_NO_SHELL): internalMsg 1 = show the link's tooltip at position `*info` (long long)
	// of the current document, as if the mouse had stopped there.
	LRESULT TestMessage(const CommunicationInfo* ci);
}
