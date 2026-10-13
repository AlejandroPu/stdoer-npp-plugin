// Stdoer — links in the Notepad++ window. See LinksUI.h.

#define NOMINMAX
#include "LinksUI.h"

#include <windowsx.h>
#include <commctrl.h>
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

#include "Links.h"

namespace
{
	NppData g_npp;

	// State per view (main and secondary).
	struct ViewState
	{
		bool applied = false;         // the link styles are set in this view
		long long revealedStart = -1; // interval shown by the last update
		long long revealedEnd = -1;
	};
	ViewState g_views[2];
	bool g_tipIsOurs = false;         // the tooltip that is visible was shown by us

	// --- path changes that cannot be seen ("Replace All") ---
	// Notepad++ replaces with SCI_REPLACETARGET, which does not respect non-modifiable styles,
	// and during the operation it turns off modification notifications; when it finishes it
	// sends NPPN_GLOBALMODIFIED. So, per document, the list of paths is kept as it was the last
	// time the text was seen to change, and on receiving that notification it is compared.
	using BufferId = std::uintptr_t;
	std::map<BufferId, std::vector<std::string>> g_paths;   // paths of each document (snapshot)
	std::set<BufferId> g_pending;                           // modified by "Replace All" while out of view
	BufferId g_viewBuffer[2] = {0, 0};                      // active document of each view
	bool g_dirty[2] = {false, false};                       // the text changed: the snapshot must be redone
	bool g_clearExposed = false;                            // the text changed: stop showing what was exposed
	std::vector<std::pair<long long, long long>> g_exposed;
	bool g_hasAnnotations = false;                          // we put warning annotations

	// --- optional log for tests: if the variable STDOER_LOG exists, it is written there ---
	void Log(const char* format, ...)
	{
		static wchar_t path[MAX_PATH] = {};
		static int state = 0;  // 0 not looked at, 1 no log, 2 with log
		if (state == 0)
			state = (::GetEnvironmentVariableW(L"STDOER_LOG", path, MAX_PATH) > 0) ? 2 : 1;
		if (state != 2)
			return;
		FILE* f = nullptr;
		if (_wfopen_s(&f, path, L"ab") != 0 || f == nullptr)
			return;
		va_list ap;
		va_start(ap, format);
		std::vfprintf(f, format, ap);
		va_end(ap);
		std::fputc('\n', f);
		std::fclose(f);
	}

	// For the automated tests: with STDOER_NO_SHELL defined, the plugin logs what it would open
	// but does not call Windows (so the tests do not open programs on anyone's screen).
	bool NoShell()
	{
		static int state = 0;
		if (state == 0)
			state = (::GetEnvironmentVariableW(L"STDOER_NO_SHELL", nullptr, 0) > 0) ? 2 : 1;
		return state == 2;
	}

	LRESULT Sci(HWND h, UINT m, WPARAM w = 0, LPARAM l = 0)
	{
		return ::SendMessageW(h, m, w, l);
	}

	int ViewIndex(HWND h)
	{
		if (h == g_npp._scintillaMainHandle)
			return 0;
		if (h == g_npp._scintillaSecondHandle)
			return 1;
		return -1;
	}

	bool IsStdoer(HWND h)
	{
		char name[32] = {};
		Sci(h, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<LPARAM>(name));
		return std::strcmp(name, "stdoer") == 0;
	}

	// --- view styles ---

	// Colors that come from the active theme (Scintilla's default style is the Notepad++
	// theme's), not fixed ones: that way dark mode and any theme are respected.
	COLORREF Blend(COLORREF a, COLORREF b)
	{
		return RGB((GetRValue(a) + GetRValue(b)) / 2, (GetGValue(a) + GetGValue(b)) / 2, (GetBValue(a) + GetBValue(b)) / 2);
	}

	// The visible path goes halfway between the text color and the background color: it stands
	// out from the rest without ceasing to be visible in any theme.
	COLORREF VisiblePathColor(HWND h)
	{
		return Blend(static_cast<COLORREF>(Sci(h, SCI_STYLEGETFORE, STYLE_DEFAULT)), static_cast<COLORREF>(Sci(h, SCI_STYLEGETBACK, STYLE_DEFAULT)));
	}

	// Color of "link[]" on mouse hover: light blue on dark backgrounds and dark blue on light ones.
	COLORREF HoverColor(HWND h)
	{
		const COLORREF background = static_cast<COLORREF>(Sci(h, SCI_STYLEGETBACK, STYLE_DEFAULT));
		const int brightness = (GetRValue(background) * 299 + GetGValue(background) * 587 + GetBValue(background) * 114) / 1000;
		return brightness < 128 ? RGB(0x66, 0xB3, 0xFF) : RGB(0x00, 0x66, 0xCC);
	}
	// The path (style 50) is invisible and not modifiable: neither Backspace, Delete, typing over
	// a selection, cut or paste touch it. While the cursor or the selection touch it, it is
	// shown (style 51) and then it can be edited, in plain view.
	void ApplyStyles(HWND h, int idx)
	{
		Sci(h, SCI_STYLESETVISIBLE, Links::kStyleHiddenPath, 0);
		Sci(h, SCI_STYLESETCHANGEABLE, Links::kStyleHiddenPath, 0);
		Sci(h, SCI_STYLESETVISIBLE, Links::kStyleVisiblePath, 1);
		Sci(h, SCI_STYLESETCHANGEABLE, Links::kStyleVisiblePath, 1);
		Sci(h, SCI_STYLESETFORE, Links::kStyleVisiblePath, VisiblePathColor(h));
		Sci(h, SCI_STYLESETHOTSPOT, Links::kStyleLink, 1);
		Sci(h, SCI_SETHOTSPOTACTIVEFORE, 1, HoverColor(h));
		Sci(h, SCI_SETHOTSPOTACTIVEUNDERLINE, 1, 0);
		Sci(h, SCI_SETHOTSPOTSINGLELINE, 1, 0);
		Sci(h, SCI_SETMOUSEDWELLTIME, 500, 0);
		g_views[idx].applied = true;
		Log("styles applied view %d", idx);
	}

	// When the document stops being .stdoer the normal values are restored (another lexer may
	// use those style numbers).
	void RemoveStyles(HWND h, int idx)
	{
		for (int e : {Links::kStyleHiddenPath, Links::kStyleVisiblePath})
		{
			Sci(h, SCI_STYLESETVISIBLE, e, 1);
			Sci(h, SCI_STYLESETCHANGEABLE, e, 1);
		}
		Sci(h, SCI_STYLESETHOTSPOT, Links::kStyleLink, 0);
		Sci(h, SCI_SETHOTSPOTACTIVEFORE, 0, 0);
		Sci(h, SCI_SETHOTSPOTACTIVEUNDERLINE, 0, 0);
		Sci(h, SCI_SETMOUSEDWELLTIME, SC_TIME_FOREVER, 0);
		g_views[idx].applied = false;
		g_views[idx].revealedStart = g_views[idx].revealedEnd = -1;
		Log("styles removed view %d", idx);
	}

	void CheckActiveDocument(HWND h, int idx);

	// May be called at any time: leaves the view as its current lexer calls for.
	// It also repairs the case where Notepad++ reset the styles without notice.
	void CheckView(HWND h, int idx)
	{
		if (h == nullptr || idx < 0)
			return;
		if (IsStdoer(h))
		{
			CheckActiveDocument(h, idx);
			if (!g_views[idx].applied || Sci(h, SCI_STYLEGETVISIBLE, Links::kStyleHiddenPath) != 0 ||
				Sci(h, SCI_STYLEGETCHANGEABLE, Links::kStyleHiddenPath) != 0 ||
				static_cast<COLORREF>(Sci(h, SCI_STYLEGETFORE, Links::kStyleVisiblePath)) != VisiblePathColor(h))
				ApplyStyles(h, idx);
		}
		else if (g_views[idx].applied)
			RemoveStyles(h, idx);
	}

	void CheckBothViews()
	{
		CheckView(g_npp._scintillaMainHandle, 0);
		CheckView(g_npp._scintillaSecondHandle, 1);
	}

	// --- text of a line ---

	std::string ReadText(HWND h, long long start, long long end)
	{
		if (end <= start)
			return std::string();
		std::string s(static_cast<std::size_t>(end - start), '\0');
		Sci_TextRangeFull tr;
		tr.chrg.cpMin = static_cast<Sci_Position>(start);
		tr.chrg.cpMax = static_cast<Sci_Position>(end);
		tr.lpstrText = &s[0];
		Sci(h, SCI_GETTEXTRANGEFULL, 0, reinterpret_cast<LPARAM>(&tr));
		return s;
	}

	struct LineWithLinks
	{
		long long start = 0;  // absolute position of the first byte
		std::string text;
		std::vector<Links::Link> links;
	};

	LineWithLinks ReadLine(HWND h, long long line)
	{
		LineWithLinks r;
		r.start = Sci(h, SCI_POSITIONFROMLINE, static_cast<WPARAM>(line));
		const long long end = Sci(h, SCI_GETLINEENDPOSITION, static_cast<WPARAM>(line));
		r.text = ReadText(h, r.start, end);
		r.links = Links::Find(r.text.data(), r.text.size());
		return r;
	}

	// --- show the path while the cursor or the selection touch it ---

	// Gives the paths of the lines [posStart, posEnd] the style that corresponds to them
	// according to the interval currently shown (the same criterion the lexer uses).
	void RestyleRange(HWND h, long long posStart, long long posEnd)
	{
		if (posStart < 0)
			return;
		Log("  RestyleRange %lld..%lld", posStart, posEnd);
		const long long total = Sci(h, SCI_GETLENGTH);
		posEnd = std::min(posEnd, total);
		const long long firstLine = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(posStart));
		long long lastLine = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(posEnd));
		// A huge range (Ctrl+A in a very long document) is colored again as a whole.
		if (lastLine - firstLine > 20000)
		{
			Sci(h, SCI_COLOURISE, 0, -1);
			return;
		}
		const long long endStyled = Sci(h, SCI_GETENDSTYLED);
		for (long long l = firstLine; l <= lastLine; ++l)
		{
			const LineWithLinks line = ReadLine(h, l);
			for (const auto& link : line.links)
			{
				if (link.closeBracket <= link.openBracket + 1)
					continue;
				const int style = Links::PathStyle(link, line.start);
				Sci(h, SCI_STARTSTYLING, static_cast<WPARAM>(line.start + static_cast<long long>(link.pathStart())), 0);
				Sci(h, SCI_SETSTYLING, static_cast<WPARAM>(link.closeBracket - link.openBracket - 1), style);
			}
		}
		Sci(h, SCI_STARTSTYLING, static_cast<WPARAM>(endStyled), 0);
	}

	void UpdateRevealed(HWND h, int idx)
	{
		long long start = -1, end = -1;
		const long long n = std::min<long long>(Sci(h, SCI_GETSELECTIONS), 1000);
		for (long long i = 0; i < n; ++i)
		{
			const long long a = Sci(h, SCI_GETSELECTIONNSTART, static_cast<WPARAM>(i));
			const long long b = Sci(h, SCI_GETSELECTIONNEND, static_cast<WPARAM>(i));
			if (start < 0 || a < start)
				start = a;
			if (b > end)
				end = b;
		}
		ViewState& v = g_views[idx];
		if (start == v.revealedStart && end == v.revealedEnd)
			return;
		const long long oldStart = v.revealedStart, oldEnd = v.revealedEnd;
		v.revealedStart = start;
		v.revealedEnd = end;
		Links::SetRevealed(start, end);
		RestyleRange(h, oldStart, oldEnd);
		RestyleRange(h, start, end);
	}

	// --- paths of the whole document (to detect changes that cannot be seen) ---

	std::vector<std::string> PathList(HWND h)
	{
		std::vector<std::string> r;
		const long long total = Sci(h, SCI_GETLENGTH);
		if (total <= 0)
			return r;
		const std::string text = ReadText(h, 0, total);
		if (text.find("__link[") == std::string::npos)
			return r;
		// Links are on one line: it goes line by line.
		std::size_t start = 0;
		while (start <= text.size())
		{
			std::size_t end = text.find_first_of("\r\n", start);
			if (end == std::string::npos)
				end = text.size();
			for (const auto& link : Links::Find(text.data() + start, end - start))
				r.push_back(Links::Trim(text.substr(start + link.openBracket + 1, link.closeBracket - link.openBracket - 1)));
			start = end + 1;
		}
		return r;
	}

	// Paths in `now` that were not in `before` (counting repetitions).
	std::multiset<std::string> NewPaths(const std::vector<std::string>& before, const std::vector<std::string>& now)
	{
		std::multiset<std::string> old(before.begin(), before.end());
		std::multiset<std::string> added;
		for (const auto& p : now)
		{
			auto it = old.find(p);
			if (it != old.end())
				old.erase(it);
			else
				added.insert(p);
		}
		return added;
	}

	void ClearExposed(HWND h)
	{
		if (g_exposed.empty())
			return;
		Log("  ClearExposed (%d zones)", static_cast<int>(g_exposed.size()));
		const auto old = g_exposed;
		g_exposed.clear();
		if (g_hasAnnotations)
		{
			Sci(h, SCI_ANNOTATIONCLEARALL);
			g_hasAnnotations = false;
		}
		Links::SetExposed(g_exposed);
		for (const auto& z : old)
			RestyleRange(h, z.first, z.second);
		Log("exposed: no longer shown");
	}

	// Shows the links whose path appears in `added` and warns with an annotation.
	void Expose(HWND h, const std::multiset<std::string>& addedInput)
	{
		std::multiset<std::string> added = addedInput;
		ClearExposed(h);
		std::vector<std::pair<long long, long long>> zones;
		const long long lineCount = Sci(h, SCI_GETLINECOUNT);
		for (long long l = 0; l < lineCount && !added.empty(); ++l)
		{
			const long long start = Sci(h, SCI_POSITIONFROMLINE, static_cast<WPARAM>(l));
			const long long end = Sci(h, SCI_GETLINEENDPOSITION, static_cast<WPARAM>(l));
			if (end - start < 8)
				continue;
			const std::string text = ReadText(h, start, end);
			for (const auto& link : Links::Find(text.data(), text.size()))
			{
				auto it = added.find(Links::Trim(text.substr(link.openBracket + 1, link.closeBracket - link.openBracket - 1)));
				if (it == added.end())
					continue;
				added.erase(it);
				zones.emplace_back(start + static_cast<long long>(link.pathStart()), start + static_cast<long long>(link.closeBracket));
			}
		}
		if (zones.empty())
			return;
		g_exposed = zones;
		Links::SetExposed(g_exposed);
		for (const auto& z : zones)
			RestyleRange(h, z.first, z.second);
		// Persistent warning: an annotation (a line of text under the link; it is not part of the
		// document). A help tooltip would not do here: it is lost when the focus changes.
		Sci(h, SCI_ANNOTATIONSETVISIBLE, ANNOTATION_BOXED, 0);
		for (const auto& z : zones)
		{
			const long long line = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(z.first));
			static const char warning[] = "The path of this link was changed without being visible (it is now visible). Ctrl+Z undoes it.";
			Sci(h, SCI_ANNOTATIONSETTEXT, static_cast<WPARAM>(line), reinterpret_cast<LPARAM>(warning));
			Sci(h, SCI_ANNOTATIONSETSTYLE, static_cast<WPARAM>(line), Links::kStyleVisiblePath);
		}
		g_hasAnnotations = true;
		Log("exposed: %d link(s) with a path changed in a way that is not visible", static_cast<int>(zones.size()));
	}

	BufferId ActiveBuffer(int view)
	{
		const LRESULT index = ::SendMessageW(g_npp._nppHandle, NPPM_GETCURRENTDOCINDEX, 0, view);
		return static_cast<BufferId>(::SendMessageW(g_npp._nppHandle, NPPM_GETBUFFERIDFROMPOS, static_cast<WPARAM>(index), view));
	}

	// Compares the document's current paths in the view with its snapshot.
	void ComparePaths(HWND h, int idx)
	{
		const BufferId id = g_viewBuffer[idx];
		Log("  ComparePaths view %d id=%llu", idx, static_cast<unsigned long long>(id));
		const std::vector<std::string> now = PathList(h);
		auto it = g_paths.find(id);
		if (it != g_paths.end())
		{
			const auto added = NewPaths(it->second, now);
			if (!added.empty())
				Expose(h, added);
		}
		g_paths[id] = now;
	}

	// Keeps up to date which document is in each view and its snapshot of paths.
	void CheckActiveDocument(HWND h, int idx)
	{
		const BufferId id = ActiveBuffer(idx);
		if (id == 0 || id == g_viewBuffer[idx])
			return;
		ClearExposed(h);
		g_viewBuffer[idx] = id;
		g_dirty[idx] = false;
		if (g_pending.erase(id) > 0)
			ComparePaths(h, idx);            // it was changed while out of view
		else if (g_paths.find(id) == g_paths.end())
			g_paths[id] = PathList(h);       // first time it is seen: this is how it is
	}

	// --- check whether a path exists, without being able to freeze Notepad++ ---

	enum class State { Exists, Missing, NoResponse };
	struct Existence
	{
		State state = State::Missing;
		bool folder = false;
	};

	struct CacheEntry
	{
		std::shared_future<DWORD> attributes;
		ULONGLONG created = 0;
	};
	std::mutex g_cacheMutex;
	std::map<std::wstring, CacheEntry> g_cache;

	std::wstring ToLower(std::wstring s)
	{
		std::transform(s.begin(), s.end(), s.begin(), [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
		return s;
	}

	// GetFileAttributes can hang for minutes (a disconnected drive, a server that does not
	// respond). It is queried on another thread and waited for at most `wait` ms. A thread that
	// does not finish is left running; while it is still pending (up to 60 s) no other
	// identical one is launched.
	Existence CheckExists(const std::wstring& path, DWORD wait)
	{
		const std::wstring key = ToLower(path);
		const ULONGLONG now = ::GetTickCount64();
		std::shared_future<DWORD> future;
		{
			std::lock_guard<std::mutex> lock(g_cacheMutex);
			if (g_cache.size() > 200)
			{
				for (auto it = g_cache.begin(); it != g_cache.end();)
				{
					const bool ready = it->second.attributes.wait_for(std::chrono::seconds(0)) == std::future_status::ready;
					it = (ready && now - it->second.created > 300000) ? g_cache.erase(it) : std::next(it);
				}
			}
			bool launch = true;
			auto it = g_cache.find(key);
			if (it != g_cache.end())
			{
				const bool ready = it->second.attributes.wait_for(std::chrono::seconds(0)) == std::future_status::ready;
				if (ready)
					launch = now - it->second.created > 3000;   // recent result: it is reused
				else if (now - it->second.created > 60000)
					return Existence{State::NoResponse, false};  // it has been going too long: no insisting
				else
					launch = false;                              // query in progress: that one is awaited
			}
			if (launch)
			{
				auto promise = std::make_shared<std::promise<DWORD>>();
				CacheEntry e;
				e.attributes = promise->get_future().share();
				e.created = now;
				g_cache[key] = e;
				const std::wstring copy = path;
				std::thread([promise, copy]() { promise->set_value(::GetFileAttributesW(copy.c_str())); }).detach();
			}
			future = g_cache[key].attributes;
		}
		if (future.wait_for(std::chrono::milliseconds(wait)) != std::future_status::ready)
			return Existence{State::NoResponse, false};
		const DWORD a = future.get();
		if (a == INVALID_FILE_ATTRIBUTES)
			return Existence{State::Missing, false};
		return Existence{State::Exists, (a & FILE_ATTRIBUTE_DIRECTORY) != 0};
	}

	// --- path of a link ---

	std::wstring ToWide(HWND h, const std::string& bytes)
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

	// Finds the link whose zone [from, to] (indexes in the line) contains the position.
	// `clickZone` = true: only "link[...]" ; false: the whole link, with the "_".
	bool LinkAt(HWND h, long long pos, bool clickZone, LineWithLinks& line, Links::Link& found)
	{
		if (pos < 0)
			return false;
		const long long l = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(pos));
		line = ReadLine(h, l);
		const long long rel = pos - line.start;
		for (const auto& link : line.links)
		{
			const long long from = static_cast<long long>(clickZone ? link.clickZoneStart() : link.start);
			if (rel >= from && rel <= static_cast<long long>(link.closeBracket))
			{
				found = link;
				return true;
			}
		}
		return false;
	}

	std::string PathBytes(const LineWithLinks& line, const Links::Link& link)
	{
		return Links::Trim(line.text.substr(link.openBracket + 1, link.closeBracket - link.openBracket - 1));
	}

	// --- tooltip on mouse hover ---

	void ShowTip(HWND h, long long pos)
	{
		LineWithLinks line;
		Links::Link link;
		if (!LinkAt(h, pos, false, line, link))
			return;
		if (Sci(h, SCI_CALLTIPACTIVE) != 0)
			return;  // there is already another tooltip (e.g., from autocompletion)
		const std::string bytes = PathBytes(line, link);
		std::string text = bytes;
		if (bytes.empty())
			text = "(empty path)";
		else
		{
			const std::wstring path = ToWide(h, bytes);
			switch (Links::ClassifyTarget(path))
			{
			case Links::TargetKind::Web:
				break;  // the address as it is: the network is not touched to check it
			case Links::TargetKind::Rejected:
				text += "\n(not opened: only http and https addresses are opened)";
				break;
			case Links::TargetKind::Path:
				if (!Links::IsAbsolutePath(path))
					text += "\n(relative path: not opened)";
				else
				{
					const Existence ex = CheckExists(path, 300);
					if (ex.state == State::Missing)
						text += "\n(does not exist)";
					else if (ex.state == State::NoResponse)
						text += "\n(no response: could not check whether it exists)";
				}
				break;
			}
		}
		Sci(h, SCI_CALLTIPSHOW, static_cast<WPARAM>(line.start + static_cast<long long>(link.start)), reinterpret_cast<LPARAM>(text.c_str()));
		g_tipIsOurs = true;
		std::string oneLine = text;
		for (auto& c : oneLine)
			if (c == '\n')
				c = '|';
		Log("tooltip: %s", oneLine.c_str());
	}

	void HideTip(HWND h)
	{
		if (g_tipIsOurs)
		{
			Sci(h, SCI_CALLTIPCANCEL);
			g_tipIsOurs = false;
		}
	}

	// --- open (a click never runs anything) ---

	void ShowInFolder(const std::wstring& path)
	{
		if (path.find(L'"') != std::wstring::npos)
			return;  // a Windows path has no quotes: it is not passed to explorer.exe
		const std::wstring args = L"/select,\"" + path + L"\"";
		if (!NoShell())
			::ShellExecuteW(nullptr, L"open", L"explorer.exe", args.c_str(), nullptr, SW_SHOWNORMAL);
		Log("open: containing folder of %ls", path.c_str());
	}

	// Would Windows open this type with a separate program? If the "open" action is the file
	// itself ("%1" ...), opening it would run it; if there is no action, the "Open with" dialog
	// would appear. In both cases it is not opened.
	bool SafeAssociation(const std::wstring& extension)
	{
		wchar_t cmd[1024] = {};
		DWORD n = static_cast<DWORD>(sizeof(cmd) / sizeof(cmd[0]));
		if (FAILED(::AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_COMMAND, extension.c_str(), L"open", cmd, &n)))
			return false;
		const std::wstring c = ToLower(cmd);
		std::size_t i = c.find_first_not_of(L" \t");
		if (i == std::wstring::npos)
			return false;
		if (c.compare(i, 4, L"\"%1\"") == 0 || c.compare(i, 2, L"%1") == 0)
			return false;
		return true;
	}

	void OpenPath(HWND h, const std::wstring& path)
	{
		if (!Links::IsAbsolutePath(path))
		{
			Log("open: path is not absolute, nothing done: %ls", path.c_str());
			return;
		}
		const ULONGLONG t0 = ::GetTickCount64();
		const Existence ex = CheckExists(path, 1000);
		Log("open: existence check took %llu ms", static_cast<unsigned long long>(::GetTickCount64() - t0));
		if (ex.state != State::Exists)
		{
			Log("open: %ls %s, nothing done", path.c_str(), ex.state == State::Missing ? "does not exist" : "no response");
			return;
		}
		if (ex.folder)
		{
			if (!NoShell())
				::ShellExecuteW(h, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
			Log("open: folder %ls", path.c_str());
			return;
		}
		const std::wstring ext = Links::ExtensionOf(path);
		switch (Links::ClassifyExtension(ext))
		{
		case Links::Action::Notepad:
			::SendMessageW(g_npp._nppHandle, NPPM_DOOPEN, 0, reinterpret_cast<LPARAM>(path.c_str()));
			Log("open: in Notepad++ %ls", path.c_str());
			break;
		case Links::Action::Windows:
			if (SafeAssociation(ext))
			{
				std::wstring folder = path.substr(0, path.find_last_of(L"\\/"));
				if (!NoShell())
					::ShellExecuteW(h, L"open", path.c_str(), nullptr, folder.c_str(), SW_SHOWNORMAL);
				Log("open: with Windows %ls", path.c_str());
			}
			else
				ShowInFolder(path);
			break;
		case Links::Action::Folder:
			ShowInFolder(path);
			break;
		}
	}

	// Containing folder of the link: if the file exists it is shown selected; if not, but its
	// folder does, that folder is opened. It never runs anything.
	void OpenContainingFolder(HWND h, const std::wstring& path)
	{
		if (!Links::IsAbsolutePath(path) || path.find(L'"') != std::wstring::npos)
		{
			Log("open: containing folder of an invalid path, nothing done: %ls", path.c_str());
			return;
		}
		const Existence ex = CheckExists(path, 1000);
		if (ex.state == State::Exists)
		{
			ShowInFolder(path);
			return;
		}
		const std::size_t slash = path.find_last_of(L"\\/");
		if (slash == std::wstring::npos || slash < 3)
		{
			Log("open: containing folder of %ls: no folder to open", path.c_str());
			return;
		}
		const std::wstring folder = path.substr(0, slash);
		const Existence ef = CheckExists(folder, 1000);
		if (ef.state == State::Exists && ef.folder)
		{
			if (!NoShell())
				::ShellExecuteW(h, L"open", folder.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
			Log("open: folder %ls (the file does not exist)", folder.c_str());
		}
		else
			Log("open: containing folder of %ls: the folder does not exist either, nothing done", path.c_str());
	}

	// Opens what a link says. ⛔ Only http and https addresses are opened (in the browser) and
	// paths under the usual rules; any other scheme is not opened.
	void OpenTarget(HWND h, const std::wstring& text)
	{
		switch (Links::ClassifyTarget(text))
		{
		case Links::TargetKind::Web:
			if (!NoShell())
				::ShellExecuteW(h, L"open", text.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
			Log("open: browser %ls", text.c_str());
			break;
		case Links::TargetKind::Rejected:
			Log("open: scheme or address not allowed, nothing done: %ls", text.c_str());
			break;
		case Links::TargetKind::Path:
			OpenPath(h, text);
			break;
		}
	}

	void LinkClicked(HWND h, long long pos, int modifiers)
	{
		Log("click on active zone pos=%lld modifiers=%d", pos, modifiers);
		if (modifiers & (SCMOD_SHIFT | SCMOD_CTRL | SCMOD_ALT))
			return;  // with modifiers it is selecting, not opening
		LineWithLinks line;
		Links::Link link;
		if (!LinkAt(h, pos, true, line, link))
		{
			Log("click: position %lld is not in the clickable zone of any link", pos);
			return;
		}
		HideTip(h);
		OpenTarget(h, ToWide(h, PathBytes(line, link)));
	}

	// === right-click menu ===

	// A link under the mouse (or the cursor): active (__link[) or disabled (_link[).
	struct MenuLink
	{
		bool active = false;
		LineWithLinks line;
		Links::Link link;
		std::wstring target;             // path or address, as written
		Links::TargetKind kind = Links::TargetKind::Path;
	};

	enum MenuId { kMenuOpen = 1, kMenuFolder, kMenuDisable, kMenuEnable };

	struct Option
	{
		int id;
		const wchar_t* text;
		bool enabled;
	};

	// Is there a link (active or disabled) that contains the character at `pos`?
	bool FindMenuLink(HWND h, long long pos, MenuLink& r)
	{
		if (pos < 0)
			return false;
		const long long l = Sci(h, SCI_LINEFROMPOSITION, static_cast<WPARAM>(pos));
		r.line = ReadLine(h, l);
		const long long rel = pos - r.line.start;
		const auto contains = [rel](const Links::Link& link) {
			return rel >= static_cast<long long>(link.start) && rel <= static_cast<long long>(link.closeBracket);
		};
		bool found = false;
		for (const auto& link : r.line.links)
			if (contains(link))
			{
				r.active = true;
				r.link = link;
				found = true;
				break;
			}
		if (!found)
			for (const auto& link : Links::FindDisabled(r.line.text.data(), r.line.text.size()))
				if (contains(link))
				{
					r.active = false;
					r.link = link;
					found = true;
					break;
				}
		if (!found)
			return false;
		r.target = ToWide(h, PathBytes(r.line, r.link));
		r.kind = Links::ClassifyTarget(r.target);
		return true;
	}

	// The menu options for this link (the test mode uses them too).
	std::vector<Option> OptionsFor(HWND h, const MenuLink& m)
	{
		std::vector<Option> o;
		const bool editable = Sci(h, SCI_GETREADONLY) == 0;
		if (!m.active)
		{
			o.push_back({kMenuEnable, L"Enable link", editable});
			return o;
		}
		bool canOpen = false;
		switch (m.kind)
		{
		case Links::TargetKind::Web:
			canOpen = true;
			break;
		case Links::TargetKind::Rejected:
			break;
		case Links::TargetKind::Path:
			canOpen = Links::IsAbsolutePath(m.target) && CheckExists(m.target, 300).state != State::Missing;
			break;
		}
		o.push_back({kMenuOpen, L"Open", canOpen});
		if (m.kind == Links::TargetKind::Path)
			o.push_back({kMenuFolder, L"Open containing folder", Links::IsAbsolutePath(m.target)});
		o.push_back({kMenuDisable, L"Disable link", editable});
		return o;
	}

	// Enable / Disable are the only thing the plugin writes: one "_", as a single undo action.
	// Before that it is checked that the text is still the expected one.
	void ToggleUnderscore(HWND h, const MenuLink& m, bool enable)
	{
		if (Sci(h, SCI_GETREADONLY) != 0)
			return;
		const long long pos = m.line.start + static_cast<long long>(m.link.start);
		const std::string now = ReadText(h, pos, pos + (enable ? 6 : 7));
		if (enable ? now != "_link[" : now != "__link[")
		{
			Log("menu: the text is no longer the expected one, nothing changed");
			return;
		}
		Sci(h, SCI_BEGINUNDOACTION);
		if (enable)
			Sci(h, SCI_INSERTTEXT, static_cast<WPARAM>(pos), reinterpret_cast<LPARAM>("_"));
		else
			Sci(h, SCI_DELETERANGE, static_cast<WPARAM>(pos), 1);
		Sci(h, SCI_ENDUNDOACTION);
		Log("menu: link %s at position %lld", enable ? "enabled" : "disabled", pos);
	}

	void RunOption(HWND h, int id, const MenuLink& m)
	{
		HideTip(h);
		bool allowed = false;
		for (const auto& o : OptionsFor(h, m))
			if (o.id == id && o.enabled)
				allowed = true;
		if (!allowed)
		{
			Log("menu: option %d is not available for this link, nothing done", id);
			return;
		}
		switch (id)
		{
		case kMenuOpen:
			OpenTarget(h, m.target);
			break;
		case kMenuFolder:
			OpenContainingFolder(h, m.target);
			break;
		case kMenuDisable:
			ToggleUnderscore(h, m, false);
			break;
		case kMenuEnable:
			ToggleUnderscore(h, m, true);
			break;
		default:
			break;
		}
	}

	void LogOptions(const std::vector<Option>& o)
	{
		std::string s;
		for (const auto& x : o)
		{
			char buf[128];
			std::snprintf(buf, sizeof(buf), "%s%ls%s", s.empty() ? "" : " | ", x.text, x.enabled ? "" : " (grayed)");
			s += buf;
		}
		Log("menu: %s", s.c_str());
	}

	// WM_CONTEXTMENU on the view. Returns true if it was handled (there was a link); if not, the
	// message goes on its way and Notepad++ shows its normal menu.
	bool ContextMenu(HWND h, LPARAM lParam)
	{
		if (!IsStdoer(h))
			return false;
		long long pos;
		POINT screen;
		if (GET_X_LPARAM(lParam) == -1 && GET_Y_LPARAM(lParam) == -1)
		{
			// From the keyboard (Menu key / Shift+F10): at the text cursor.
			pos = Sci(h, SCI_GETCURRENTPOS);
			POINT p = {static_cast<LONG>(Sci(h, SCI_POINTXFROMPOSITION, 0, static_cast<LPARAM>(pos))),
					   static_cast<LONG>(Sci(h, SCI_POINTYFROMPOSITION, 0, static_cast<LPARAM>(pos)))};
			::ClientToScreen(h, &p);
			screen = p;
		}
		else
		{
			screen.x = GET_X_LPARAM(lParam);
			screen.y = GET_Y_LPARAM(lParam);
			POINT c = screen;
			::ScreenToClient(h, &c);
			// Notepad++ is DPI aware: Scintilla's points are those of the client area.
			pos = Sci(h, SCI_CHARPOSITIONFROMPOINTCLOSE, static_cast<WPARAM>(c.x), static_cast<LPARAM>(c.y));
			Log("menu: screen=(%ld,%ld) client=(%ld,%ld) -> pos=%lld", screen.x, screen.y, c.x, c.y, pos);
		}
		MenuLink m;
		if (!FindMenuLink(h, pos, m))
		{
			Log("menu: no link at pos=%lld: normal menu", pos);
			return false;
		}
		const std::vector<Option> options = OptionsFor(h, m);
		LogOptions(options);
		HMENU menu = ::CreatePopupMenu();
		if (menu == nullptr)
			return false;
		for (const auto& o : options)
			::AppendMenuW(menu, MF_STRING | (o.enabled ? MF_ENABLED : MF_GRAYED), static_cast<UINT_PTR>(o.id), o.text);
		HideTip(h);
		const int chosen = ::TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, screen.x, screen.y, 0, g_npp._nppHandle, nullptr);
		::DestroyMenu(menu);
		Log("menu: chosen %d", chosen);
		if (chosen != 0)
		{
			// The document may have changed while the menu was open: the link is looked up again.
			MenuLink again;
			if (FindMenuLink(h, pos, again) && again.active == m.active && again.target == m.target)
				RunOption(h, chosen, again);
			else
				Log("menu: the link changed while the menu was open, nothing done");
		}
		return true;
	}

	// --- the menu listens on both Scintilla views ---

	LRESULT CALLBACK ViewProc(HWND h, UINT m, WPARAM w, LPARAM l, UINT_PTR, DWORD_PTR)
	{
		if (m == WM_CONTEXTMENU && ContextMenu(h, l))
			return 0;
		return ::DefSubclassProc(h, m, w, l);
	}
	constexpr UINT_PTR kSubclassId = 0x57D0E5;
	bool g_subclassed = false;

	void InstallMenu()
	{
		if (g_subclassed)
			return;
		for (HWND h : {g_npp._scintillaMainHandle, g_npp._scintillaSecondHandle})
			if (h != nullptr)
				::SetWindowSubclass(h, ViewProc, kSubclassId, 0);
		g_subclassed = true;
		Log("menu installed");
	}

	void UninstallMenu()
	{
		if (!g_subclassed)
			return;
		for (HWND h : {g_npp._scintillaMainHandle, g_npp._scintillaSecondHandle})
			if (h != nullptr)
				::RemoveWindowSubclass(h, ViewProc, kSubclassId);
		g_subclassed = false;
	}
}

namespace LinksUI
{
	LRESULT TestMessage(const CommunicationInfo* ci)
	{
		if (!NoShell() || ci == nullptr || ci->info == nullptr)
			return FALSE;
		int which = 0;
		::SendMessageW(g_npp._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, reinterpret_cast<LPARAM>(&which));
		HWND h = (which == 0) ? g_npp._scintillaMainHandle : g_npp._scintillaSecondHandle;
		const int idx = ViewIndex(h);
		if (ci->internalMsg == 1 && idx >= 0 && g_views[idx].applied)
		{
			ShowTip(h, *static_cast<const long long*>(ci->info));
			return TRUE;
		}
		// 3 = the same as a left click (no modifiers) at that position
		if (ci->internalMsg == 3 && idx >= 0 && g_views[idx].applied)
		{
			LinkClicked(h, *static_cast<const long long*>(ci->info), 0);
			return TRUE;
		}
		// 2 = log the menu options of that link; 11..14 = choose that option (Open, Folder, Disable, Enable)
		if ((ci->internalMsg == 2 || (ci->internalMsg >= 11 && ci->internalMsg <= 14)) && idx >= 0 && g_views[idx].applied)
		{
			MenuLink m;
			if (!FindMenuLink(h, *static_cast<const long long*>(ci->info), m))
				return FALSE;
			if (ci->internalMsg == 2)
				LogOptions(OptionsFor(h, m));
			else
				RunOption(h, ci->internalMsg - 10, m);
			return TRUE;
		}
		return FALSE;
	}

	void Init(const NppData& data)
	{
		g_npp = data;
	}

	void Notify(const SCNotification* n)
	{
		HWND source = static_cast<HWND>(n->nmhdr.hwndFrom);
		switch (n->nmhdr.code)
		{
		case NPPN_READY:
			InstallMenu();
			CheckBothViews();
			break;
		case NPPN_SHUTDOWN:
			UninstallMenu();
			break;
		case NPPN_BUFFERACTIVATED:
		case NPPN_LANGCHANGED:
		case NPPN_WORDSTYLESUPDATED:
		case NPPN_EXTERNALLEXERBUFFER:
		case NPPN_FILEOPENED:
		case NPPN_DARKMODECHANGED:
			CheckBothViews();
			break;
		case NPPN_GLOBALMODIFIED:
		{
			// "Replace All" finished in the document (Buffer*) of hwndFrom.
			const BufferId id = reinterpret_cast<BufferId>(n->nmhdr.hwndFrom);
			bool seen = false;
			for (int v = 0; v < 2; ++v)
			{
				HWND hv = (v == 0) ? g_npp._scintillaMainHandle : g_npp._scintillaSecondHandle;
				if (hv != nullptr && g_viewBuffer[v] == id && IsStdoer(hv))
				{
					ComparePaths(hv, v);
					seen = true;
				}
			}
			if (!seen && g_paths.find(id) != g_paths.end())
				g_pending.insert(id);
			CheckBothViews();
			break;
		}
		case NPPN_FILECLOSED:
		{
			const BufferId id = static_cast<BufferId>(n->nmhdr.idFrom);
			g_paths.erase(id);
			g_pending.erase(id);
			for (int v = 0; v < 2; ++v)
				if (g_viewBuffer[v] == id)
					g_viewBuffer[v] = 0;
			break;
		}
		case SCN_MODIFIED:
		{
			// Normal editing (with notifications on): the text changed; the snapshot is redone
			// and what was exposed stops being shown. It is done on the next SCN_UPDATEUI.
			if (n->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))
			{
				const int idx = ViewIndex(source);
				if (idx >= 0)
				{
					g_dirty[idx] = true;
					if (!g_exposed.empty())
						g_clearExposed = true;
				}
			}
			break;
		}
		case SCN_UPDATEUI:
		{
			const int idx = ViewIndex(source);
			if (idx < 0)
				break;
			CheckView(source, idx);
			if (g_views[idx].applied)
			{
				if (g_clearExposed)
				{
					g_clearExposed = false;
					ClearExposed(source);
				}
				if (g_dirty[idx])
				{
					g_dirty[idx] = false;
					g_paths[g_viewBuffer[idx]] = PathList(source);
				}
				UpdateRevealed(source, idx);
			}
			break;
		}
		case SCN_DWELLSTART:
		{
			const int idx = ViewIndex(source);
			Log("mouse dwell pos=%lld view=%d applied=%d", static_cast<long long>(n->position), idx, idx >= 0 ? (g_views[idx].applied ? 1 : 0) : -1);
			if (idx >= 0 && g_views[idx].applied && n->position >= 0)
				ShowTip(source, n->position);
			break;
		}
		case SCN_DWELLEND:
			if (ViewIndex(source) >= 0)
				HideTip(source);
			break;
		case SCN_HOTSPOTCLICK:
		{
			const int idx = ViewIndex(source);
			if (idx >= 0 && g_views[idx].applied)
				LinkClicked(source, n->position, n->modifiers);
			break;
		}
		default:
			break;
		}
	}
}
