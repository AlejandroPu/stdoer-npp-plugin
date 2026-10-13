// Stdoer — __link[path] links. See Links.h for the rules.

#include "Links.h"

#include <algorithm>
#include <atomic>
#include <cwctype>
#include <cstring>

namespace Links
{
	namespace
	{
		constexpr char kPrefix[] = "__link[";
		constexpr std::size_t kPrefixLength = sizeof(kPrefix) - 1;

		std::atomic<long long> g_revealedStart{-1};
		std::atomic<long long> g_revealedEnd{-1};
		std::vector<std::pair<long long, long long>> g_exposed;  // only used from the UI thread

		// Files that are opened in Notepad++.
		const wchar_t* const kTextTypes[] = {L".stdoer", L".py", L".txt", L".md", L".js", L".json",
											 L".xml", L".ini", L".log", L".csv"};

		// Files that Windows would run or that can run code when opened: they are never
		// opened; their folder is shown instead. (Based on Windows' list of high-risk file
		// types, plus Office macros and other code containers.)
		const wchar_t* const kDangerous[] = {
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

		bool InList(const wchar_t* const* list, std::size_t n, const std::wstring& ext)
		{
			for (std::size_t i = 0; i < n; ++i)
				if (ext == list[i])
					return true;
			return false;
		}
	}

	std::vector<Link> Find(const char* text, std::size_t length)
	{
		std::vector<Link> r;
		std::size_t from = 0;
		while (from + kPrefixLength <= length)
		{
			const char* found = static_cast<const char*>(
				memchr(text + from, '_', length - from));
			if (found == nullptr)
				break;
			const std::size_t i = static_cast<std::size_t>(found - text);
			if (i + kPrefixLength > length)
				break;
			const bool starts = std::memcmp(text + i, kPrefix, kPrefixLength) == 0;
			const bool preceded = i > 0 && text[i - 1] == '_';
			if (!starts || preceded)
			{
				from = i + 1;
				continue;
			}
			// The "]" that balances the brackets.
			const std::size_t openBracket = i + kPrefixLength - 1;
			int depth = 1;
			std::size_t k = openBracket + 1;
			for (; k < length; ++k)
			{
				if (text[k] == '[')
					++depth;
				else if (text[k] == ']' && --depth == 0)
					break;
			}
			if (k < length)
			{
				Link link;
				link.start = i;
				link.openBracket = openBracket;
				link.closeBracket = k;
				r.push_back(link);
				from = k + 1;
			}
			else
				from = i + 2;  // unclosed: there may be a link of its own further on
		}
		return r;
	}

	std::vector<Link> FindDisabled(const char* text, std::size_t length)
	{
		static const char disabledPrefix[] = "_link[";
		constexpr std::size_t n = sizeof(disabledPrefix) - 1;
		std::vector<Link> r;
		std::size_t from = 0;
		while (from + n <= length)
		{
			const char* found = static_cast<const char*>(memchr(text + from, '_', length - from));
			if (found == nullptr)
				break;
			const std::size_t i = static_cast<std::size_t>(found - text);
			if (i + n > length)
				break;
			bool wordBefore = false;
			if (i > 0)
			{
				const unsigned char p = static_cast<unsigned char>(text[i - 1]);
				wordBefore = p == '_' || p >= 0x80 || (p >= '0' && p <= '9') || ((p | 0x20) >= 'a' && (p | 0x20) <= 'z');
			}
			if (wordBefore || std::memcmp(text + i, disabledPrefix, n) != 0)
			{
				from = i + 1;
				continue;
			}
			const std::size_t openBracket = i + n - 1;
			int depth = 1;
			std::size_t k = openBracket + 1;
			for (; k < length; ++k)
			{
				if (text[k] == '[')
					++depth;
				else if (text[k] == ']' && --depth == 0)
					break;
			}
			if (k < length)
			{
				Link link;
				link.start = i;
				link.openBracket = openBracket;
				link.closeBracket = k;
				r.push_back(link);
				from = k + 1;
			}
			else
				from = i + 1;
		}
		return r;
	}

	bool PathTouched(const Link& link, long long base, long long selStart, long long selEnd)
	{
		if (selStart < 0 || selEnd < selStart)
			return false;
		const long long start = base + static_cast<long long>(link.pathStart());
		const long long end = base + static_cast<long long>(link.closeBracket);
		return selStart <= end && selEnd >= start;
	}

	void SetRevealed(long long start, long long end)
	{
		g_revealedStart = start;
		g_revealedEnd = end;
	}

	void GetRevealed(long long& start, long long& end)
	{
		start = g_revealedStart;
		end = g_revealedEnd;
	}

	void SetExposed(const std::vector<std::pair<long long, long long>>& zones)
	{
		g_exposed = zones;
	}

	int PathStyle(const Link& link, long long base)
	{
		long long start = -1, end = -1;
		GetRevealed(start, end);
		if (PathTouched(link, base, start, end))
			return kStyleVisiblePath;
		for (const auto& zone : g_exposed)
			if (PathTouched(link, base, zone.first, zone.second))
				return kStyleVisiblePath;
		return kStyleHiddenPath;
	}

	std::wstring ExtensionOf(const std::wstring& path)
	{
		const std::size_t slash = path.find_last_of(L"\\/");
		const std::size_t dot = path.find_last_of(L'.');
		if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash))
			return std::wstring();
		std::wstring ext = path.substr(dot);
		std::transform(ext.begin(), ext.end(), ext.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
		return ext;
	}

	Action ClassifyExtension(const std::wstring& anyCaseExtension)
	{
		std::wstring ext = anyCaseExtension;
		std::transform(ext.begin(), ext.end(), ext.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
		if (ext.empty())
			return Action::Folder;  // no extension: there is no telling what it is
		if (InList(kTextTypes, sizeof(kTextTypes) / sizeof(kTextTypes[0]), ext))
			return Action::Notepad;
		if (InList(kDangerous, sizeof(kDangerous) / sizeof(kDangerous[0]), ext))
			return Action::Folder;
		return Action::Windows;
	}

	TargetKind ClassifyTarget(const std::wstring& text)
	{
		// Does it start with a scheme? A letter, (letter|digit|+|-|.)* and ":" ; at least 2 characters.
		std::size_t i = 0;
		if (!text.empty() && text[0] < 0x80 && std::iswalpha(text[0]))
		{
			i = 1;
			while (i < text.size() && text[i] < 0x80 &&
				   (std::iswalnum(text[i]) || text[i] == L'+' || text[i] == L'-' || text[i] == L'.'))
				++i;
		}
		if (i < 2 || i >= text.size() || text[i] != L':')
			return TargetKind::Path;  // no scheme ("C:\..." has a single character before ":")
		std::wstring scheme = text.substr(0, i);
		std::transform(scheme.begin(), scheme.end(), scheme.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
		if (scheme != L"http" && scheme != L"https")
			return TargetKind::Rejected;
		// Web address: "scheme://" + at least one character, with no dangerous characters.
		const std::size_t rest = i + 1;
		if (text.size() < rest + 3 || text.compare(rest, 2, L"//") != 0 || text.size() > 2048)
			return TargetKind::Rejected;
		if (text[rest + 2] == L'/' || text[rest + 2] == L'?' || text[rest + 2] == L'#')
			return TargetKind::Rejected;  // no host
		for (std::size_t k = rest + 2; k < text.size(); ++k)
		{
			const wchar_t c = text[k];
			if (c <= L' ' || c == 0x7F || c == L'"' || c == L'<' || c == L'>' || c == L'^' || c == L'`' || c == L'\\')
				return TargetKind::Rejected;
		}
		return TargetKind::Web;
	}

	bool IsAbsolutePath(const std::wstring& path)
	{
		if (path.size() >= 3 && std::iswalpha(path[0]) && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/'))
			return true;
		return path.size() >= 3 && path[0] == L'\\' && path[1] == L'\\' && path[2] != L'\\' && path[2] != L'?';
	}

	std::string Trim(const std::string& path)
	{
		const std::size_t a = path.find_first_not_of(" \t");
		if (a == std::string::npos)
			return std::string();
		const std::size_t b = path.find_last_not_of(" \t");
		return path.substr(a, b - a + 1);
	}
}
