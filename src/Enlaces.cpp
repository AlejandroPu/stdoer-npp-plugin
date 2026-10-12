// Stdoer — enlaces __link[ruta]. Ver Enlaces.h para las reglas.

#include "Enlaces.h"

#include <algorithm>
#include <atomic>
#include <cwctype>
#include <cstring>

namespace Enlaces
{
	namespace
	{
		constexpr char kInicio[] = "__link[";
		constexpr std::size_t kLargoInicio = sizeof(kInicio) - 1;

		std::atomic<long long> g_reveladoIni{-1};
		std::atomic<long long> g_reveladoFin{-1};

		// Archivos que se abren en Notepad++ (diseño: "Qué se abre dónde").
		const wchar_t* const kTexto[] = {L".stdoer", L".py", L".txt", L".md", L".js", L".json",
										 L".xml", L".ini", L".log", L".csv"};

		// Archivos que Windows ejecutaría o que pueden ejecutar código al abrirlos: nunca se
		// abren; se muestra su carpeta. (Basada en la lista de tipos de alto riesgo de
		// Windows, más las macros de Office y otros contenedores de código.)
		const wchar_t* const kPeligrosas[] = {
			L".ade", L".adp", L".app", L".appref-ms", L".appx", L".appxbundle", L".application",
			L".asp", L".aspx", L".bas", L".bat", L".cab", L".cer", L".chm", L".cmd", L".com",
			L".cpl", L".crt", L".csh", L".der", L".dll", L".docm", L".dotm", L".exe", L".fxp",
			L".gadget", L".grp", L".hlp", L".hta", L".inf", L".ins", L".isp", L".its", L".jar",
			L".jnlp", L".jse", L".ksh", L".lnk", L".mad", L".maf", L".mag", L".mam", L".maq",
			L".mar", L".mas", L".mat", L".mau", L".mav", L".maw", L".mcf", L".mda", L".mdb",
			L".mde", L".mdt", L".mdw", L".mdz", L".msc", L".msh", L".msh1", L".msh2", L".mshxml",
			L".msh1xml", L".msh2xml", L".msi", L".msix", L".msixbundle", L".msp", L".mst",
			L".ocx", L".ops", L".pcd", L".pif", L".plg", L".potm", L".ppam", L".ppsm", L".pptm",
			L".prf", L".prg", L".printerexport", L".ps1", L".ps1xml", L".ps2", L".ps2xml",
			L".psc1", L".psc2", L".psd1", L".psdm1", L".pst", L".pyc", L".pyw", L".reg",
			L".scf", L".scr", L".sct", L".settingcontent-ms", L".shb", L".shs", L".sldm",
			L".sys", L".theme", L".themepack", L".tmp", L".url", L".vb", L".vbe", L".vbp",
			L".vbs", L".vsmacros", L".vss", L".vst", L".vsw", L".ws", L".wsc", L".wsf", L".wsh",
			L".xlam", L".xlsm", L".xltm", L".xnk"};

		bool Esta(const wchar_t* const* lista, std::size_t n, const std::wstring& ext)
		{
			for (std::size_t i = 0; i < n; ++i)
				if (ext == lista[i])
					return true;
			return false;
		}
	}

	std::vector<Enlace> Buscar(const char* texto, std::size_t largo)
	{
		std::vector<Enlace> r;
		std::size_t desde = 0;
		while (desde + kLargoInicio <= largo)
		{
			const char* hallado = static_cast<const char*>(
				memchr(texto + desde, '_', largo - desde));
			if (hallado == nullptr)
				break;
			const std::size_t i = static_cast<std::size_t>(hallado - texto);
			if (i + kLargoInicio > largo)
				break;
			const bool empieza = std::memcmp(texto + i, kInicio, kLargoInicio) == 0;
			const bool precedido = i > 0 && texto[i - 1] == '_';
			if (!empieza || precedido)
			{
				desde = i + 1;
				continue;
			}
			// El "]" que equilibra los corchetes.
			const std::size_t abre = i + kLargoInicio - 1;
			int profundidad = 1;
			std::size_t k = abre + 1;
			for (; k < largo; ++k)
			{
				if (texto[k] == '[')
					++profundidad;
				else if (texto[k] == ']' && --profundidad == 0)
					break;
			}
			if (k < largo)
			{
				Enlace e;
				e.inicio = i;
				e.abre = abre;
				e.cierra = k;
				r.push_back(e);
				desde = k + 1;
			}
			else
				desde = i + 2;  // sin cerrar: puede haber un enlace propio más adelante
		}
		return r;
	}

	bool RutaTocada(const Enlace& e, long long base, long long selIni, long long selFin)
	{
		if (selIni < 0 || selFin < selIni)
			return false;
		const long long ini = base + static_cast<long long>(e.inicioRuta());
		const long long fin = base + static_cast<long long>(e.cierra);
		return selIni <= fin && selFin >= ini;
	}

	void FijarRevelado(long long ini, long long fin)
	{
		g_reveladoIni = ini;
		g_reveladoFin = fin;
	}

	void LeerRevelado(long long& ini, long long& fin)
	{
		ini = g_reveladoIni;
		fin = g_reveladoFin;
	}

	int EstiloDeRuta(const Enlace& e, long long base)
	{
		long long ini = -1, fin = -1;
		LeerRevelado(ini, fin);
		return RutaTocada(e, base, ini, fin) ? kEstiloRutaVisible : kEstiloRutaOculta;
	}

	std::wstring ExtensionDe(const std::wstring& ruta)
	{
		const std::size_t barra = ruta.find_last_of(L"\\/");
		const std::size_t punto = ruta.find_last_of(L'.');
		if (punto == std::wstring::npos || (barra != std::wstring::npos && punto < barra))
			return std::wstring();
		std::wstring ext = ruta.substr(punto);
		std::transform(ext.begin(), ext.end(), ext.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
		return ext;
	}

	Destino ClasificarExtension(const std::wstring& extensionCualquiera)
	{
		std::wstring ext = extensionCualquiera;
		std::transform(ext.begin(), ext.end(), ext.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
		if (ext.empty())
			return Destino::Carpeta;  // sin extensión: no se sabe qué es
		if (Esta(kTexto, sizeof(kTexto) / sizeof(kTexto[0]), ext))
			return Destino::Notepad;
		if (Esta(kPeligrosas, sizeof(kPeligrosas) / sizeof(kPeligrosas[0]), ext))
			return Destino::Carpeta;
		return Destino::Windows;
	}

	bool EsRutaAbsoluta(const std::wstring& ruta)
	{
		if (ruta.size() >= 3 && std::iswalpha(ruta[0]) && ruta[1] == L':' && (ruta[2] == L'\\' || ruta[2] == L'/'))
			return true;
		return ruta.size() >= 3 && ruta[0] == L'\\' && ruta[1] == L'\\' && ruta[2] != L'\\' && ruta[2] != L'?';
	}

	std::string Recortar(const std::string& ruta)
	{
		const std::size_t a = ruta.find_first_not_of(" \t");
		if (a == std::string::npos)
			return std::string();
		const std::size_t b = ruta.find_last_not_of(" \t");
		return ruta.substr(a, b - a + 1);
	}
}
