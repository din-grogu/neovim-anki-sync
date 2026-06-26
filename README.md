# Neovim Anki Sync (`neovim-anki-sync`)

A native, ultra-fast, and **stateless** Lua plugin for Neovim that parses flashcards from Markdown/Org files and synchronizes them directly to Anki via AnkiConnect.

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
* **In-place UUID Injection:** Automatically generates and appends unique IDs (`<!-- id: <uuid> -->`) to your notes when syncing new cards, allowing you to move cards around without losing scheduling history.
* **Auto-Initialization:** Automatically creates the target deck and the custom `NeovimAnkiCard` note type (with fields `Front`, `Back`, `UUID`, and `Config`) in Anki if they do not exist.
* **Asynchronous Execution:** Runs in the background using Neovim's job APIs, ensuring your editor UI never freezes during sync.

---

## 🛠️ Installation & Setup

You can install `neovim-anki-sync` using your favorite plugin manager.

### Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "din-grogu/neovim-anki-sync",
    ft = { "markdown", "org" },
    config = function()
        require("neovim-anki-sync").setup({
            deck = "Default",                   -- Fallback deck name in Anki (if file is at root or outside notes_dir)
            model = "NeovimAnkiCard",           -- Target note type name (auto-created if missing)
            anki_url = "http://127.0.0.1:8765", -- AnkiConnect URL
            notes_dir = nil                     -- Root directory of your notes (optional). If nil, auto-detects Git root/CWD.
        })
    end
}
```

### 📂 Automatic Hierarchical Decks

The plugin automatically maps your notes' folder hierarchy to Anki sub-decks using Anki's `::` separator.

* **How it works:** 
  The plugin automatically detects the root of your notes by searching upwards for a `.git` folder (or falling back to your active working directory). The directory path of your note file *relative* to this root is converted to Anki's sub-deck hierarchy.
* **Example:**
  If your project root is `/home/user/notes` and you edit a file at:
  `/home/user/notes/Concursos/Estratégia/CFBM/cards.md`
  
  The plugin will automatically create and sync your cards to the deck:
  `Concursos::Estratégia::CFBM`
* **Fallback:**
  If the file is directly at the root (no subdirectory) or outside the detected project directory, it falls back to the configured `deck` option (defaulting to `"Default"`).
* **Custom Root:**
  If you want to manually specify your notes root directory instead of using git/CWD detection, you can set the `notes_dir` option in the `setup` config.

---

## ✍️ Card Syntax

Write your flashcards as list items (bullets or headers) containing the tag `#card`. The text on the header is the Front, and any indented lines under it become the Back:

```markdown
# My Study Notes

- What is the capital of France? #card
  The capital is Paris.

- What is Neovim? #card
  A Vim-based text editor built for extensibility using Lua.
```

### Cloze Deletion Support
You can also use standard Anki Cloze syntax:
```markdown
- The Sun is a {{c1::star}} at the center of the Solar System. #card
```

---

## ⌨️ User Commands

The plugin registers a global user command with path auto-completion:

* `:AnkiSync` - Synchronizes the active buffer. Any newly detected cards will have their UUID comments appended in-place automatically.
* `:AnkiSync <path_to_file>` - Synchronizes a specific Markdown/Org file.

---

## ⚠️ Current Limitations

Since this is a lightweight Lua port focused on speed and simplicity, it has some limitations compared to the original Logseq plugin:
* **No Media/Asset Sync:** Local image files, audio, and video files are not automatically uploaded to Anki yet.
* **Basic Text Parsing:** Complex card layouts (such as swift arrows, image occlusion, or advanced HTML styling) are not yet supported.
* **Raw References:** Block references and page embeds are parsed as raw text rather than being resolved dynamically.

---

## 🗺️ Roadmap / Future Features

* [ ] **Local Media Synchronization:** Detect and upload local image/audio assets to Anki using `storeMediaFile` via curl.
* [ ] **Markdown to HTML Converter:** Implement a basic Markdown converter to support bold, italics, and code blocks formatting in Anki.
* [ ] **Multiple Card Styles:** Add support for Multiline, Swift Arrow, and custom card templates.
* [ ] **Interactive Sync Window:** Provide a visual diff/sync window (using `nui.nvim` or `Telescope`) to review changes before pushing to Anki.

---

## 🧪 Running Integration Tests

You can run the headless integration test suite to verify the parser, UUID injector, HTTP client, and synchronization engine:

```bash
nvim --headless -l tests/neovim-sync-test.lua
```

---

## 🙏 Support & Donations

If you love this tool, please consider sponsoring or donating to support its continued development!

* [GitHub Sponsors](https://github.com/sponsors/din-grogu)
