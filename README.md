# Anki Sync Suite (Logseq & Neovim)

<h3 align="center">Supercharged synchronization plugins from your favorite editors (Logseq & Neovim) to Anki.</h3>

<p align="center">
  <img src="https://img.shields.io/github/stars/debanjandhar12/logseq-anki-sync.svg?logo=GitHub&style=flat" alt="GitHub Stars" />
  <img src="https://img.shields.io/github/sponsors/debanjandhar12.svg?logo=github&style=flat&color=orange&label=Sponsor" alt="Sponsor" />
</p>

---

## 1. Neovim Anki Sync (Lua Plugin)

A native, ultra-fast, and **stateless** Lua plugin for Neovim that parses flashcards from Markdown/Org files and syncs them directly to Anki via AnkiConnect.

### 🚀 Features (Neovim)
* **100% Pure Lua:** Zero external dependencies (no Node.js, python, or npm required). It only uses `curl` in the background.
* **Stateless Cache (Approach 3):** Content hashes are stored directly within Anki (in the card's `Config` field). No local JSON or SQLite cache files to sync across devices.
* **In-place UUID Injection:** Automatically generates and inserts unique IDs (`<!-- id: <uuid> -->`) into your notes when syncing new cards.
* **Auto-Initialization:** Automatically creates the target deck and the custom `NeovimAnkiCard` note type in Anki if they do not exist.
* **Fast and Asynchronous:** Uses Neovim's built-in JSON encoder/decoder and runs asynchronously so your editor never freezes.

### 🛠️ Installation & Setup

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "debanjandhar12/logseq-anki-sync", -- Path to this repository
    ft = { "markdown", "org" },
    config = function()
        require("neovim-anki-sync").setup({
            deck = "Default",           -- Default deck name in Anki
            model = "NeovimAnkiCard",    -- Target note type (auto-created if missing)
            anki_url = "http://127.0.0.1:8765" -- AnkiConnect URL
        })
    end
}
```

### ✍️ Card Syntax

Simply write your cards as list items ending with `#card`. The list item serves as the front, and all indented lines underneath serve as the back:

```markdown
- Qual a capital do Brasil? #card
  A capital é Brasília.

- O que é o Neovim? #card
  Um editor de texto baseado em Vim, altamente extensível via Lua.
```

### ⌨️ Commands

* `:AnkiSync` - Synchronizes all cards in the current buffer. Missing UUIDs will be generated and written back to the file.
* `:AnkiSync <path_to_file>` - Synchronizes a specific file (supports path auto-completion).

---

## 2. Logseq Anki Sync (Logseq Plugin)

A feature-rich plugin for Logseq with advanced rendering, image occlusion, clozes, and PDF annotation support.

### 🚀 Features (Logseq)
* **Rich rendering:** Support for rendering block/page references, PDF annotations, math equations, and custom cloze templates.
* **Image Occlusion:** In-app fabric.js canvas editor to draw occlusions directly over images or PDF annotations.
* **Extremely fast:** Employs an invalidation dependency-graph cache system ([BlockAndPageHashCache.ts](file:///home/dieb/Documentos/git/neovim-anki-sync/src/sync/cache/BlockAndPageHashCache.ts)) to track changes.

### 🛠️ Installation & Setup (Logseq)

1. Enable plugins in Logseq (`Settings` > `Features` > `Plugins`).
2. Go to `Plugins` > `Marketplace`, search for **Logseq Anki Sync** and install.
3. Install **AnkiConnect** in Anki (add-on code [2055492159](https://ankiweb.net/shared/info/2055492159)).
4. Restart both applications and click the Sync button in Logseq's toolbar.

For detailed usage, please see the [Logseq Documentation](https://debanjandhar12.github.io/logseq-anki-sync/docs/intro/).

---

## 🙏 Support & Donations

If you love these tools, please consider sponsoring or donating to support their continued development!

* [GitHub Sponsors](https://github.com/sponsors/debanjandhar12)
