// Stdoer — contracción con { }. Ver Llaves.h para las reglas.

#include "Llaves.h"

#include <algorithm>

#include "Scintilla.h"

namespace Llaves
{
	namespace
	{
		// Niveles de plegado de Scintilla: parte numérica en los 12 bits bajos más banderas.
		constexpr int kBase = SC_FOLDLEVELBASE;
		constexpr int kMascara = SC_FOLDLEVELNUMBERMASK;
		constexpr int kCabecera = SC_FOLDLEVELHEADERFLAG;

		bool EsEspacio(char c)
		{
			return c == ' ' || c == '\t';
		}

		// Un marco de la pila: o una región { } o un bloque por sangría de Python.
		struct Marco
		{
			bool llave;
			int nivel;  // solo para bloques por sangría: número de nivel de su cabecera
		};
	}

	Linea Clasificar(const char* texto, std::size_t largo)
	{
		Linea r;
		std::size_t ini = 0;
		while (ini < largo && EsEspacio(texto[ini]))
			++ini;
		if (ini == largo)
			return r;  // en blanco
		std::size_t fin = largo;
		while (fin > ini && EsEspacio(texto[fin - 1]))
			--fin;
		r.cierra = (texto[ini] == '}');
		r.abre = (texto[fin - 1] == '{');
		return r;
	}

	std::size_t Emparejar(std::vector<Linea>& lineas)
	{
		// Un "}" que cierra y "{" que abre en la misma línea ("} else {"): primero cierra.
		std::vector<std::size_t> pila;  // líneas con "{" aún sin pareja
		std::vector<char> abreConPareja(lineas.size(), 0);
		std::vector<char> cierraConPareja(lineas.size(), 0);
		std::size_t pares = 0;
		for (std::size_t i = 0; i < lineas.size(); ++i)
		{
			if (lineas[i].cierra && !pila.empty())
			{
				abreConPareja[pila.back()] = 1;
				cierraConPareja[i] = 1;
				pila.pop_back();
				++pares;
			}
			if (lineas[i].abre)
				pila.push_back(i);
		}
		for (std::size_t i = 0; i < lineas.size(); ++i)
		{
			lineas[i].abre = abreConPareja[i] != 0;
			lineas[i].cierra = cierraConPareja[i] != 0;
		}
		return pares;
	}

	bool Aplicar(const std::vector<Linea>& lineas, std::vector<int>& niveles)
	{
		const std::size_t n = std::min(lineas.size(), niveles.size());
		bool hayPares = false;
		for (std::size_t i = 0; i < n && !hayPares; ++i)
			hayPares = lineas[i].abre || lineas[i].cierra;
		if (!hayPares)
			return false;

		// Se reconstruye el árbol de plegado como una pila de marcos y cada línea recibe
		// como nivel 1024 + (marcos que la rodean). Para los bloques por sangría esto
		// conserva exactamente la estructura de Python: una cabecera abre un marco, que
		// termina en la primera línea cuyo nivel sea menor o igual (así lo interpreta
		// Scintilla).
		std::vector<Marco> pila;
		std::vector<int> profundidades(n, 0);
		std::vector<char> candidata(n, 0);  // la línea abrió algún marco
		int nivelPrevio = 0;  // por si alguna línea no trajera nivel de Python (no debería)
		for (std::size_t i = 0; i < n; ++i)
		{
			const int original = niveles[i];
			const int numero = (original >= 0) ? (original & kMascara) : nivelPrevio;
			const bool cabeceraPython = original >= 0 && (original & kCabecera) != 0;
			nivelPrevio = numero;

			// 1) "}" con pareja: cierra su región y todo lo que se abrió dentro. Si la línea solo
			//    cierra, queda DENTRO de la región (al contraer se esconde con ella); si además
			//    abre otra ("} sino {"), no puede esconderse con la primera y ser cabecera de la
			//    segunda a la vez: queda fuera de la primera y es la cabecera de la segunda.
			int profundidadCierre = -1;
			if (lineas[i].cierra)
			{
				while (!pila.empty() && !pila.back().llave)
					pila.pop_back();
				if (!lineas[i].abre)
					profundidadCierre = static_cast<int>(pila.size());  // cuenta la llave: nivel del contenido
				if (!pila.empty())
					pila.pop_back();
			}
			// 2) Bloques por sangría que terminan aquí. No atraviesan la llave de su región:
			//    dentro de una región se compara la sangría solo con la de la misma región.
			while (!pila.empty() && !pila.back().llave && pila.back().nivel >= numero)
				pila.pop_back();

			profundidades[i] = (profundidadCierre >= 0) ? profundidadCierre : static_cast<int>(pila.size());
			// Una línea que abre "{" abre un solo marco, el de la región: si además Python la
			// marcó cabecera (la línea siguiente está más sangrada), la región manda y los
			// niveles quedan consecutivos.
			if (lineas[i].abre)
			{
				pila.push_back({true, 0});
				candidata[i] = 1;
			}
			else if (cabeceraPython)
			{
				pila.push_back({false, numero});
				candidata[i] = 1;
			}
		}

		// Segunda pasada: una línea es cabecera solo si la siguiente queda más adentro; así un
		// marco que no tiene nada debajo no deja un pliegue sin nada que esconder.
		bool cambio = false;
		for (std::size_t i = 0; i < n; ++i)
		{
			const int original = niveles[i];
			const bool cabecera = candidata[i] && i + 1 < n && profundidades[i + 1] > profundidades[i];
			const int conservar = (original >= 0) ? (original & ~(kMascara | kCabecera)) : 0;
			const int nuevo = conservar | (kBase + std::min(profundidades[i], kMascara - kBase)) | (cabecera ? kCabecera : 0);
			if (nuevo != original)
			{
				niveles[i] = nuevo;
				cambio = true;
			}
		}
		return cambio;
	}
}
