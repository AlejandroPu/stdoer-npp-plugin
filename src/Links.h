// Stdoer — __link[path] links (pure logic, independent of Scintilla and Windows).
//
// Rules (DEVELOPMENT.md, "Links"):
//   - A link is "__link[" + path + "]", all on ONE line. With a single "_" (or none) it is a
//     disabled link: plain text that does nothing.
//   - The closing "]" is the one that balances the brackets (the path may contain "[ ]").
//     If the line ends unbalanced, there is no link.
//   - Several links per line. A "__link[" preceded by another "_" does not count ("___link[").
//   - Only the text is looked at: quotes and "#" do not matter.

#pragma once

#include <cstddef>
#include <string>
#include <utility>
#include <vector>

namespace Links
{
	// Scintilla styles that the lexer gives to the parts of a link. They are above those of the
	// Python lexer (0-21 and substyles from 128) and the reserved ones (32-39).
	constexpr int kStyleHiddenPath = 50;   // the path: invisible and not modifiable
	constexpr int kStyleVisiblePath = 51;  // the path, while the cursor or the selection touch it
	constexpr int kStyleLink = 52;         // "link[" and "]": the clickable zone (hotspot)

	// Positions within a line (byte indexes).
	struct Link
	{
		std::size_t start = 0;         // first "_"
		std::size_t openBracket = 0;   // "["
		std::size_t closeBracket = 0;  // matching "]"

		// The path occupies [openBracket + 1, closeBracket). The clickable zone is "link[" + "]":
		// from start + 2 to closeBracket, both included (without the two "_").
		std::size_t pathStart() const { return openBracket + 1; }
		std::size_t clickZoneStart() const { return start + 2; }
	};

	// All the links of a line (without its line break), in order.
	std::vector<Link> Find(const char* text, std::size_t length);

	// Disabled links of a line: "_link[" with a SINGLE "_" that does not follow another letter,
	// digit or "_" (so "my_link[0]" is not mistaken for one). `start` is that "_" (the brackets
	// are as in a link). They serve the "Enable link" menu item.
	std::vector<Link> FindDisabled(const char* text, std::size_t length);

	// Is the link's path "touched" by the interval [selStart, selEnd] (cursor positions, ends
	// included)? Used to show the path while it is being edited. `base` is the absolute
	// position of the first byte of the line. With selStart < 0 nothing is touched.
	bool PathTouched(const Link& link, long long base, long long selStart, long long selEnd);

	// State shared between the plugin and the lexer: the interval (selection) whose links are
	// shown. The plugin writes it; the lexer reads it when styling. -1 = none.
	void SetRevealed(long long start, long long end);
	void GetRevealed(long long& start, long long& end);

	// Path zones that are shown in addition to the selection (links whose path changed in a way
	// that cannot be seen, such as "Replace All"). Each zone is a cursor interval [start, end].
	void SetExposed(const std::vector<std::pair<long long, long long>>& zones);

	// Style that corresponds to the link's path, according to the shared state.
	int PathStyle(const Link& link, long long base);

	// What to do when opening a file (a click never runs anything).
	enum class Action
	{
		Notepad,  // open as a Notepad++ tab
		Windows,  // open with the program Windows has assigned
		Folder,   // show the file in its folder (executables, scripts, macros...)
	};

	// Classifies by extension (with the dot, any case; empty if it has none).
	Action ClassifyExtension(const std::wstring& extension);

	// Extension of a path (with the dot, lowercase), or empty.
	std::wstring ExtensionOf(const std::wstring& path);

	// What the text of a link is (already trimmed).
	enum class TargetKind
	{
		Path,      // a file or folder path (or text without a scheme, e.g. empty or relative)
		Web,       // a well-formed http:// or https:// address: opened in the browser
		Rejected,  // carries a scheme other than http(s) ("javascript:", "file:", "ms-settings:"...),
		           // or a malformed http(s) address: never opened
	};

	// ⛔ Only http and https. A scheme is 2 or more characters (a letter, then letters, digits,
	// + - .) followed by ":"; "C:" is not one (it is a drive). A valid web address is
	// "http(s)://" + something, with no spaces or control characters, no " < > ^ ` \, and no
	// longer than 2048 characters (so it cannot break the browser's command line).
	TargetKind ClassifyTarget(const std::wstring& text);

	// Is the path absolute (X:\... or \\server\...)? Relative ones are not opened.
	bool IsAbsolutePath(const std::wstring& path);

	// Removes spaces and tabs from both ends of the path.
	std::string Trim(const std::string& path);
}
