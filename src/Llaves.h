// Stdoer — contracción con { } (lógica pura, sin depender de Scintilla).
//
// Reglas (diseno/lenguaje-notepad.md, "Contracción con { }"):
//   - "{" cuenta solo como ÚLTIMO carácter de una línea (sin contar espacios ni tabs): abre.
//   - "}" cuenta solo como PRIMER carácter de una línea (idem): cierra.
//   - Cualquier otra llave no hace nada. Se mira solo el texto: comillas y "#" no existen
//     para esta capa (el lexer de Python no interviene en esto).
//   - Una "}" sin pareja se ignora. Una "{" sin cerrar también: solo cuenta una "{" que
//     tenga su "}" pareja, así que un error de llaves nunca esconde más de la cuenta.
//   - Emparejado por pila, de arriba hacia abajo, sin mirar la sangría.
//   - Dentro de una región { } la contracción por sangría sigue funcionando; la sangría
//     se compara solo entre líneas de la misma región (un dedent no saca de la región).
//   - La línea "}" queda DENTRO de la región: al contraer se esconde con ella y solo se ve la
//     línea "{". Excepción: "} sino {" cierra una región y abre otra, así que no puede
//     esconderse con la primera y ser cabecera de la segunda a la vez; queda fuera de la
//     primera (visible) y es la cabecera de la segunda.

#pragma once

#include <cstddef>
#include <vector>

namespace Llaves
{
	struct Linea
	{
		bool abre = false;    // la línea termina en "{"
		bool cierra = false;  // la línea empieza con "}"
	};

	// Clasifica el texto de UNA línea (sin su salto de línea).
	Linea Clasificar(const char* texto, std::size_t largo);

	// Pone abre/cierra en false en toda llave sin pareja. Devuelve cuántos pares hay.
	std::size_t Emparejar(std::vector<Linea>& lineas);

	// Recibe en `niveles` los niveles de plegado que dio el lexer de Python (nivel +
	// banderas, uno por línea) y los reescribe incorporando las regiones { } ya
	// emparejadas. Con cero pares no cambia nada. Devuelve true si cambió algo.
	bool Aplicar(const std::vector<Linea>& lineas, std::vector<int>& niveles);
}
