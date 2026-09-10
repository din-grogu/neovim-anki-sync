# Project Structure

This is a native, stateless Neovim Lua plugin (`neovim-anki-sync`) for synchronizing flashcards from Markdown and Org files directly to Anki via AnkiConnect.

- **Entry Point (Plugin Command):** `plugin/neovim-anki-sync.lua` registers the user command `:AnkiSync [filepath]`
- **Core Lua Modules:** `lua/neovim-anki-sync/`
  - `init.lua` - Main plugin setup, deck resolution, sync orchestration, Anki note model creation, change detection, and sync execution
  - `client.lua` - AnkiConnect HTTP client wrapping `curl` with `vim.system` or `vim.fn.system` and JSON encoding/decoding
  - `parser.lua` - Markdown/Org parser: extracts `#card` bullets/headers, handles properties (`deck::`, `tags::`), converts inline markdown to HTML while preserving clozes, handles code blocks, computes DJB2 hashes, and injects UUIDs (`<!-- id: <uuid> -->`)
- **Tests:** `tests/run_tests.lua` - Headless Neovim test suite

## Tech Stack

- **Language:** Lua (Neovim Lua runtime / LuaJIT)
- **External Dependencies:** `curl` (no Node.js, Python, or npm required)
- **Integration Target:** AnkiConnect (default URL: `http://127.0.0.1:8765`)

## Architecture

**Pure Lua & Stateless:**
- Content hashes are stored directly in Anki notes (in the `Config` field as `hash:<hex> path:<hex>`).
- No local database or external state file is needed.

**Hierarchical Decks & Breadcrumbs:**
- Automatically maps folder hierarchy to Anki decks using `::` separator relative to `notes_dir` or detected project root (`.git`, `.obsidian`, `.logseq`, `.root`).
- Breadcrumbs are generated from file paths and Markdown heading hierarchies.

**Buffer-Safe UUID Injection:**
- Injects `<!-- id: <uuid> -->` directly into active Neovim buffers using `nvim_buf_set_lines` via `parse_buffer` so unsaved buffer modifications are preserved.
- Falls back to atomic disk writes in `parse_file` when the file is not currently loaded in a buffer.

## Testing

**Running Tests:**
- Run the headless test suite:
  ```bash
  nvim --headless -u NONE -l tests/run_tests.lua
  ```

## Best Practices

- **Zero External Runtimes:** Keep the plugin 100% pure Lua; rely only on Neovim built-in APIs and `curl`.
- **Buffer Safety:** When modifying files to inject UUIDs, always check if the buffer is currently loaded and use the Neovim buffer API (`nvim_buf_set_lines`).
- **Anki Cloze Integrity:** Never break Anki cloze syntax (`{{c1::...}}`) during Markdown-to-HTML conversion.
- **Robust Network Calls:** Use `-sS` and appropriate timeouts with `curl` in `client.lua` to ensure network errors are properly captured and reported.
- **Test Coverage:** Whenever parser or sync logic is modified, add or update corresponding test cases in `tests/run_tests.lua`.