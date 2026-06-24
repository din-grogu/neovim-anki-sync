# Neovim Anki Sync (`neovim-anki-sync`)

A native, ultra-fast, and **stateless** Lua plugin for Neovim that parses flashcards from Markdown/Org files and synchronizes them directly to Anki via AnkiConnect.

<p align="center">
  <img src="https://img.shields.io/github/stars/din-grogu/neovim-anki-sync.svg?logo=GitHub&style=flat" alt="GitHub Stars" />
  <img src="https://img.shields.io/github/sponsors/din-grogu.svg?logo=github&style=flat&color=orange&label=Sponsor" alt="Sponsor" />
</p>

---

## 🚀 Features

* **100% Pure Lua:** Zero external dependencies (no Node.js, Python, or NPM required). It only uses `curl` in the background.
* **Stateless Cache:** Card hashes are stored directly within Anki (in the card's `Config` field). There are no local database or JSON cache files to sync across devices.
* **In-place UUID Injection:** Automatically generates and inserts unique IDs (`<!-- id: <uuid> -->`) into your notes when syncing new cards, allowing you to move cards around without losing scheduling history.
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
            deck = "Default",           -- Nome do Deck de destino no Anki
            model = "NeovimAnkiCard",   -- Nome do Modelo de nota (criado automaticamente)
            anki_url = "http://127.0.0.1:8765" -- URL do AnkiConnect
        })
    end
}
```

---

## ✍️ Card Syntax

Write your flashcards as list items (bullets or headers) containing the tag `#card`. The text on the header is the Front, and any indented lines under it become the Back:

```markdown
# Minhas Notas de Estudo

- Qual a capital do Brasil? #card
  A capital é Brasília.

- O que é o Neovim? #card
  Um editor de texto baseado em Vim, altamente extensível via Lua.
```

### Cloze Deletion Support
You can also use standard Anki Cloze syntax:
```markdown
- O Sol é uma {{c1::estrela}} no centro do nosso sistema solar. #card
```

---

## ⌨️ User Commands

The plugin registers a global user command with path auto-completion:

* `:AnkiSync` - Synchronizes the active buffer. Any newly detected cards will have their UUID comments appended in-place automatically.
* `:AnkiSync <path_to_file>` - Synchronizes a specific Markdown/Org file.

---

## 🧪 Running Integration Tests

You can run the headless integration test suite to verify the parser, UUID injector, HTTP client, and synchronization engine. The test suite automatically runs a mock server simulation if Anki is offline, or runs live integration tests if Anki is running:

```bash
nvim --headless -l tests/neovim-sync-test.lua
```

---

## 🙏 Support & Donations

If you love this tool, please consider sponsoring or donating to support its continued development!

* [GitHub Sponsors](https://github.com/sponsors/din-grogu)
