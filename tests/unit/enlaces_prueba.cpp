// Pruebas unitarias de src\Enlaces.cpp (analizador de enlaces y clasificación de rutas).
// Se compila y corre con tests\unit\correr.cmd; sale con código 0 si todo pasa.

#include <cstdio>
#include <string>

#include "Enlaces.h"

namespace
{
	int g_fallos = 0;
	int g_total = 0;

	void Comprobar(bool ok, const char* nombre)
	{
		++g_total;
		if (!ok)
		{
			++g_fallos;
			std::printf("FALLA: %s\n", nombre);
		}
	}

	// Devuelve "inicio:abre:cierra" de cada enlace separados por espacio, o "-" si no hay.
	std::string Resumen(const std::string& linea)
	{
		const auto v = Enlaces::Buscar(linea.data(), linea.size());
		if (v.empty())
			return "-";
		std::string r;
		for (const auto& e : v)
		{
			if (!r.empty())
				r += ' ';
			r += std::to_string(e.inicio) + ":" + std::to_string(e.abre) + ":" + std::to_string(e.cierra);
		}
		return r;
	}

	void Caso(const std::string& linea, const std::string& esperado)
	{
		const std::string obtenido = Resumen(linea);
		++g_total;
		if (obtenido != esperado)
		{
			++g_fallos;
			std::printf("FALLA Buscar(\"%s\"): esperado [%s], obtenido [%s]\n", linea.c_str(), esperado.c_str(), obtenido.c_str());
		}
	}
}

int main()
{
	using namespace Enlaces;

	// --- Buscar ---
	Caso("", "-");
	Caso("__link[a]", "0:6:8");
	Caso("_link[a]", "-");                       // desactivado
	Caso("link[a]", "-");
	Caso("___link[a]", "-");                     // "_" de más: no cuenta
	Caso("x __link[a [1].txt] y", "2:8:18");     // corchetes dentro de la ruta
	Caso("__link[a] y __link[b]", "0:6:8 12:18:20");
	Caso("__link[a", "-");                       // sin cerrar
	Caso("__link[a __link[b]", "9:15:17");        // el primero queda sin cerrar; el segundo vale
	Caso("__link[]", "0:6:7");                   // ruta vacía
	Caso("__link[a]]", "0:6:8");                 // un "]" de más se ignora
	Caso("__link[[x]]", "0:6:10");
	Caso("__link[a] __link[b", "0:6:8");         // el segundo, sin cerrar, no cuenta
	Caso("__LINK[a]", "-");                      // distingue mayúsculas
	Caso("__link [a]", "-");
	Caso("  __link[F:\carpeta\archivo.txt]", "2:8:31");
	Caso("# __link[a] {", "2:8:10");             // # y llaves no importan

	// --- RutaTocada: ruta [107,110), zona de cursor 107..110 ---
	{
		const auto v = Buscar("__link[abc]", 11);
		const Enlace e = v.at(0);
		Comprobar(RutaTocada(e, 100, 107, 107), "cursor justo despues de [");
		Comprobar(RutaTocada(e, 100, 110, 110), "cursor justo antes de ]");
		Comprobar(RutaTocada(e, 100, 108, 108), "cursor dentro de la ruta");
		Comprobar(!RutaTocada(e, 100, 106, 106), "cursor antes de [");
		Comprobar(!RutaTocada(e, 100, 111, 111), "cursor despues de ]");
		Comprobar(RutaTocada(e, 100, 90, 120), "seleccion que contiene el enlace");
		Comprobar(RutaTocada(e, 100, 90, 107), "seleccion que termina en [");
		Comprobar(!RutaTocada(e, 100, 90, 106), "seleccion que termina antes");
		Comprobar(RutaTocada(e, 100, 110, 130), "seleccion que empieza en ]");
		Comprobar(!RutaTocada(e, 100, 111, 130), "seleccion que empieza despues");
		Comprobar(!RutaTocada(e, 100, -1, -1), "sin nada tocado");
	}

	// --- Revelado compartido ---
	{
		FijarRevelado(-1, -1);
		const Enlace e = Buscar("__link[abc]", 11).at(0);
		Comprobar(EstiloDeRuta(e, 100) == kEstiloRutaOculta, "sin revelado: oculta");
		FijarRevelado(108, 108);
		Comprobar(EstiloDeRuta(e, 100) == kEstiloRutaVisible, "con revelado: visible");
		Comprobar(EstiloDeRuta(e, 500) == kEstiloRutaOculta, "otro enlace: oculta");
		FijarRevelado(-1, -1);
	}

	// --- Clasificación por extensión ---
	Comprobar(ClasificarExtension(L".txt") == Destino::Notepad, ".txt");
	Comprobar(ClasificarExtension(L".STDOER") == Destino::Notepad, ".STDOER en mayuscula");
	Comprobar(ClasificarExtension(L".js") == Destino::Notepad, ".js se abre en Notepad++ (no se ejecuta)");
	Comprobar(ClasificarExtension(L".ods") == Destino::Windows, ".ods");
	Comprobar(ClasificarExtension(L".xlsx") == Destino::Windows, ".xlsx");
	Comprobar(ClasificarExtension(L".html") == Destino::Windows, ".html");
	Comprobar(ClasificarExtension(L".pdf") == Destino::Windows, ".pdf");
	Comprobar(ClasificarExtension(L".exe") == Destino::Carpeta, ".exe");
	Comprobar(ClasificarExtension(L".EXE") == Destino::Carpeta, ".EXE");
	Comprobar(ClasificarExtension(L".bat") == Destino::Carpeta, ".bat");
	Comprobar(ClasificarExtension(L".cmd") == Destino::Carpeta, ".cmd");
	Comprobar(ClasificarExtension(L".ps1") == Destino::Carpeta, ".ps1");
	Comprobar(ClasificarExtension(L".vbs") == Destino::Carpeta, ".vbs");
	Comprobar(ClasificarExtension(L".lnk") == Destino::Carpeta, ".lnk");
	Comprobar(ClasificarExtension(L".hta") == Destino::Carpeta, ".hta");
	Comprobar(ClasificarExtension(L".msi") == Destino::Carpeta, ".msi");
	Comprobar(ClasificarExtension(L".jar") == Destino::Carpeta, ".jar");
	Comprobar(ClasificarExtension(L".scr") == Destino::Carpeta, ".scr");
	Comprobar(ClasificarExtension(L".reg") == Destino::Carpeta, ".reg");
	Comprobar(ClasificarExtension(L".docm") == Destino::Carpeta, ".docm (macros)");
	Comprobar(ClasificarExtension(L".xlsm") == Destino::Carpeta, ".xlsm (macros)");
	Comprobar(ClasificarExtension(L"") == Destino::Carpeta, "sin extension");

	// --- ExtensionDe ---
	Comprobar(ExtensionDe(L"C:\a\b.TXT") == L".txt", "ExtensionDe mayuscula");
	Comprobar(ExtensionDe(L"C:\a.b\c") == L"", "punto en carpeta, no en archivo");
	Comprobar(ExtensionDe(L"C:\a\b") == L"", "sin extension");
	Comprobar(ExtensionDe(L"C:\a\b.tar.gz") == L".gz", "ultima extension");
	Comprobar(ExtensionDe(L"C:\a\.stdoer") == L".stdoer", "archivo que empieza con punto");

	// --- EsRutaAbsoluta ---
	Comprobar(EsRutaAbsoluta(L"C:\a"), "unidad");
	Comprobar(EsRutaAbsoluta(L"c:/a"), "unidad con barra");
	Comprobar(EsRutaAbsoluta(L"\\servidor\recurso\a"), "UNC");
	Comprobar(!EsRutaAbsoluta(L"a\b.txt"), "relativa");
	Comprobar(!EsRutaAbsoluta(L"..\a"), "relativa con ..");
	Comprobar(!EsRutaAbsoluta(L"C:a"), "unidad sin barra (relativa a la unidad)");
	Comprobar(!EsRutaAbsoluta(L"\a"), "raiz sin unidad");
	Comprobar(!EsRutaAbsoluta(L""), "vacia");
	Comprobar(!EsRutaAbsoluta(L"\\?\C:\a"), "prefijo de ruta larga: no admitido");
	Comprobar(!EsRutaAbsoluta(L"http://x"), "URL");

	// --- Recortar ---
	Comprobar(Recortar("  a b \t") == "a b", "Recortar");
	Comprobar(Recortar("   ") == "", "Recortar solo espacios");
	Comprobar(Recortar("a") == "a", "Recortar sin nada que quitar");

	std::printf("%d pruebas, %d fallos\n", g_total, g_fallos);
	return g_fallos == 0 ? 0 : 1;
}
