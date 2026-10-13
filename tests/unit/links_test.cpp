// Unit tests of src\Links.cpp (link parser and path classification).
// Built and run with tests\unit\run.cmd; exits with code 0 if everything passes.

#include <cstdio>
#include <string>

#include "Links.h"

namespace
{
	int g_failures = 0;
	int g_total = 0;

	void Check(bool ok, const char* name)
	{
		++g_total;
		if (!ok)
		{
			++g_failures;
			std::printf("FAIL: %s\n", name);
		}
	}

	// Returns "start:open:close" of each link separated by a space, or "-" if there are none.
	std::string Summary(const std::string& line)
	{
		const auto v = Links::Find(line.data(), line.size());
		if (v.empty())
			return "-";
		std::string r;
		for (const auto& e : v)
		{
			if (!r.empty())
				r += ' ';
			r += std::to_string(e.start) + ":" + std::to_string(e.openBracket) + ":" + std::to_string(e.closeBracket);
		}
		return r;
	}

	void Case(const std::string& line, const std::string& expected)
	{
		const std::string actual = Summary(line);
		++g_total;
		if (actual != expected)
		{
			++g_failures;
			std::printf("FAIL Find(\"%s\"): expected [%s], got [%s]\n", line.c_str(), expected.c_str(), actual.c_str());
		}
	}
}

int main()
{
	using namespace Links;

	// --- Find ---
	Case("", "-");
	Case("__link[a]", "0:6:8");
	Case("_link[a]", "-");                       // disabled
	Case("link[a]", "-");
	Case("___link[a]", "-");                     // extra "_": does not count
	Case("x __link[a [1].txt] y", "2:8:18");     // brackets inside the path
	Case("__link[a] y __link[b]", "0:6:8 12:18:20");
	Case("__link[a", "-");                       // unclosed
	Case("__link[a __link[b]", "9:15:17");       // the first stays unclosed; the second counts
	Case("__link[]", "0:6:7");                   // empty path
	Case("__link[a]]", "0:6:8");                 // an extra "]" is ignored
	Case("__link[[x]]", "0:6:10");
	Case("__link[a] __link[b", "0:6:8");         // the second, unclosed, does not count
	Case("__LINK[a]", "-");                      // case-sensitive
	Case("__link [a]", "-");
	Case(R"(  __link[F:\folder\file.txt])", "2:8:27");
	Case("# __link[a] {", "2:8:10");             // # and braces do not matter

	// --- PathTouched: path [107,110), cursor zone 107..110 ---
	{
		const auto v = Find("__link[abc]", 11);
		const Link link = v.at(0);
		Check(PathTouched(link, 100, 107, 107), "cursor right after [");
		Check(PathTouched(link, 100, 110, 110), "cursor right before ]");
		Check(PathTouched(link, 100, 108, 108), "cursor inside the path");
		Check(!PathTouched(link, 100, 106, 106), "cursor before [");
		Check(!PathTouched(link, 100, 111, 111), "cursor after ]");
		Check(PathTouched(link, 100, 90, 120), "selection that contains the link");
		Check(PathTouched(link, 100, 90, 107), "selection that ends at [");
		Check(!PathTouched(link, 100, 90, 106), "selection that ends before");
		Check(PathTouched(link, 100, 110, 130), "selection that starts at ]");
		Check(!PathTouched(link, 100, 111, 130), "selection that starts after");
		Check(!PathTouched(link, 100, -1, -1), "nothing touched");
	}

	// --- Shared revealed state ---
	{
		SetRevealed(-1, -1);
		const Link link = Find("__link[abc]", 11).at(0);
		Check(PathStyle(link, 100) == kStyleHiddenPath, "no revealed interval: hidden");
		SetRevealed(108, 108);
		Check(PathStyle(link, 100) == kStyleVisiblePath, "with revealed interval: visible");
		Check(PathStyle(link, 500) == kStyleHiddenPath, "another link: hidden");
		SetRevealed(-1, -1);
	}

	// --- Classification by extension ---
	Check(ClassifyExtension(L".txt") == Action::Notepad, ".txt");
	Check(ClassifyExtension(L".STDOER") == Action::Notepad, ".STDOER in uppercase");
	Check(ClassifyExtension(L".js") == Action::Notepad, ".js opens in Notepad++ (it is not run)");
	Check(ClassifyExtension(L".ods") == Action::Windows, ".ods");
	Check(ClassifyExtension(L".xlsx") == Action::Windows, ".xlsx");
	Check(ClassifyExtension(L".html") == Action::Windows, ".html");
	Check(ClassifyExtension(L".pdf") == Action::Windows, ".pdf");
	Check(ClassifyExtension(L".exe") == Action::Folder, ".exe");
	Check(ClassifyExtension(L".EXE") == Action::Folder, ".EXE");
	Check(ClassifyExtension(L".bat") == Action::Folder, ".bat");
	Check(ClassifyExtension(L".cmd") == Action::Folder, ".cmd");
	Check(ClassifyExtension(L".ps1") == Action::Folder, ".ps1");
	Check(ClassifyExtension(L".vbs") == Action::Folder, ".vbs");
	Check(ClassifyExtension(L".lnk") == Action::Folder, ".lnk");
	Check(ClassifyExtension(L".hta") == Action::Folder, ".hta");
	Check(ClassifyExtension(L".msi") == Action::Folder, ".msi");
	Check(ClassifyExtension(L".jar") == Action::Folder, ".jar");
	Check(ClassifyExtension(L".scr") == Action::Folder, ".scr");
	Check(ClassifyExtension(L".reg") == Action::Folder, ".reg");
	Check(ClassifyExtension(L".docm") == Action::Folder, ".docm (macros)");
	Check(ClassifyExtension(L".xlsm") == Action::Folder, ".xlsm (macros)");
	Check(ClassifyExtension(L"") == Action::Folder, "no extension");

	// --- ExtensionOf ---
	Check(ExtensionOf(LR"(C:\a\b.TXT)") == L".txt", "ExtensionOf uppercase");
	Check(ExtensionOf(LR"(C:\a.b\c)") == L"", "dot in folder, not in file");
	Check(ExtensionOf(LR"(C:\a\b)") == L"", "no extension");
	Check(ExtensionOf(LR"(C:\a\b.tar.gz)") == L".gz", "last extension");
	Check(ExtensionOf(LR"(C:\a\.stdoer)") == L".stdoer", "file that starts with a dot");

	// --- IsAbsolutePath ---
	Check(IsAbsolutePath(LR"(C:\a)"), "drive");
	Check(IsAbsolutePath(L"c:/a"), "drive with forward slash");
	Check(IsAbsolutePath(LR"(\\server\share\a)"), "UNC");
	Check(!IsAbsolutePath(LR"(a\b.txt)"), "relative");
	Check(!IsAbsolutePath(LR"(..\a)"), "relative with ..");
	Check(!IsAbsolutePath(L"C:a"), "drive without slash (relative to the drive)");
	Check(!IsAbsolutePath(LR"(\a)"), "root without drive");
	Check(!IsAbsolutePath(L""), "empty");
	Check(!IsAbsolutePath(LR"(\\?\C:\a)"), "long path prefix: not supported");
	Check(!IsAbsolutePath(L"http://x"), "URL");

	// --- Trim ---
	Check(Trim("  a b \t") == "a b", "Trim");
	Check(Trim("   ") == "", "Trim only spaces");
	Check(Trim("a") == "a", "Trim with nothing to remove");

	std::printf("%d checks, %d failures\n", g_total, g_failures);
	return g_failures == 0 ? 0 : 1;
}
