# Neovim Anki Sync (`neovim-anki-sync`)

A native, ultra-fast, and **stateless** Lua plugin for Neovim that parses flashcards from Markdown notes (including outliners) and synchronizes them directly to Anki via AnkiConnect.

<p align="center">
  <img src="https://img.shields.io/github/stars/din-grogu/neovim-anki-sync.svg?logo=GitHub&style=flat" alt="GitHub Stars" />
  <img src="https://img.shields.io/github/sponsors/din-grogu.svg?logo=github&style=flat&color=orange&label=Sponsor" alt="Sponsor" />
</p>

---

## 💡 Origin & Motivation

This plugin is a fork of the excellent [logseq-anki-sync](https://github.com/debanjandhar12/logseq-anki-sync) plugin. 

Having migrated from Logseq to Neovim, the main goal of this fork was to port the great flashcard synchronization workflow of the original Logseq plugin into a native, fast, and lightweight Neovim experience. 

---

## 🚀 Features

* **100% Pure Lua:** Zero external dependencies (no Node.js, Python, or NPM required). It only uses `curl` in the background.
* **Stateless Cache:** Content hashes are stored directly within Anki (in the card's `Config` field). No local databases or JSON cache files to manage or sync across multiple machines.
* **Outliner & Hierarchy Support:** Full support for indented bullet trees, markdown headings (`#`, `##`), Logseq-style properties (`deck::`, `tags::`), inline tags (`#tag`), and automatic hierarchical breadcrumbs/parent context.
* **In-place UUID Injection:** Automatically generates and appends unique IDs (`<!-- id: <uuid> -->`) to your notes when syncing new cards, allowing you to move cards around without losing scheduling history.
* **Auto-Initialization:** Automatically creates the target deck and the custom `NeovimAnkiCard-Cloze-v2` note type (with fields `Text`, `Back`, `Breadcrumb`, `UUID`, and `Config`, styled with CSS mimicking Logseq bubble breadcrumbs and night mode) in Anki if they do not exist.
* **Inline Markdown & Code Blocks:** Supports inline Markdown (`**bold**`, `*italic*`, `==highlight==`, `` `code` ``, `[text](url)`) and fenced code blocks (``` / ~~~), safely preserving Anki clozes and ignoring `#card` inside code.
* **Asynchronous Execution:** Runs in the background using Neovim's job APIs, ensuring your editor UI never freezes during sync.

---

## 🛠️ Installation & Setup

You can install `neovim-anki-sync` using your favorite plugin manager.

### Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "din-grogu/neovim-anki-sync",
    ft = { "markdown" },
    config = function()
        require("neovim-anki-sync").setup({
            deck = "Default",                   -- Fallback deck name in Anki (if file is at root or relative_dir is empty)
            deck_prefix = "",                   -- Optional prefix prepended to all resolved decks (e.g. "Concursos")
            include_filename_in_deck = true,    -- Whether to append the filename (without ext) as the innermost sub-deck
            model = "NeovimAnkiCard-Cloze-v2",  -- Target note type name (auto-created if missing)
            anki_url = "http://127.0.0.1:8765", -- AnkiConnect URL
            notes_dir = nil,                    -- Root directory of your notes (optional). Accepts "~/path". If nil, auto-detects root.
            root_markers = { ".git", ".obsidian", ".logseq", ".root" }, -- Heuristic markers to auto-detect notes root
        })
    end
}
```

### 📂 Automatic Hierarchical Decks

The plugin automatically maps your notes' folder hierarchy to Anki sub-decks using Anki's `::` separator.

* **How it works:** 
  The plugin detects the root of your notes by searching upwards for any of `root_markers` (e.g. `.git`, `.obsidian`, `.logseq`, `.root`, or falling back to your active Neovim working directory). The directory path of your note file *relative* to this root is converted to Anki's sub-deck hierarchy.
* **Example:**
  If your `notes_dir` is `/home/user/notes` and you edit a file at:
  `/home/user/notes/Concursos/Estratégia/CFBM/cards.md`
  
  With `include_filename_in_deck = true` (default), the deck will be:
  `Concursos::Estratégia::CFBM::cards`

  With `include_filename_in_deck = false`:
  `Concursos::Estratégia::CFBM`
* **Prefixing Decks:**
  Set `deck_prefix = "Estudos"` to automatically prefix all decks (e.g. `Estudos::Concursos::...`).
* **Fallback:**
  If the file is directly at the root (no subdirectory) or outside the detected project directory, it falls back to the configured `deck` option (defaulting to `"Default"`).
* **Custom Root:**
  If you want to manually specify your notes root directory instead of using marker/CWD detection, you can set `notes_dir = vim.fn.expand("~/path/to/notes")` in `setup`.

### 🏷️ Properties & Metadata

You can override the deck or add tags to your cards using Logseq-style properties or Markdown frontmatter.

**Global properties (Frontmatter)**:
Properties defined at the top of the file apply to all cards inside it.
```markdown
deck:: GlobalDeck
tags:: tag1, tag2
```

**Card properties**:
Properties indented right below a card apply only to that specific card.
```markdown
- What is the capital of France? #card
  deck:: CustomDeck
  tags:: geography, cities
  The capital is Paris.
```

**Inline Tags**:
You can also specify tags directly in the card title using the `#tag` syntax.
```markdown
- What is Neovim? #card #programming #tools
  A Vim-based text editor built for extensibility using Lua.
```

### 🍞 Breadcrumbs & Bullet Hierarchy Context

The plugin automatically generates hierarchical breadcrumbs combining:
1. Directory path relative to `notes_dir`
2. Filename (without extension)
3. Markdown headings (`#`, `##`, `###`) leading up to the card
4. Parent bullet hierarchy enclosing the card

This context is styled into a neat pill badge (`<div class="bubble">...</div>`) at the top of the card in Anki, ensuring you always know the exact context when reviewing!

---

## ✍️ Card Syntax

### Multiline Cards & Child Bullets
Cards are written as list items (bullets or headers) containing `#card`. Any indented child bullets under `#card` are automatically wrapped as an Anki cloze deletion (`{{c1::...}}`) maintaining full Markdown bullet hierarchy in HTML:

```markdown
# My Study Notes

- What is Neovim? #card
  - A Vim-based modal text editor.
  - Built for extensibility using Lua.
```

### Manual Cloze Deletions
You can also specify explicit Anki Cloze syntax anywhere in the card:
```markdown
- The Sun is a {{c1::star}} at the center of the {{c2::Solar System}}. #card
```

### Inline Markdown Formatting
Use standard Markdown syntax inside your cards:
```markdown
- Important concepts in Law: #card
  - **Strict liability**: requires no *mens rea*.
  - Use ==highlight== for key terms and `code` for commands.
```

---

## ⌨️ User Commands

The plugin registers a global user command with path auto-completion:

* `:AnkiSync` - Synchronizes the active buffer. Any newly detected cards will have their UUID comments appended in-place automatically.
* `:AnkiSync <path_to_file>` - Synchronizes a specific Markdown file.

---

## ⚠️ Current Limitations

Since this is a lightweight Lua port focused on speed and simplicity, it has some limitations compared to the original Logseq plugin:
* **No Media/Asset Sync:** Local image files, audio, and video files are not automatically uploaded to Anki yet.
* **Basic Text Parsing:** Complex card layouts (such as swift arrows, image occlusion, or advanced HTML styling) are not yet supported.
* **Raw References:** Block references and page embeds are parsed as raw text rather than being resolved dynamically.

---

## 🗺️ Roadmap / Future Features

* [ ] **Local Media Synchronization:** Detect and upload local image/audio assets to Anki using `storeMediaFile` via curl.
* [x] **Markdown to HTML Converter:** Native converter supporting bold, italics, highlights (`==`), inline code (` `), links, and fenced code blocks (` ``` `).
* [x] **Multiline Cloze Cards:** Automatic conversion of indented bullet trees into cloze cards preserving HTML list hierarchy.
* [ ] **Additional Card Styles:** Support for Swift Arrow (`->`) and customizable note templates.
* [ ] **Interactive Sync Window:** Provide a visual diff/sync window (using `nui.nvim` or `Telescope`) to review changes before pushing to Anki.

---

## 🧪 Running Integration Tests

You can run the headless test suite to verify the parser, UUID injector, path resolution, and synchronization engine:

```bash
nvim --headless -u NONE -l tests/run_tests.lua
```

---

## 🙏 Support & Donations

If you love this tool, please consider sponsoring or donating to support its continued development!

* [GitHub Sponsors](https://github.com/sponsors/din-grogu)
