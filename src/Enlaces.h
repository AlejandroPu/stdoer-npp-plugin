// Stdoer — enlaces __link[ruta] (lógica pura, sin depender de Scintilla ni de Windows).
//
// Reglas (diseno/lenguaje-notepad.md, "Enlaces"):
//   - Un enlace es "__link[" + ruta + "]", todo en UNA línea. Con un solo "_" (o ninguno)
//     es un enlace desactivado: texto normal que no hace nada.
//   - El "]" de cierre es el que equilibra los corchetes (la ruta puede tener "[ ]").
//     Si la línea termina sin equilibrar, no hay enlace.
//   - Varios enlaces por línea. Un "__link[" precedido de otro "_" no cuenta ("___link[").
//   - Solo se mira el texto: comillas y "#" no importan.

#pragma once

#include <cstddef>
#include <string>
#include <utility>
#include <vector>

namespace Enlaces
{
	// Estilos de Scintilla que el lexer da a las partes de un enlace. Están por encima de los
	// del lexer de Python (0-21 y subestilos desde 128) y de los reservados (32-39).
	constexpr int kEstiloRutaOculta = 50;   // la ruta: invisible y no modificable
	constexpr int kEstiloRutaVisible = 51;  // la ruta, mientras el cursor o la selección la tocan
	constexpr int kEstiloEnlace = 52;       // "link[" y "]": la zona clicable (hotspot)

	// Posiciones dentro de una línea (índices de byte).
	struct Enlace
	{
		std::size_t inicio = 0;  // primer "_"
		std::size_t abre = 0;    // "["
		std::size_t cierra = 0;  // "]" pareja

		// La ruta ocupa [abre + 1, cierra). La zona clicable es "link[" + "]": de inicio + 2
		// a cierra, ambos incluidos (sin los dos "_").
		std::size_t inicioRuta() const { return abre + 1; }
		std::size_t inicioZonaClic() const { return inicio + 2; }
	};

	// Todos los enlaces de una línea (sin su salto de línea), en orden.
	std::vector<Enlace> Buscar(const char* texto, std::size_t largo);

	// ¿El enlace tiene la ruta "tocada" por el intervalo [selIni, selFin] (posiciones de
	// cursor, extremos incluidos)? Se usa para mostrar la ruta mientras se edita. `base` es
	// la posición absoluta del primer byte de la línea. Con selIni < 0 no hay nada tocado.
	bool RutaTocada(const Enlace& e, long long base, long long selIni, long long selFin);

	// Estado compartido entre el plugin y el lexer: el intervalo (selección) cuyos enlaces
	// se muestran. Lo escribe el plugin; lo lee el lexer al dar estilo. -1 = ninguno.
	void FijarRevelado(long long ini, long long fin);
	void LeerRevelado(long long& ini, long long& fin);

	// Zonas de ruta que se muestran además de la selección (enlaces cuya ruta cambió por una vía
	// que no se ve, como "Reemplazar todo"). Cada zona es un intervalo de cursor [ini, fin].
	void FijarExpuestos(const std::vector<std::pair<long long, long long>>& zonas);

	// Estilo que corresponde a la ruta del enlace, según el estado compartido.
	int EstiloDeRuta(const Enlace& e, long long base);

	// Qué hacer al abrir un archivo (el clic nunca ejecuta nada).
	enum class Destino
	{
		Notepad,     // abrir como pestaña de Notepad++
		Windows,     // abrir con el programa que Windows tenga asignado
		Carpeta,     // mostrar el archivo en su carpeta (ejecutables, scripts, macros...)
	};

	// Clasifica por extensión (con el punto, cualquier mayúscula; vacía si no tiene).
	Destino ClasificarExtension(const std::wstring& extension);

	// Extensión de una ruta (con el punto, en minúsculas), o vacía.
	std::wstring ExtensionDe(const std::wstring& ruta);

	// ¿La ruta es absoluta (X:\... o \\servidor\...)? Las relativas no se abren.
	bool EsRutaAbsoluta(const std::wstring& ruta);

	// Quita espacios y tabs de los extremos de la ruta.
	std::string Recortar(const std::string& ruta);
}
