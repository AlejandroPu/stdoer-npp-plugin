# Stdoer

Notepad++ plugin (Windows, x64) that adds the **`stdoer`** language for writing text
documents organized as an outline: sections that fold by indentation or with braces, and
links to files, folders and web pages that open with a click.

**Version 0.5.0.** Tested on Notepad++ 8.8.2 x64.

---

## Where it comes from

Stdoer was born in a personal advisory project built with
[Claude Code](https://claude.com/claude-code), meant to help me organize my daily tasks
and personal documents.

For more than 10 years I have written my tasks and some text documents in Notepad++, and
I save them with the `.py` extension even though they are not code, because that way
Notepad++ lets me fold and unfold sections by indentation. It is a simple, lightweight
and flexible method. However, Windows treats those files as Python programs, and the
Python styles that Notepad++ applies make no sense for what I use them for. That is why,
for several years, I had the idea of modifying Notepad++ in some way to fit my needs.

In that project, after weighing different options, the idea came up of giving my
documents a language of their own: one that kept the ability to fold and unfold sections
as in Python files in Notepad++, added what was missing, and used styles better suited
to their real purpose. Stdoer is that language.

## Who made it

- **The planning** was done in conversation with a Claude Code agent, following the
  `bootstrap-colossus-workflow` skill from another of my repositories
  ([claude-skills](https://github.com/AlejandroPu/claude-skills)); as a first step, the
  agent reviewed which parts of it would be useful for the project. That is how we
  specified what the plugin had to do, what it must never do, in what order to build it
  and how to verify each delivery.
- **The code was written entirely by Claude** (Anthropic), in two roles within the same
  project, as the skill above defines them:
  - **Max**, the advisor/planner, with **Claude Opus 5.5**;
  - **Jr.**, who built each delivery and its tests, with **Claude Sonnet 5.5**.
- I tested each delivery before moving on to the next one, in a portable Notepad++
  installation set up for that purpose, before trying it in my usual installation. Jr.'s
  tests were also run in the portable Notepad++.

## What was missing — What it does

### Folding and unfolding sections by indentation

A `.stdoer` document folds by indentation **exactly like a `.py` file**: the plugin uses
Lexilla's Python lexer without modifying it. If you already work this way with `.py`
files, you can change their extension and everything stays the same.

### Folding and unfolding sections with braces

Folding by indentation is combined with the kind of folding that languages such as
JavaScript allow, using the braces `{` and `}` to open and close a section. When folded,
only the line with the opening brace `{` stays visible.

Example:

```
March trip {
Tickets
Lodging
}
Trip details
	Budget {
	Cheap option
	}
	Itinerary
		Berlin
		Paris
```

### Links

```
Signed contract: __link[C:\Documents\contract.pdf]
Supplier: __link[https://www.example.com]
```

- You see `__link[]`: **the path is hidden** to keep the text clean. It shows up while
  the text cursor touches it, so any change to a path is made in plain view.
- The path sits between the square brackets; the plugin hides it only from the person
  viewing the document in Notepad++.
- **Hovering with the mouse** shows a tooltip with the full path, and warns if it does
  not exist.
- **Left click** on `link[]` opens the file, the folder or the web page.
- **Right click**: Open, Open containing folder and Disable link. A disabled link
  (`_link[...]`, with a single underscore) is plain text and can be enabled again from
  the same menu.

### Colors

Stdoer has no colors of its own: it uses those of the active Notepad++ theme, light or
dark, and adapts if the theme changes.

## Security

A document with links should not be able to cause harm when opened or clicked:

- ⛔ **Stdoer never runs anything.** A link to a program, a script, a shortcut or a
  document with macros (`.exe`, `.bat`, `.ps1`, `.lnk`, `.docm`, `.xlsm` and many more)
  **opens the folder that contains it**, not the file.
- Text files (`.txt`, `.md`, `.py`, `.stdoer`…) open in a Notepad++ tab. Everything else
  opens with the program Windows has assigned to it.
- Only `http://` and `https://` web addresses are opened. Any other scheme
  (`javascript:`, `file:`, `ms-settings:`…) is never opened.
- Hidden paths cannot be changed without being shown. If "Replace All" changes one,
  Stdoer shows the link and adds a warning below the line.
- The only thing Stdoer writes to or deletes from the document is the leading `_` of
  Enable / Disable link, and only when chosen from the menu (one Ctrl+Z undoes it).

## Installation

The compiled `Stdoer.dll` and `Stdoer.xml` are on this repository's **Releases** page,
in `Stdoer-0.5.0-x64.zip`.

1. Close Notepad++.
2. Copy both files into the Notepad++ installation folder:

   | File | Destination |
   | --- | --- |
   | `Stdoer.dll` | `plugins\Stdoer\Stdoer.dll` |
   | `Stdoer.xml` | `plugins\Config\Stdoer.xml` |

3. Open Notepad++. `.stdoer` files use the language automatically.

## Known limitations

- Tested only on Notepad++ 8.8.2 x64.
- Another plugin that replaces text on its own, or "Replace in Files", can change a
  hidden path without warning.
- Copying text that contains a link also copies the hidden path between `[` and `]`.
- Notepad++ search also finds text inside hidden paths. The path is hidden only from
  view; the original text with the path is still there.
- In 0.5.0 the plugin's menus and messages are still in Spanish (for example, *Abrir*
  for Open and *Desactivar enlace* for Disable link). English is planned for the next
  version.

## Building

Visual Studio Build Tools (MSVC and Windows SDK) was used to build it. Build
instructions, the test suite and the internals are in
[`DEVELOPMENT.md`](DEVELOPMENT.md).

## License

GNU GPL v2 or later: see [`LICENSE`](LICENSE). It includes, unmodified, the headers of
the Notepad++ plugin template (GPL v2+) and the Python lexer from Lexilla 5.4.5 (HPND
license). Details in [`third_party/ORIGIN.md`](third_party/ORIGIN.md).
