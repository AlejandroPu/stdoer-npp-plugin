// Stdoer — lexer externo para Notepad++ (interfaz tipo Lexilla).
//
// El lexer "stdoer" es una CAPA sobre el lexer de Python de Lexilla 5.4.5 (el mismo que
// usa Notepad++ 8.8.2), cuyo código no se modifica:
//   - Lex (coloreado) y todo lo demás se delegan tal cual al lexer de Python.
//   - Fold (contracción): se pide a Python el plegado por sangría, pero sus niveles no
//     van directo al documento; esta capa los intercepta, les incorpora las regiones
//     { } (ver Llaves.h) y recién entonces los escribe. Sin llaves con pareja se
//     escriben tal como los dio Python, así un documento sin llaves se contrae
//     exactamente igual que un .py.
//   - Sin colores: Stdoer.xml no define estilos, así que todo se ve como texto plano.
//   - Las propiedades que Notepad++ fija para Python y que a un lexer externo no le fija
//     nadie, se fijan aquí con los mismos valores.
//
// Código de Lexilla/Scintilla en third_party\lexilla (licencia HPND, ver ORIGIN.md).

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include "ILexer.h"
#include "LexerModule.h"
#include "Enlaces.h"
#include "Llaves.h"

extern const Lexilla::LexerModule lmPython;

namespace
{
	const char kNombreLexer[] = "stdoer";
	constexpr int kBaseDeNiveles = 0x400;  // SC_FOLDLEVELBASE: nivel sin información

	using Scintilla::IDocument;
	using Scintilla::ILexer5;

	// Documento "sombra" para el Fold de Python: reenvía todo al documento real, salvo
	// los niveles de plegado, que se anotan aquí en vez de escribirse.
	class DocumentoSombra final : public IDocument
	{
	public:
		explicit DocumentoSombra(IDocument* real, Sci_Position lineas)
			: real_(real), niveles_(static_cast<std::size_t>(lineas), -1) {}

		const std::vector<int>& niveles() const { return niveles_; }

		int SCI_METHOD Version() const override { return real_->Version(); }
		void SCI_METHOD SetErrorStatus(int e) override { real_->SetErrorStatus(e); }
		Sci_Position SCI_METHOD Length() const override { return real_->Length(); }
		// Python no ve las rutas de los enlaces: se le entregan como "xxx" (mismo largo), así
		// ni comillas, "#" ni llaves de una ruta cambian su coloreado ni su plegado.
		void SCI_METHOD GetCharRange(char* b, Sci_Position p, Sci_Position n) const override
		{
			real_->GetCharRange(b, p, n);
			if (n > 0)
				EnmascararRutas(b, p, n);
		}
		char SCI_METHOD StyleAt(Sci_Position p) const override { return real_->StyleAt(p); }
		Sci_Position SCI_METHOD LineFromPosition(Sci_Position p) const override { return real_->LineFromPosition(p); }
		Sci_Position SCI_METHOD LineStart(Sci_Position l) const override { return real_->LineStart(l); }
		int SCI_METHOD GetLevel(Sci_Position l) const override
		{
			return EnRango(l) && niveles_[static_cast<std::size_t>(l)] >= 0 ? niveles_[static_cast<std::size_t>(l)] : real_->GetLevel(l);
		}
		int SCI_METHOD SetLevel(Sci_Position l, int nivel) override
		{
			if (!EnRango(l))
				return nivel;
			const int previo = niveles_[static_cast<std::size_t>(l)];
			niveles_[static_cast<std::size_t>(l)] = nivel;
			return previo >= 0 ? previo : nivel;
		}
		int SCI_METHOD GetLineState(Sci_Position l) const override { return real_->GetLineState(l); }
		int SCI_METHOD SetLineState(Sci_Position l, int e) override { return real_->SetLineState(l, e); }
		void SCI_METHOD StartStyling(Sci_Position p) override { real_->StartStyling(p); }
		bool SCI_METHOD SetStyleFor(Sci_Position n, char e) override { return real_->SetStyleFor(n, e); }
		bool SCI_METHOD SetStyles(Sci_Position n, const char* e) override { return real_->SetStyles(n, e); }
		void SCI_METHOD DecorationSetCurrentIndicator(int i) override { real_->DecorationSetCurrentIndicator(i); }
		void SCI_METHOD DecorationFillRange(Sci_Position p, int v, Sci_Position n) override { real_->DecorationFillRange(p, v, n); }
		void SCI_METHOD ChangeLexerState(Sci_Position a, Sci_Position b) override { real_->ChangeLexerState(a, b); }
		int SCI_METHOD CodePage() const override { return real_->CodePage(); }
		bool SCI_METHOD IsDBCSLeadByte(char c) const override { return real_->IsDBCSLeadByte(c); }
		const char* SCI_METHOD BufferPointer() override { return real_->BufferPointer(); }
		int SCI_METHOD GetLineIndentation(Sci_Position l) override { return real_->GetLineIndentation(l); }
		Sci_Position SCI_METHOD LineEnd(Sci_Position l) const override { return real_->LineEnd(l); }
		Sci_Position SCI_METHOD GetRelativePosition(Sci_Position p, Sci_Position o) const override { return real_->GetRelativePosition(p, o); }
		int SCI_METHOD GetCharacterAndWidth(Sci_Position p, Sci_Position* w) const override { return real_->GetCharacterAndWidth(p, w); }

	private:
		bool EnRango(Sci_Position l) const { return l >= 0 && static_cast<std::size_t>(l) < niveles_.size(); }

		// Sustituye por 'x' las rutas de enlace que caen dentro de [p, p + n) del búfer b.
		// Los enlaces viven en una sola línea: se leen las líneas completas que toca el rango.
		void EnmascararRutas(char* b, Sci_Position p, Sci_Position n) const
		{
			const Sci_Position primera = real_->LineFromPosition(p);
			const Sci_Position ultima = real_->LineFromPosition(p + n);
			const Sci_Position desde = real_->LineStart(primera);
			const Sci_Position hasta = real_->LineEnd(ultima);
			if (hasta <= desde)
				return;
			std::string linea(static_cast<std::size_t>(hasta - desde), '\0');
			real_->GetCharRange(&linea[0], desde, hasta - desde);
			if (linea.find("__link[") == std::string::npos)
				return;
			// Se recorre línea por línea para que Buscar no cruce saltos de línea.
			for (Sci_Position l = primera; l <= ultima; ++l)
			{
				const Sci_Position ini = real_->LineStart(l);
				const Sci_Position fin = real_->LineEnd(l);
				if (fin <= ini)
					continue;
				const auto enlaces = Enlaces::Buscar(linea.data() + (ini - desde), static_cast<std::size_t>(fin - ini));
				for (const auto& e : enlaces)
				{
					Sci_Position a = ini + static_cast<Sci_Position>(e.inicioRuta());
					Sci_Position z = ini + static_cast<Sci_Position>(e.cierra);  // exclusivo
					a = std::max(a, p);
					z = std::min(z, p + n);
					for (Sci_Position k = a; k < z; ++k)
						b[k - p] = 'x';
				}
			}
		}

		IDocument* real_;
		std::vector<int> niveles_;
	};

	class LexerStdoer final : public ILexer5
	{
	public:
		explicit LexerStdoer(ILexer5* python) : py_(python) {}

		int SCI_METHOD Version() const override { return py_->Version(); }
		void SCI_METHOD Release() override { py_->Release(); delete this; }
		const char* SCI_METHOD PropertyNames() override { return py_->PropertyNames(); }
		int SCI_METHOD PropertyType(const char* n) override { return py_->PropertyType(n); }
		const char* SCI_METHOD DescribeProperty(const char* n) override { return py_->DescribeProperty(n); }
		Sci_Position SCI_METHOD PropertySet(const char* k, const char* v) override { return py_->PropertySet(k, v); }
		const char* SCI_METHOD DescribeWordListSets() override { return py_->DescribeWordListSets(); }
		Sci_Position SCI_METHOD WordListSet(int n, const char* wl) override { return py_->WordListSet(n, wl); }
		void SCI_METHOD Lex(Sci_PositionU p, Sci_Position l, int e, IDocument* d) override;
		void SCI_METHOD Fold(Sci_PositionU p, Sci_Position l, int e, IDocument* d) override;
		void* SCI_METHOD PrivateCall(int o, void* p) override { return py_->PrivateCall(o, p); }
		int SCI_METHOD LineEndTypesSupported() override { return py_->LineEndTypesSupported(); }
		int SCI_METHOD AllocateSubStyles(int b, int n) override { return py_->AllocateSubStyles(b, n); }
		int SCI_METHOD SubStylesStart(int b) override { return py_->SubStylesStart(b); }
		int SCI_METHOD SubStylesLength(int b) override { return py_->SubStylesLength(b); }
		int SCI_METHOD StyleFromSubStyle(int s) override { return py_->StyleFromSubStyle(s); }
		int SCI_METHOD PrimaryStyleFromStyle(int s) override { return py_->PrimaryStyleFromStyle(s); }
		void SCI_METHOD FreeSubStyles() override { py_->FreeSubStyles(); }
		void SCI_METHOD SetIdentifiers(int s, const char* i) override { py_->SetIdentifiers(s, i); }
		int SCI_METHOD DistanceToSecondaryStyles() override { return py_->DistanceToSecondaryStyles(); }
		const char* SCI_METHOD GetSubStyleBases() override { return py_->GetSubStyleBases(); }
		int SCI_METHOD NamedStyles() override { return py_->NamedStyles(); }
		const char* SCI_METHOD NameOfStyle(int s) override { return py_->NameOfStyle(s); }
		const char* SCI_METHOD TagsOfStyle(int s) override { return py_->TagsOfStyle(s); }
		const char* SCI_METHOD DescriptionOfStyle(int s) override { return py_->DescriptionOfStyle(s); }
		const char* SCI_METHOD GetName() override { return kNombreLexer; }
		int SCI_METHOD GetIdentifier() override { return py_->GetIdentifier(); }
		const char* SCI_METHOD PropertyGet(const char* k) override { return py_->PropertyGet(k); }

	private:
		ILexer5* py_;
	};

	// Coloreado: lo hace Python sobre un texto sin rutas de enlace; después se da a cada
	// enlace su estilo (ver Enlaces.h): "link[" y "]" son la zona clicable, y la ruta queda
	// oculta, salvo que el cursor o la selección la toquen (estado compartido con el plugin).
	// Los enlaces están en una sola línea, así que se estilan las líneas completas del rango.
	void EstilarEnlaces(IDocument* doc, Sci_PositionU inicio, Sci_Position largo)
	{
		const Sci_Position total = doc->Length();
		if (total <= 0 || largo <= 0)
			return;
		const Sci_Position fin = std::min<Sci_Position>(static_cast<Sci_Position>(inicio) + largo, total);
		const Sci_Position primera = doc->LineFromPosition(static_cast<Sci_Position>(inicio));
		const Sci_Position ultima = doc->LineFromPosition(fin);
		const Sci_Position desde = doc->LineStart(primera);
		const Sci_Position hasta = doc->LineEnd(ultima);
		if (hasta <= desde)
			return;
		std::string texto(static_cast<std::size_t>(hasta - desde), '\0');
		doc->GetCharRange(&texto[0], desde, hasta - desde);
		if (texto.find("__link[") == std::string::npos)
			return;
		for (Sci_Position l = primera; l <= ultima; ++l)
		{
			const Sci_Position ini = doc->LineStart(l);
			const Sci_Position fl = doc->LineEnd(l);
			if (fl <= ini)
				continue;
			for (const auto& e : Enlaces::Buscar(texto.data() + (ini - desde), static_cast<std::size_t>(fl - ini)))
			{
				doc->StartStyling(ini + static_cast<Sci_Position>(e.inicioZonaClic()));
				doc->SetStyleFor(static_cast<Sci_Position>(e.abre - e.inicioZonaClic() + 1), static_cast<char>(Enlaces::kEstiloEnlace));
				if (e.cierra > e.abre + 1)
					doc->SetStyleFor(static_cast<Sci_Position>(e.cierra - e.abre - 1), static_cast<char>(Enlaces::EstiloDeRuta(e, ini)));
				doc->SetStyleFor(1, static_cast<char>(Enlaces::kEstiloEnlace));
			}
		}
		// Python dejó el "ya estilado hasta" al final del rango; se restituye.
		doc->StartStyling(fin);
	}

	void SCI_METHOD LexerStdoer::Lex(Sci_PositionU inicio, Sci_Position largo, int estadoInicial, IDocument* doc)
	{
		DocumentoSombra enmascarado(doc, 0);
		py_->Lex(inicio, largo, estadoInicial, &enmascarado);
		EstilarEnlaces(doc, inicio, largo);
	}

	// Siempre se recalcula el documento entero, sea cual sea el rango que pida Scintilla:
	// que una "{" tenga pareja depende de texto lejano (y si se borra una "}" cambia el
	// plegado de líneas anteriores al cambio), así que un cálculo parcial dejaría niveles
	// viejos. Es lineal en el tamaño del documento.
	void SCI_METHOD LexerStdoer::Fold(Sci_PositionU inicio, Sci_Position largo, int estadoInicial, IDocument* doc)
	{
		const Sci_Position total = doc->Length();
		if (total <= 0)
		{
			py_->Fold(inicio, largo, estadoInicial, doc);
			return;
		}
		const Sci_Position lineas = doc->LineFromPosition(total) + 1;

		// 1) Python calcula el plegado por sangría de todo el documento, en la sombra.
		DocumentoSombra sombra(doc, lineas);
		py_->Fold(0, total, estadoInicial, &sombra);
		std::vector<int> niveles = sombra.niveles();

		// 2) Las llaves, mirando solo el texto.
		std::string texto(static_cast<std::size_t>(total), '\0');
		doc->GetCharRange(&texto[0], 0, total);
		std::vector<Llaves::Linea> marcas(static_cast<std::size_t>(lineas));
		for (Sci_Position i = 0; i < lineas; ++i)
		{
			const Sci_Position ini = doc->LineStart(i);
			const Sci_Position fin = doc->LineEnd(i);
			if (fin > ini)
				marcas[static_cast<std::size_t>(i)] = Llaves::Clasificar(texto.data() + ini, static_cast<std::size_t>(fin - ini));
		}
		if (Llaves::Emparejar(marcas) > 0)
			Llaves::Aplicar(marcas, niveles);

		// 3) Se escriben. SetLevel no avisa si el nivel no cambió. Las líneas que Python no
		//    tocó (-1) se dejan como estaban.
		for (Sci_Position i = 0; i < lineas; ++i)
		{
			const int nivel = niveles[static_cast<std::size_t>(i)];
			if (nivel >= kBaseDeNiveles)
				doc->SetLevel(i, nivel);
		}
	}
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

		Scintilla::ILexer5* python = lmPython.Create();
		if (python == nullptr)
			return nullptr;

		// Mismos valores que Notepad++ 8.8.2 fija para Python (ScintillaEditView.cpp:
		// setLexer y setPythonLexer). Un lexer externo no recibe ninguno.
		python->PropertySet("fold", "1");
		python->PropertySet("fold.compact", "0");
		python->PropertySet("fold.quotes.python", "1");
		python->PropertySet("lexer.python.decorator.attributes", "1");
		python->PropertySet("lexer.python.identifier.attributes", "1");
		return new LexerStdoer(python);
	}
}
