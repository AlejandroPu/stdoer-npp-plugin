// Stdoer — folding with { } (pure logic, independent of Scintilla).
//
// Rules (DEVELOPMENT.md, "Folding with { }"):
//   - "{" counts only as the LAST character of a line (not counting spaces or tabs): it opens.
//   - "}" counts only as the FIRST character of a line (idem): it closes.
//   - Any other brace does nothing. Only the text is looked at: quotes and "#" do not exist
//     for this layer (the Python lexer plays no part in it).
//   - An unmatched "}" is ignored. So is an unclosed "{": only a "{" that has its matching "}"
//     counts, so a brace mistake never hides more than it should.
//   - Matched with a stack, top to bottom, without looking at indentation.
//   - Inside a { } region, folding by indentation keeps working; indentation is compared only
//     between lines of the same region (a dedent does not leave the region).
//   - The "}" line stays INSIDE the region: when folded it is hidden with it and only the "{"
//     line is visible. Exception: "} else {" closes one region and opens another, so it cannot
//     be hidden with the first and be the header of the second at once; it stays outside the
//     first (visible) and is the header of the second.

#pragma once

#include <cstddef>
#include <vector>

namespace Braces
{
	struct Line
	{
		bool opens = false;   // the line ends with "{"
		bool closes = false;  // the line starts with "}"
	};

	// Classifies the text of ONE line (without its line break).
	Line Classify(const char* text, std::size_t length);

	// Sets opens/closes to false on every unmatched brace. Returns how many pairs there are.
	std::size_t Match(std::vector<Line>& lines);

	// Takes in `levels` the fold levels given by the Python lexer (level + flags, one per
	// line) and rewrites them to include the already matched { } regions. With zero pairs it
	// changes nothing. Returns true if anything changed.
	bool Apply(const std::vector<Line>& lines, std::vector<int>& levels);
}
