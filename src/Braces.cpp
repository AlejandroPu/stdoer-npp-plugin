// Stdoer — folding with { }. See Braces.h for the rules.

#include "Braces.h"

#include <algorithm>

#include "Scintilla.h"

namespace Braces
{
	namespace
	{
		// Scintilla fold levels: the number in the low 12 bits plus flags.
		constexpr int kBase = SC_FOLDLEVELBASE;
		constexpr int kMask = SC_FOLDLEVELNUMBERMASK;
		constexpr int kHeader = SC_FOLDLEVELHEADERFLAG;

		bool IsBlank(char c)
		{
			return c == ' ' || c == '\t';
		}

		// One frame of the stack: either a { } region or a Python indentation block.
		struct Frame
		{
			bool brace;
			int level;  // only for indentation blocks: level number of its header
		};
	}

	Line Classify(const char* text, std::size_t length)
	{
		Line r;
		std::size_t start = 0;
		while (start < length && IsBlank(text[start]))
			++start;
		if (start == length)
			return r;  // blank
		std::size_t end = length;
		while (end > start && IsBlank(text[end - 1]))
			--end;
		r.closes = (text[start] == '}');
		r.opens = (text[end - 1] == '{');
		return r;
	}

	std::size_t Match(std::vector<Line>& lines)
	{
		// A "}" that closes and a "{" that opens on the same line ("} else {"): it closes first.
		std::vector<std::size_t> stack;  // lines with a "{" not yet matched
		std::vector<char> opensMatched(lines.size(), 0);
		std::vector<char> closesMatched(lines.size(), 0);
		std::size_t pairs = 0;
		for (std::size_t i = 0; i < lines.size(); ++i)
		{
			if (lines[i].closes && !stack.empty())
			{
				opensMatched[stack.back()] = 1;
				closesMatched[i] = 1;
				stack.pop_back();
				++pairs;
			}
			if (lines[i].opens)
				stack.push_back(i);
		}
		for (std::size_t i = 0; i < lines.size(); ++i)
		{
			lines[i].opens = opensMatched[i] != 0;
			lines[i].closes = closesMatched[i] != 0;
		}
		return pairs;
	}

	bool Apply(const std::vector<Line>& lines, std::vector<int>& levels)
	{
		const std::size_t n = std::min(lines.size(), levels.size());
		bool anyPairs = false;
		for (std::size_t i = 0; i < n && !anyPairs; ++i)
			anyPairs = lines[i].opens || lines[i].closes;
		if (!anyPairs)
			return false;

		// The fold tree is rebuilt as a stack of frames and each line gets as its level
		// 1024 + (frames around it). For indentation blocks this keeps exactly the structure
		// of Python: a header opens a frame, which ends at the first line whose level is lower
		// or equal (that is how Scintilla reads it).
		std::vector<Frame> stack;
		std::vector<int> depths(n, 0);
		std::vector<char> candidate(n, 0);  // the line opened some frame
		int previousLevel = 0;  // in case a line brought no Python level (it should not happen)
		for (std::size_t i = 0; i < n; ++i)
		{
			const int original = levels[i];
			const int number = (original >= 0) ? (original & kMask) : previousLevel;
			const bool pythonHeader = original >= 0 && (original & kHeader) != 0;
			previousLevel = number;

			// 1) "}" with a match: closes its region and everything opened inside it. If the
			//    line only closes, it stays INSIDE the region (when folded it is hidden with
			//    it); if it also opens another ("} else {"), it cannot be hidden with the first
			//    and be the header of the second at once: it stays outside the first and is
			//    the header of the second.
			int closeDepth = -1;
			if (lines[i].closes)
			{
				while (!stack.empty() && !stack.back().brace)
					stack.pop_back();
				if (!lines[i].opens)
					closeDepth = static_cast<int>(stack.size());  // counts the brace: level of the content
				if (!stack.empty())
					stack.pop_back();
			}
			// 2) Indentation blocks that end here. They do not cross the brace of their
			//    region: inside a region, indentation is compared only with that of the same
			//    region.
			while (!stack.empty() && !stack.back().brace && stack.back().level >= number)
				stack.pop_back();

			depths[i] = (closeDepth >= 0) ? closeDepth : static_cast<int>(stack.size());
			// A line that opens "{" opens a single frame, that of the region: if Python also
			// marked it a header (the next line is more indented), the region wins and the
			// levels stay consecutive.
			if (lines[i].opens)
			{
				stack.push_back({true, 0});
				candidate[i] = 1;
			}
			else if (pythonHeader)
			{
				stack.push_back({false, number});
				candidate[i] = 1;
			}
		}

		// Second pass: a line is a header only if the next one is deeper; that way a frame
		// with nothing under it does not leave a fold with nothing to hide.
		bool changed = false;
		for (std::size_t i = 0; i < n; ++i)
		{
			const int original = levels[i];
			const bool header = candidate[i] && i + 1 < n && depths[i + 1] > depths[i];
			const int keep = (original >= 0) ? (original & ~(kMask | kHeader)) : 0;
			const int updated = keep | (kBase + std::min(depths[i], kMask - kBase)) | (header ? kHeader : 0);
			if (updated != original)
			{
				levels[i] = updated;
				changed = true;
			}
		}
		return changed;
	}
}
