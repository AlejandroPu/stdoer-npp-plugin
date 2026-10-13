// Stdoer — external lexer for Notepad++ (Lexilla-style interface).
//
// The "stdoer" lexer is a LAYER over the Lexilla 5.4.5 Python lexer (the one Notepad++
// 8.8.2 uses), whose code is not modified:
//   - Lex (coloring) and everything else are delegated to the Python lexer as they are.
//   - Fold: Python is asked for the folding by indentation, but its levels do not go
//     straight to the document; this layer intercepts them, adds the { } regions (see
//     Braces.h) and only then writes them. Without matched braces they are written as
//     Python gave them, so a document without braces folds exactly like a .py file.
//   - No colors: Stdoer.xml defines no styles, so everything looks like plain text.
//   - The properties that Notepad++ sets for Python and that nobody sets for an external
//     lexer are set here with the same values.
//
// Lexilla/Scintilla code in third_party\lexilla (HPND license, see ORIGIN.md).

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

#include "ILexer.h"
#include "LexerModule.h"
#include "Links.h"
#include "Braces.h"

extern const Lexilla::LexerModule lmPython;

namespace
{
	const char kLexerName[] = "stdoer";
	constexpr int kLevelBase = 0x400;  // SC_FOLDLEVELBASE: level without information

	using Scintilla::IDocument;
	using Scintilla::ILexer5;

	// "Shadow" document for Python's Fold: forwards everything to the real document, except
	// the fold levels, which are recorded here instead of being written.
	class ShadowDocument final : public IDocument
	{
	public:
		explicit ShadowDocument(IDocument* real, Sci_Position lines)
			: real_(real), levels_(static_cast<std::size_t>(lines), -1) {}

		const std::vector<int>& levels() const { return levels_; }

		int SCI_METHOD Version() const override { return real_->Version(); }
		void SCI_METHOD SetErrorStatus(int e) override { real_->SetErrorStatus(e); }
		Sci_Position SCI_METHOD Length() const override { return real_->Length(); }
		// Python does not see the paths of the links: they are handed over as "xxx" (same
		// length), so no quote, "#" or brace in a path changes its coloring or folding.
		void SCI_METHOD GetCharRange(char* b, Sci_Position p, Sci_Position n) const override
		{
			real_->GetCharRange(b, p, n);
			if (n > 0)
				MaskPaths(b, p, n);
		}
		char SCI_METHOD StyleAt(Sci_Position p) const override { return real_->StyleAt(p); }
		Sci_Position SCI_METHOD LineFromPosition(Sci_Position p) const override { return real_->LineFromPosition(p); }
		Sci_Position SCI_METHOD LineStart(Sci_Position l) const override { return real_->LineStart(l); }
		int SCI_METHOD GetLevel(Sci_Position l) const override
		{
			return InRange(l) && levels_[static_cast<std::size_t>(l)] >= 0 ? levels_[static_cast<std::size_t>(l)] : real_->GetLevel(l);
		}
		int SCI_METHOD SetLevel(Sci_Position l, int level) override
		{
			if (!InRange(l))
				return level;
			const int previous = levels_[static_cast<std::size_t>(l)];
			levels_[static_cast<std::size_t>(l)] = level;
			return previous >= 0 ? previous : level;
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
		bool InRange(Sci_Position l) const { return l >= 0 && static_cast<std::size_t>(l) < levels_.size(); }

		// Replaces with 'x' the link paths that fall within [p, p + n) of buffer b.
		// Links live on a single line: the whole lines that the range touches are read.
		void MaskPaths(char* b, Sci_Position p, Sci_Position n) const
		{
			const Sci_Position firstLine = real_->LineFromPosition(p);
			const Sci_Position lastLine = real_->LineFromPosition(p + n);
			const Sci_Position from = real_->LineStart(firstLine);
			const Sci_Position to = real_->LineEnd(lastLine);
			if (to <= from)
				return;
			std::string text(static_cast<std::size_t>(to - from), '\0');
			real_->GetCharRange(&text[0], from, to - from);
			if (text.find("__link[") == std::string::npos)
				return;
			// Line by line so that Find does not cross line breaks.
			for (Sci_Position l = firstLine; l <= lastLine; ++l)
			{
				const Sci_Position start = real_->LineStart(l);
				const Sci_Position end = real_->LineEnd(l);
				if (end <= start)
					continue;
				const auto links = Links::Find(text.data() + (start - from), static_cast<std::size_t>(end - start));
				for (const auto& link : links)
				{
					Sci_Position a = start + static_cast<Sci_Position>(link.pathStart());
					Sci_Position z = start + static_cast<Sci_Position>(link.closeBracket);  // exclusive
					a = std::max(a, p);
					z = std::min(z, p + n);
					for (Sci_Position k = a; k < z; ++k)
						b[k - p] = 'x';
				}
			}
		}

		IDocument* real_;
		std::vector<int> levels_;
	};

	class StdoerLexer final : public ILexer5
	{
	public:
		explicit StdoerLexer(ILexer5* python) : py_(python) {}

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
		const char* SCI_METHOD GetName() override { return kLexerName; }
		int SCI_METHOD GetIdentifier() override { return py_->GetIdentifier(); }
		const char* SCI_METHOD PropertyGet(const char* k) override { return py_->PropertyGet(k); }

	private:
		ILexer5* py_;
	};

	// Coloring: Python does it over a text without link paths; afterwards each link is given
	// its style (see Links.h): "link[" and "]" are the clickable zone, and the path stays
	// hidden unless the cursor or the selection touch it (state shared with the plugin).
	// Links are on a single line, so the whole lines of the range are styled.
	void StyleLinks(IDocument* doc, Sci_PositionU start, Sci_Position length)
	{
		const Sci_Position total = doc->Length();
		if (total <= 0 || length <= 0)
			return;
		const Sci_Position end = std::min<Sci_Position>(static_cast<Sci_Position>(start) + length, total);
		const Sci_Position firstLine = doc->LineFromPosition(static_cast<Sci_Position>(start));
		const Sci_Position lastLine = doc->LineFromPosition(end);
		const Sci_Position from = doc->LineStart(firstLine);
		const Sci_Position to = doc->LineEnd(lastLine);
		if (to <= from)
			return;
		std::string text(static_cast<std::size_t>(to - from), '\0');
		doc->GetCharRange(&text[0], from, to - from);
		if (text.find("__link[") == std::string::npos)
			return;
		for (Sci_Position l = firstLine; l <= lastLine; ++l)
		{
			const Sci_Position lineStart = doc->LineStart(l);
			const Sci_Position lineEnd = doc->LineEnd(l);
			if (lineEnd <= lineStart)
				continue;
			for (const auto& link : Links::Find(text.data() + (lineStart - from), static_cast<std::size_t>(lineEnd - lineStart)))
			{
				doc->StartStyling(lineStart + static_cast<Sci_Position>(link.clickZoneStart()));
				doc->SetStyleFor(static_cast<Sci_Position>(link.openBracket - link.clickZoneStart() + 1), static_cast<char>(Links::kStyleLink));
				if (link.closeBracket > link.openBracket + 1)
					doc->SetStyleFor(static_cast<Sci_Position>(link.closeBracket - link.openBracket - 1), static_cast<char>(Links::PathStyle(link, lineStart)));
				doc->SetStyleFor(1, static_cast<char>(Links::kStyleLink));
			}
		}
		// Python left the "styled up to" mark at the end of the range; it is restored.
		doc->StartStyling(end);
	}

	void SCI_METHOD StdoerLexer::Lex(Sci_PositionU start, Sci_Position length, int initialState, IDocument* doc)
	{
		ShadowDocument masked(doc, 0);
		py_->Lex(start, length, initialState, &masked);
		StyleLinks(doc, start, length);
	}

	// The whole document is always recomputed, whatever range Scintilla asks for: whether a
	// "{" has a match depends on distant text (and deleting a "}" changes the folding of
	// lines before the change), so a partial computation would leave old levels. It is
	// linear in the size of the document.
	void SCI_METHOD StdoerLexer::Fold(Sci_PositionU start, Sci_Position length, int initialState, IDocument* doc)
	{
		const Sci_Position total = doc->Length();
		if (total <= 0)
		{
			py_->Fold(start, length, initialState, doc);
			return;
		}
		const Sci_Position lineCount = doc->LineFromPosition(total) + 1;

		// 1) Python computes the folding by indentation of the whole document, in the shadow.
		ShadowDocument shadow(doc, lineCount);
		py_->Fold(0, total, initialState, &shadow);
		std::vector<int> levels = shadow.levels();

		// 2) The braces, looking only at the text.
		std::string text(static_cast<std::size_t>(total), '\0');
		doc->GetCharRange(&text[0], 0, total);
		std::vector<Braces::Line> marks(static_cast<std::size_t>(lineCount));
		for (Sci_Position i = 0; i < lineCount; ++i)
		{
			const Sci_Position lineStart = doc->LineStart(i);
			const Sci_Position lineEnd = doc->LineEnd(i);
			if (lineEnd > lineStart)
				marks[static_cast<std::size_t>(i)] = Braces::Classify(text.data() + lineStart, static_cast<std::size_t>(lineEnd - lineStart));
		}
		if (Braces::Match(marks) > 0)
			Braces::Apply(marks, levels);

		// 3) They are written. SetLevel does not notify if the level did not change. The
		//    lines that Python did not touch (-1) are left as they were.
		for (Sci_Position i = 0; i < lineCount; ++i)
		{
			const int level = levels[static_cast<std::size_t>(i)];
			if (level >= kLevelBase)
				doc->SetLevel(i, level);
		}
	}
}

extern "C"
{
	__declspec(dllexport) int __stdcall GetLexerCount()
	{
		return 1;
	}

	__declspec(dllexport) void __stdcall GetLexerName(unsigned int index, char* name, int length)
	{
		if (name == nullptr || length <= 0)
			return;
		name[0] = '\0';
		if (index == 0 && static_cast<size_t>(length) > sizeof(kLexerName) - 1)
			std::memcpy(name, kLexerName, sizeof(kLexerName));
	}

	__declspec(dllexport) Scintilla::ILexer5* __stdcall CreateLexer(const char* name)
	{
		if (name == nullptr || std::strcmp(name, kLexerName) != 0)
			return nullptr;

		Scintilla::ILexer5* python = lmPython.Create();
		if (python == nullptr)
			return nullptr;

		// Same values that Notepad++ 8.8.2 sets for Python (ScintillaEditView.cpp:
		// setLexer and setPythonLexer). An external lexer receives none of them.
		python->PropertySet("fold", "1");
		python->PropertySet("fold.compact", "0");
		python->PropertySet("fold.quotes.python", "1");
		python->PropertySet("lexer.python.decorator.attributes", "1");
		python->PropertySet("lexer.python.identifier.attributes", "1");
		return new StdoerLexer(python);
	}
}
