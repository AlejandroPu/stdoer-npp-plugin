// Stdoer — enlaces en la ventana de Notepad++. Ver EnlacesUI.h.

#define NOMINMAX
#include "EnlacesUI.h"

#include <shellapi.h>
#include <shlwapi.h>

#include <algorithm>
#include <chrono>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <future>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "Enlaces.h"

namespace
{
	NppData g_npp;

	// Estado por vista (principal y secundaria).
	struct EstadoVista
	{
		bool aplicado = false;        // los estilos de enlace están puestos en esta vista
		long long revIni = -1;        // intervalo mostrado por la última actualización
		long long revFin = -1;
	};
	EstadoVista g_vistas[2];
	bool g_tipNuestro = false;        // el recuadro que está visible lo mostramos nosotros

	// --- cambios de ruta que no se ven ("Reemplazar todo") ---
	// Notepad++ reemplaza con SCI_REPLACETARGET, que no respeta los estilos no modificables, y
	// durante la operación apaga los avisos de modificación; al terminar manda
	// NPPN_GLOBALMODIFIED. Por eso se guarda, por documento, la lista de rutas tal como estaba
	// la última vez que se vio cambiar el texto, y al recibir ese aviso se compara.
	using IdBuffer = std::uintptr_t;
	std::map<IdBuffer, std::vector<std::string>> g_rutas;   // rutas de cada documento (instantánea)
	std::set<IdBuffer> g_pendientes;                        // modificados por "reemplazar todo" sin estar a la vista
	IdBuffer g_bufVista[2] = {0, 0};                        // documento activo de cada vista
	bool g_sucia[2] = {false, false};                       // el texto cambió: hay que rehacer la instantánea
	bool g_limpiarExpuestos = false;                        // el texto cambió: dejar de mostrar lo expuesto
	std::vector<std::pair<long long, long long>> g_expuestos;
	bool g_hayAnotaciones = false;                          // pusimos anotaciones de aviso

	// --- registro opcional para pruebas: si existe la variable STDOER_LOG, se anota ahí ---
	void Log(const char* formato, ...)
	{
		static wchar_t ruta[MAX_PATH] = {};
		static int estado = 0;  // 0 sin mirar, 1 sin registro, 2 con registro
		if (estado == 0)
			estado = (::GetEnvironmentVariableW(L"STDOER_LOG", ruta, MAX_PATH) > 0) ? 2 : 1;
		if (estado != 2)
			return;
		FILE* f = nullptr;
		if (_wfopen_s(&f, ruta, L"ab") != 0 || f == nullptr)
			return;
		va_list ap;
		va_start(ap, formato);
		std::vfprintf(f, formato, ap);
		va_end(ap);
		std::fputc('\n', f);
		std::fclose(f);
	}

	// Para las pruebas automáticas: con STDOER_SIN_SHELL definida, el plugin registra qué abriría
	// pero no llama a Windows (así las pruebas no abren programas en la pantalla de nadie).
	bool SinShell()
	{
		static int estado = 0;
		if (estado == 0)
			estado = (::GetEnvironmentVariableW(L"STDOER_SIN_SHELL", nullptr, 0) > 0) ? 2 : 1;
		return estado == 2;
	}

	LRESULT Sci(HWND h, UINT m, WPARAM w = 0, LPARAM l = 0)
	{
		return ::SendMessageW(h, m, w, l);
	}

	int IndiceVista(HWND h)
	{
		if (h == g_npp._scintillaMainHandle)
			return 0;
		if (h == g_npp._scintillaSecondHandle)
			return 1;
		return -1;
	}

	bool EsStdoer(HWND h)
	{
		char nombre[32] = {};
		Sci(h, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<LPARAM>(nombre));
		return std::strcmp(nombre, "stdoer") == 0;
	}

	// --- estilos de la vista ---

	// La ruta (estilo 50) es invisible y no modificable: ni Retroceso, Suprimir, escribir sobre
	// una selección, cortar o pegar la tocan. Mientras el cursor o la selección la tocan se
	// muestra (estilo 51) y entonces sí se puede editar, a la vista.
	void AplicarEstilos(HWND h, int idx)
	{
		Sci(h, SCI_STYLESETVISIBLE, Enlaces::kEstiloRutaOculta, 0);
		Sci(h, SCI_STYLESETCHANGEABLE, Enlaces::kEstiloRutaOculta, 0);
		Sci(h, SCI_STYLESETVISIBLE, Enlaces::kEstiloRutaVisible, 1);
		Sci(h, SCI_STYLESETCHANGEABLE, Enlaces::kEstiloRutaVisible, 1);
		Sci(h, SCI_STYLESETFORE, Enlaces::kEstiloRutaVisible, RGB(0x80, 0x80, 0x80));
		Sci(h, SCI_STYLESETHOTSPOT, Enlaces::kEstiloEnlace, 1);
		Sci(h, SCI_SETHOTSPOTACTIVEFORE, 1, RGB(0x00, 0x66, 0xCC));
		Sci(h, SCI_SETHOTSPOTACTIVEUNDERLINE, 1, 0);
		Sci(h, SCI_SETHOTSPOTSINGLELINE, 1, 0);
		Sci(h, SCI_SETMOUSEDWELLTIME, 500, 0);
		g_vistas[idx].aplicado = true;
		Log("estilos aplicados vista %d", idx);
	}

	// Cuando el documento deja de ser .stdoer se devuelven los valores normales (otro lexer
	// puede usar esos números de estilo).
	void QuitarEstilos(HWND h, int idx)
	{
		for (int e : {Enlaces::kEstiloRutaOculta, Enlaces::kEstiloRutaVisible})
		{
			Sci(h, SCI_STYLESETVISIBLE, e, 1);
			Sci(h, SCI_STYLESETCHANGEABLE, e, 1);
		}
		Sci(h, SCI_STYLESETHOTSPOT, Enlaces::kEstiloEnlace, 0);
		Sci(h, SCI_SETHOTSPOTACTIVEFORE, 0, 0);
		Sci(h, SCI_SETHOTSPOTACTIVEUNDERLINE, 0, 0);
		Sci(h, SCI_SETMOUSEDWELLTIME, SC_TIME_FOREVER, 0);
		g_vistas[idx].aplicado = false;
		g_vistas[idx].revIni = g_vistas[idx].revFin = -1;
		Log("estilos quitados vista %d", idx);
	}

	void RevisarDocumentoActivo(HWND h, int idx);

	// Puede llamarse en cualquier momento: deja la vista como corresponde a su lexer actual.
	// También repara el caso de que Notepad++ haya reiniciado los estilos sin avisar.
	void RevisarVista(HWND h, int idx)
	{
		if (h == nullptr || idx < 0)
			return;
		if (EsStdoer(h))
		{
			RevisarDocumentoActivo(h, idx);
			if (!g_vistas[idx].aplicado || Sci(h, SCI_STYLEGETVISIBLE, Enlaces::kEstiloRutaOculta) != 0 ||
				Sci(h, SCI_STYLEGETCHANGEABLE, Enlaces::kEstiloRutaOculta) != 0)
				AplicarEstilos(h, idx);
		}
		else if (g_vistas[idx].aplicado)
			QuitarEstilos(h, idx);
	}

	void RevisarAmbasVistas()
	{
		RevisarVista(g_npp._scintillaMainHandle, 0);
		RevisarVista(g_npp._scintillaSecondHandle, 1);
	}

	// --- texto de una línea ---

	std::string TextoRango(HWND h, long long ini, long long fin)
	{
		if (fin <= ini)
			return std::string();
		std::string s(static_cast<std::size_t>(fin - ini), '\0');
		Sci_TextRangeFull tr;
		tr.chrg.cpMin = static_cast<Sci_Position>(ini);
		tr.chrg.cpMax = static_cast<Sci_Position>(fin);
		tr.lpstrText = &s[0];
		Sci(h, SCI_GETTEXTRANGEFULL, 0, reinterpret_cast<LPARAM>(&tr));
		return s;
	}

	struct LineaConEnlaces
	{
		long long inicio = 0;  // posición absoluta del primer byte
		std::string texto;
		std::vector<Enlaces::Enlace> enlaces;
	};

	LineaConEnlaces LeerLinea(HWND h, long long linea)
	{
		LineaConEnlaces r;
		r.inicio = Sci(h, SCI_POSITIONFROMLINE, static_cast<WPARAM>(linea));
		const long long fin = Sci(h, SCI_GETLINEENDPOSITION, static_cast<WPARAM>(linea));
		r.texto = TextoRango(h, r.inicio, fin);
		r.enlaces = Enlaces::Buscar(r.texto.data(), r.texto.size());
		return r;
	}

	// --- mostrar la ruta mientras el cursor o la selección la tocan ---

	// Da a las rutas de las líneas [posIni, posFin] el estilo que les corresponde según el
	// intervalo mostrado actual (el mismo criterio que usa el lexer).
	void RestilarRango(HWND h, long long posIni, long long posFin)
	{
		if (posIni < 0)
			return;
		Log("  RestilarRango %lld..%lld", posIni, posFin);
		const long long total = Sci(h, SCI_GETLENGTH);
		posFin = std::min(posFin, total);
		const long long primera = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(posIni));
		long long ultima = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(posFin));
		// Un rango enorme (Ctrl+E de un documento muy largo) se vuelve a colorear entero.
		if (ultima - primera > 20000)
		{
			Sci(h, SCI_COLOURISE, 0, -1);
			return;
		}
		const long long finEstilado = Sci(h, SCI_GETENDSTYLED);
		for (long long l = primera; l <= ultima; ++l)
		{
			const LineaConEnlaces ln = LeerLinea(h, l);
			for (const auto& e : ln.enlaces)
			{
				if (e.cierra <= e.abre + 1)
					continue;
				const int estilo = Enlaces::EstiloDeRuta(e, ln.inicio);
				Sci(h, SCI_STARTSTYLING, static_cast<WPARAM>(ln.inicio + static_cast<long long>(e.inicioRuta())), 0);
				Sci(h, SCI_SETSTYLING, static_cast<WPARAM>(e.cierra - e.abre - 1), estilo);
			}
		}
		Sci(h, SCI_STARTSTYLING, static_cast<WPARAM>(finEstilado), 0);
	}

	void ActualizarRevelado(HWND h, int idx)
	{
		long long ini = -1, fin = -1;
		const long long n = std::min<long long>(Sci(h, SCI_GETSELECTIONS), 1000);
		for (long long i = 0; i < n; ++i)
		{
			const long long a = Sci(h, SCI_GETSELECTIONNSTART, static_cast<WPARAM>(i));
			const long long b = Sci(h, SCI_GETSELECTIONNEND, static_cast<WPARAM>(i));
			if (ini < 0 || a < ini)
				ini = a;
			if (b > fin)
				fin = b;
		}
		EstadoVista& v = g_vistas[idx];
		if (ini == v.revIni && fin == v.revFin)
			return;
		const long long viejoIni = v.revIni, viejoFin = v.revFin;
		v.revIni = ini;
		v.revFin = fin;
		Enlaces::FijarRevelado(ini, fin);
		RestilarRango(h, viejoIni, viejoFin);
		RestilarRango(h, ini, fin);
	}

	// --- rutas de todo el documento (para detectar cambios que no se ven) ---

	std::vector<std::string> ListaRutas(HWND h)
	{
		std::vector<std::string> r;
		const long long total = Sci(h, SCI_GETLENGTH);
		if (total <= 0)
			return r;
		const std::string texto = TextoRango(h, 0, total);
		if (texto.find("__link[") == std::string::npos)
			return r;
		// Los enlaces están en una línea: se recorre línea por línea.
		std::size_t ini = 0;
		while (ini <= texto.size())
		{
			std::size_t fin = texto.find_first_of("\r\n", ini);
			if (fin == std::string::npos)
				fin = texto.size();
			for (const auto& e : Enlaces::Buscar(texto.data() + ini, fin - ini))
				r.push_back(Enlaces::Recortar(texto.substr(ini + e.abre + 1, e.cierra - e.abre - 1)));
			ini = fin + 1;
		}
		return r;
	}

	// Rutas de `ahora` que no estaban en `antes` (contando repeticiones).
	std::multiset<std::string> RutasNuevas(const std::vector<std::string>& antes, const std::vector<std::string>& ahora)
	{
		std::multiset<std::string> viejas(antes.begin(), antes.end());
		std::multiset<std::string> nuevas;
		for (const auto& r : ahora)
		{
			auto it = viejas.find(r);
			if (it != viejas.end())
				viejas.erase(it);
			else
				nuevas.insert(r);
		}
		return nuevas;
	}

	void LimpiarExpuestos(HWND h)
	{
		if (g_expuestos.empty())
			return;
		Log("  LimpiarExpuestos (%d zonas)", static_cast<int>(g_expuestos.size()));
		const auto viejos = g_expuestos;
		g_expuestos.clear();
		if (g_hayAnotaciones)
		{
			Sci(h, SCI_ANNOTATIONCLEARALL);
			g_hayAnotaciones = false;
		}
		Enlaces::FijarExpuestos(g_expuestos);
		for (const auto& z : viejos)
			RestilarRango(h, z.first, z.second);
		Log("expuestos: se dejan de mostrar");
	}

	// Muestra los enlaces cuya ruta aparece en `nuevas` y avisa con un recuadro.
	void Exponer(HWND h, const std::multiset<std::string>& nuevasEntrada)
	{
		std::multiset<std::string> nuevas = nuevasEntrada;
		LimpiarExpuestos(h);
		std::vector<std::pair<long long, long long>> zonas;
		const long long lineas = Sci(h, SCI_GETLINECOUNT);
		for (long long l = 0; l < lineas && !nuevas.empty(); ++l)
		{
			const long long ini = Sci(h, SCI_POSITIONFROMLINE, static_cast<WPARAM>(l));
			const long long fin = Sci(h, SCI_GETLINEENDPOSITION, static_cast<WPARAM>(l));
			if (fin - ini < 8)
				continue;
			const std::string texto = TextoRango(h, ini, fin);
			for (const auto& e : Enlaces::Buscar(texto.data(), texto.size()))
			{
				auto it = nuevas.find(Enlaces::Recortar(texto.substr(e.abre + 1, e.cierra - e.abre - 1)));
				if (it == nuevas.end())
					continue;
				nuevas.erase(it);
				zonas.emplace_back(ini + static_cast<long long>(e.inicioRuta()), ini + static_cast<long long>(e.cierra));
			}
		}
		if (zonas.empty())
			return;
		g_expuestos = zonas;
		Enlaces::FijarExpuestos(g_expuestos);
		for (const auto& z : zonas)
			RestilarRango(h, z.first, z.second);
		// Aviso persistente: una anotación (línea de texto bajo el enlace; no es parte del documento).
		// Un recuadro de ayuda no sirve aquí: se pierde al cambiar el foco.
		Sci(h, SCI_ANNOTATIONSETVISIBLE, ANNOTATION_BOXED, 0);
		for (const auto& z : zonas)
		{
			const long long linea = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(z.first));
			static const char aviso[] = "Se cambio la ruta de este enlace sin que se viera (ahora esta visible). Ctrl+Z deshace.";
			Sci(h, SCI_ANNOTATIONSETTEXT, static_cast<WPARAM>(linea), reinterpret_cast<LPARAM>(aviso));
			Sci(h, SCI_ANNOTATIONSETSTYLE, static_cast<WPARAM>(linea), Enlaces::kEstiloRutaVisible);
		}
		g_hayAnotaciones = true;
		Log("expuestos: %d enlace(s) con ruta cambiada por una via que no se ve", static_cast<int>(zonas.size()));
	}

	IdBuffer BufferActivo(int vista)
	{
		const LRESULT indice = ::SendMessageW(g_npp._nppHandle, NPPM_GETCURRENTDOCINDEX, 0, vista);
		return static_cast<IdBuffer>(::SendMessageW(g_npp._nppHandle, NPPM_GETBUFFERIDFROMPOS, static_cast<WPARAM>(indice), vista));
	}

	// Compara las rutas actuales del documento de la vista con su instantánea.
	void CompararRutas(HWND h, int idx)
	{
		const IdBuffer id = g_bufVista[idx];
		Log("  CompararRutas vista %d id=%llu", idx, static_cast<unsigned long long>(id));
		const std::vector<std::string> ahora = ListaRutas(h);
		auto it = g_rutas.find(id);
		if (it != g_rutas.end())
		{
			const auto nuevas = RutasNuevas(it->second, ahora);
			if (!nuevas.empty())
				Exponer(h, nuevas);
		}
		g_rutas[id] = ahora;
	}

	// Mantiene al día qué documento hay en cada vista y su instantánea de rutas.
	void RevisarDocumentoActivo(HWND h, int idx)
	{
		const IdBuffer id = BufferActivo(idx);
		if (id == 0 || id == g_bufVista[idx])
			return;
		LimpiarExpuestos(h);
		g_bufVista[idx] = id;
		g_sucia[idx] = false;
		if (g_pendientes.erase(id) > 0)
			CompararRutas(h, idx);            // lo cambiaron mientras no se veía
		else if (g_rutas.find(id) == g_rutas.end())
			g_rutas[id] = ListaRutas(h);      // primera vez que se ve: así está
	}

	// --- comprobar si una ruta existe, sin poder congelar Notepad++ ---

	enum class Estado { Existe, NoExiste, SinRespuesta };
	struct Existencia
	{
		Estado estado = Estado::NoExiste;
		bool carpeta = false;
	};

	struct Entrada
	{
		std::shared_future<DWORD> atributos;
		ULONGLONG creada = 0;
	};
	std::mutex g_mutexCache;
	std::map<std::wstring, Entrada> g_cache;

	std::wstring EnMinusculas(std::wstring s)
	{
		std::transform(s.begin(), s.end(), s.begin(), [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
		return s;
	}

	// GetFileAttributes puede quedarse esperando minutos (unidad desconectada, servidor que no
	// responde). Se consulta en otro hilo y se espera como máximo `espera` ms. Un hilo que no
	// termina se deja correr; mientras sigue pendiente (hasta 60 s) no se lanza otro igual.
	Existencia Comprobar(const std::wstring& ruta, DWORD espera)
	{
		const std::wstring clave = EnMinusculas(ruta);
		const ULONGLONG ahora = ::GetTickCount64();
		std::shared_future<DWORD> futuro;
		{
			std::lock_guard<std::mutex> cierre(g_mutexCache);
			if (g_cache.size() > 200)
			{
				for (auto it = g_cache.begin(); it != g_cache.end();)
				{
					const bool listo = it->second.atributos.wait_for(std::chrono::seconds(0)) == std::future_status::ready;
					it = (listo && ahora - it->second.creada > 300000) ? g_cache.erase(it) : std::next(it);
				}
			}
			bool lanzar = true;
			auto it = g_cache.find(clave);
			if (it != g_cache.end())
			{
				const bool listo = it->second.atributos.wait_for(std::chrono::seconds(0)) == std::future_status::ready;
				if (listo)
					lanzar = ahora - it->second.creada > 3000;   // resultado reciente: se reutiliza
				else if (ahora - it->second.creada > 60000)
					return Existencia{Estado::SinRespuesta, false};  // lleva demasiado: no se insiste
				else
					lanzar = false;                              // consulta en curso: se espera esa
			}
			if (lanzar)
			{
				auto promesa = std::make_shared<std::promise<DWORD>>();
				Entrada e;
				e.atributos = promesa->get_future().share();
				e.creada = ahora;
				g_cache[clave] = e;
				const std::wstring copia = ruta;
				std::thread([promesa, copia]() { promesa->set_value(::GetFileAttributesW(copia.c_str())); }).detach();
			}
			futuro = g_cache[clave].atributos;
		}
		if (futuro.wait_for(std::chrono::milliseconds(espera)) != std::future_status::ready)
			return Existencia{Estado::SinRespuesta, false};
		const DWORD a = futuro.get();
		if (a == INVALID_FILE_ATTRIBUTES)
			return Existencia{Estado::NoExiste, false};
		return Existencia{Estado::Existe, (a & FILE_ATTRIBUTE_DIRECTORY) != 0};
	}

	// --- ruta de un enlace ---

	std::wstring ARuta(HWND h, const std::string& bytes)
	{
		if (bytes.empty())
			return std::wstring();
		const UINT cp = (Sci(h, SCI_GETCODEPAGE) == SC_CP_UTF8) ? CP_UTF8 : CP_ACP;
		const int n = ::MultiByteToWideChar(cp, 0, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
		if (n <= 0)
			return std::wstring();
		std::wstring w(static_cast<std::size_t>(n), L'\0');
		::MultiByteToWideChar(cp, 0, bytes.data(), static_cast<int>(bytes.size()), &w[0], n);
		return w;
	}

	// Busca el enlace cuya zona [desde, hasta] (índices de la línea) contiene la posición.
	// `zonaClic` = true: solo "link[...]" ; false: todo el enlace, con los "_".
	bool EnlaceEn(HWND h, long long pos, bool zonaClic, LineaConEnlaces& linea, Enlaces::Enlace& hallado)
	{
		if (pos < 0)
			return false;
		const long long l = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(pos));
		linea = LeerLinea(h, l);
		const long long rel = pos - linea.inicio;
		for (const auto& e : linea.enlaces)
		{
			const long long desde = static_cast<long long>(zonaClic ? e.inicioZonaClic() : e.inicio);
			if (rel >= desde && rel <= static_cast<long long>(e.cierra))
			{
				hallado = e;
				return true;
			}
		}
		return false;
	}

	std::string RutaEnBytes(const LineaConEnlaces& linea, const Enlaces::Enlace& e)
	{
		return Enlaces::Recortar(linea.texto.substr(e.abre + 1, e.cierra - e.abre - 1));
	}

	// --- recuadro al pasar el mouse ---

	void MostrarRecuadro(HWND h, long long pos)
	{
		LineaConEnlaces linea;
		Enlaces::Enlace e;
		if (!EnlaceEn(h, pos, false, linea, e))
			return;
		if (Sci(h, SCI_CALLTIPACTIVE) != 0)
			return;  // ya hay otro recuadro (p. ej., de autocompletado)
		const std::string bytes = RutaEnBytes(linea, e);
		std::string texto = bytes;
		if (bytes.empty())
			texto = "(ruta vacia)";
		else
		{
			const std::wstring ruta = ARuta(h, bytes);
			if (!Enlaces::EsRutaAbsoluta(ruta))
				texto += "\n(ruta relativa: no se abre)";
			else
			{
				const Existencia ex = Comprobar(ruta, 300);
				if (ex.estado == Estado::NoExiste)
					texto += "\n(no existe)";
				else if (ex.estado == Estado::SinRespuesta)
					texto += "\n(sin respuesta: no se pudo comprobar si existe)";
			}
		}
		Sci(h, SCI_CALLTIPSHOW, static_cast<WPARAM>(linea.inicio + static_cast<long long>(e.inicio)), reinterpret_cast<LPARAM>(texto.c_str()));
		g_tipNuestro = true;
		std::string unaLinea = texto;
		for (auto& c : unaLinea)
			if (c == '\n')
				c = '|';
		Log("recuadro: %s", unaLinea.c_str());
	}

	void OcultarRecuadro(HWND h)
	{
		if (g_tipNuestro)
		{
			Sci(h, SCI_CALLTIPCANCEL);
			g_tipNuestro = false;
		}
	}

	// --- abrir (el clic nunca ejecuta nada) ---

	void MostrarEnCarpeta(const std::wstring& ruta)
	{
		const std::wstring args = L"/select,\"" + ruta + L"\"";
		if (!SinShell())
			::ShellExecuteW(nullptr, L"open", L"explorer.exe", args.c_str(), nullptr, SW_SHOWNORMAL);
		Log("abrir: carpeta contenedora de %ls", ruta.c_str());
	}

	// ¿Windows abriría este tipo con un programa aparte? Si la acción "open" es el propio
	// archivo ("%1" ...), abrirlo lo ejecutaría; si no hay acción, saldría el diálogo
	// "Abrir con". En ambos casos no se abre.
	bool AsociacionSegura(const std::wstring& extension)
	{
		wchar_t cmd[1024] = {};
		DWORD n = static_cast<DWORD>(sizeof(cmd) / sizeof(cmd[0]));
		if (FAILED(::AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_COMMAND, extension.c_str(), L"open", cmd, &n)))
			return false;
		const std::wstring c = EnMinusculas(cmd);
		std::size_t i = c.find_first_not_of(L" \t");
		if (i == std::wstring::npos)
			return false;
		if (c.compare(i, 4, L"\"%1\"") == 0 || c.compare(i, 2, L"%1") == 0)
			return false;
		return true;
	}

	void AbrirRuta(HWND h, const std::wstring& ruta)
	{
		if (!Enlaces::EsRutaAbsoluta(ruta))
		{
			Log("abrir: ruta no absoluta, no se hace nada: %ls", ruta.c_str());
			return;
		}
		const ULONGLONG t0 = ::GetTickCount64();
		const Existencia ex = Comprobar(ruta, 1000);
		Log("abrir: comprobar existencia tardo %llu ms", static_cast<unsigned long long>(::GetTickCount64() - t0));
		if (ex.estado != Estado::Existe)
		{
			Log("abrir: %ls %s, no se hace nada", ruta.c_str(), ex.estado == Estado::NoExiste ? "no existe" : "sin respuesta");
			return;
		}
		if (ex.carpeta)
		{
			if (!SinShell())
				::ShellExecuteW(h, L"open", ruta.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
			Log("abrir: carpeta %ls", ruta.c_str());
			return;
		}
		const std::wstring ext = Enlaces::ExtensionDe(ruta);
		switch (Enlaces::ClasificarExtension(ext))
		{
		case Enlaces::Destino::Notepad:
			::SendMessageW(g_npp._nppHandle, NPPM_DOOPEN, 0, reinterpret_cast<LPARAM>(ruta.c_str()));
			Log("abrir: en Notepad++ %ls", ruta.c_str());
			break;
		case Enlaces::Destino::Windows:
			if (AsociacionSegura(ext))
			{
				std::wstring carpeta = ruta.substr(0, ruta.find_last_of(L"\\/"));
				if (!SinShell())
					::ShellExecuteW(h, L"open", ruta.c_str(), nullptr, carpeta.c_str(), SW_SHOWNORMAL);
				Log("abrir: con Windows %ls", ruta.c_str());
			}
			else
				MostrarEnCarpeta(ruta);
			break;
		case Enlaces::Destino::Carpeta:
			MostrarEnCarpeta(ruta);
			break;
		}
	}

	void ClicEnEnlace(HWND h, long long pos, int modificadores)
	{
		Log("clic en zona activa pos=%lld modificadores=%d", pos, modificadores);
		if (modificadores & (SCMOD_SHIFT | SCMOD_CTRL | SCMOD_ALT))
			return;  // con modificadores es seleccionar, no abrir
		LineaConEnlaces linea;
		Enlaces::Enlace e;
		if (!EnlaceEn(h, pos, true, linea, e))
		{
			Log("clic: la posicion %lld no esta en la zona clicable de ningun enlace", pos);
			return;
		}
		OcultarRecuadro(h);
		AbrirRuta(h, ARuta(h, RutaEnBytes(linea, e)));
	}
}

namespace EnlacesUI
{
	LRESULT MensajeDePrueba(const CommunicationInfo* ci)
	{
		if (!SinShell() || ci == nullptr || ci->info == nullptr)
			return FALSE;
		int cual = 0;
		::SendMessageW(g_npp._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, reinterpret_cast<LPARAM>(&cual));
		HWND h = (cual == 0) ? g_npp._scintillaMainHandle : g_npp._scintillaSecondHandle;
		const int idx = IndiceVista(h);
		if (ci->internalMsg == 1 && idx >= 0 && g_vistas[idx].aplicado)
		{
			MostrarRecuadro(h, *static_cast<const long long*>(ci->info));
			return TRUE;
		}
		return FALSE;
	}

	void Iniciar(const NppData& datos)
	{
		g_npp = datos;
	}

	void Notificar(const SCNotification* n)
	{
		HWND origen = static_cast<HWND>(n->nmhdr.hwndFrom);
		switch (n->nmhdr.code)
		{
		case NPPN_READY:
		case NPPN_BUFFERACTIVATED:
		case NPPN_LANGCHANGED:
		case NPPN_WORDSTYLESUPDATED:
		case NPPN_EXTERNALLEXERBUFFER:
		case NPPN_FILEOPENED:
		case NPPN_DARKMODECHANGED:
			RevisarAmbasVistas();
			break;
		case NPPN_GLOBALMODIFIED:
		{
			// "Reemplazar todo" terminó en el documento (Buffer*) de hwndFrom.
			const IdBuffer id = reinterpret_cast<IdBuffer>(n->nmhdr.hwndFrom);
			bool visto = false;
			for (int v = 0; v < 2; ++v)
			{
				HWND hv = (v == 0) ? g_npp._scintillaMainHandle : g_npp._scintillaSecondHandle;
				if (hv != nullptr && g_bufVista[v] == id && EsStdoer(hv))
				{
					CompararRutas(hv, v);
					visto = true;
				}
			}
			if (!visto && g_rutas.find(id) != g_rutas.end())
				g_pendientes.insert(id);
			RevisarAmbasVistas();
			break;
		}
		case NPPN_FILECLOSED:
		{
			const IdBuffer id = static_cast<IdBuffer>(n->nmhdr.idFrom);
			g_rutas.erase(id);
			g_pendientes.erase(id);
			for (int v = 0; v < 2; ++v)
				if (g_bufVista[v] == id)
					g_bufVista[v] = 0;
			break;
		}
		case SCN_MODIFIED:
		{
			// Edición normal (con avisos activos): el texto cambió; se rehace la instantánea
			// y se deja de mostrar lo expuesto. Se hace en el siguiente SCN_UPDATEUI.
			if (n->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))
			{
				const int idx = IndiceVista(origen);
				if (idx >= 0)
				{
					g_sucia[idx] = true;
					if (!g_expuestos.empty())
						g_limpiarExpuestos = true;
				}
			}
			break;
		}
		case SCN_UPDATEUI:
		{
			const int idx = IndiceVista(origen);
			if (idx < 0)
				break;
			RevisarVista(origen, idx);
			if (g_vistas[idx].aplicado)
			{
				if (g_limpiarExpuestos)
				{
					g_limpiarExpuestos = false;
					LimpiarExpuestos(origen);
				}
				if (g_sucia[idx])
				{
					g_sucia[idx] = false;
					g_rutas[g_bufVista[idx]] = ListaRutas(origen);
				}
				ActualizarRevelado(origen, idx);
			}
			break;
		}
		case SCN_DWELLSTART:
		{
			const int idx = IndiceVista(origen);
			Log("mouse detenido pos=%lld vista=%d aplicado=%d", static_cast<long long>(n->position), idx, idx >= 0 ? (g_vistas[idx].aplicado ? 1 : 0) : -1);
			if (idx >= 0 && g_vistas[idx].aplicado && n->position >= 0)
				MostrarRecuadro(origen, n->position);
			break;
		}
		case SCN_DWELLEND:
			if (IndiceVista(origen) >= 0)
				OcultarRecuadro(origen);
			break;
		case SCN_HOTSPOTCLICK:
		{
			const int idx = IndiceVista(origen);
			if (idx >= 0 && g_vistas[idx].aplicado)
				ClicEnEnlace(origen, n->position, n->modifiers);
			break;
		}
		default:
			break;
		}
	}
}
