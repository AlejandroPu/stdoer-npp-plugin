// Stdoer — parte del plugin que atiende los enlaces __link[ruta] en la ventana de Notepad++:
// estilos de la vista (ruta oculta y no modificable), mostrar la ruta mientras el cursor o la
// selección la tocan, recuadro al pasar el mouse y clic que abre.
//
// El coloreado de cada enlace lo hace el lexer (StdoerLexer.cxx); este módulo no escribe nunca
// en el documento: solo cambia estilos de Scintilla.

#pragma once

#include <windows.h>
#include "PluginInterface.h"

namespace EnlacesUI
{
	void Iniciar(const NppData& datos);
	void Notificar(const SCNotification* n);
}
