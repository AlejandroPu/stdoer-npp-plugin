// Stdoer — lexer externo para Notepad++ (interfaz tipo Lexilla).
//
// Entrega 2 (0.2.0): el lexer "stdoer" reutiliza tal cual el lexer de Python de
// Lexilla 5.4.4 (el mismo que usa Notepad++ 8.8.1), de modo que la contracción por
// sangría es idéntica a la de los .py por construcción. Lo que cambia es:
//   - el nombre del lexer ("stdoer") y la extensión (.stdoer, ver config\Stdoer.xml);
//   - las propiedades que Notepad++ fija para Python y que a un lexer externo no le
//     fija nadie, se fijan aquí con los mismos valores;
//   - sin colores: Stdoer.xml no define estilos, así que todo se ve como texto plano.
//
// Código de Lexilla/Scintilla en third_party\lexilla (licencia HPND, ver ORIGEN.md).

#include <cstring>

#include "ILexer.h"
#include "LexerModule.h"

extern const Lexilla::LexerModule lmPython;

namespace
{
	const char kNombreLexer[] = "stdoer";
}

extern "C"
{
	__declspec(dllexport) int __stdcall GetLexerCount()
	{
		return 1;
	}

	__declspec(dllexport) void __stdcall GetLexerName(unsigned int indice, char* nombre, int largo)
	{
		if (nombre == nullptr || largo <= 0)
			return;
		nombre[0] = '\0';
		if (indice == 0 && static_cast<size_t>(largo) > sizeof(kNombreLexer) - 1)
			std::memcpy(nombre, kNombreLexer, sizeof(kNombreLexer));
	}

	__declspec(dllexport) Scintilla::ILexer5* __stdcall CreateLexer(const char* nombre)
	{
		if (nombre == nullptr || std::strcmp(nombre, kNombreLexer) != 0)
			return nullptr;

		Scintilla::ILexer5* lexer = lmPython.Create();
		if (lexer == nullptr)
			return nullptr;

		// Mismos valores que Notepad++ 8.8.1 fija para Python (ScintillaEditView.cpp:
		// setLexer y setPythonLexer). Un lexer externo no recibe ninguno.
		lexer->PropertySet("fold", "1");
		lexer->PropertySet("fold.compact", "0");
		lexer->PropertySet("fold.quotes.python", "1");
		lexer->PropertySet("lexer.python.decorator.attributes", "1");
		lexer->PropertySet("lexer.python.identifier.attributes", "1");
		return lexer;
	}
}
