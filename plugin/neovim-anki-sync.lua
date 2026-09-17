if vim.g.loaded_neovim_anki_sync then
    return
end
vim.g.loaded_neovim_anki_sync = true

-- Registra o comando global no Neovim
vim.api.nvim_create_user_command("AnkiSync", function(opts)
    local filepath = (opts.args ~= "" and opts.args) or nil
    package.loaded["neovim-anki-sync.table"] = nil
    package.loaded["neovim-anki-sync.parser"] = nil
    package.loaded["neovim-anki-sync.client"] = nil
    package.loaded["neovim-anki-sync"] = nil
    require("neovim-anki-sync").sync(filepath)
end, {
    nargs = "?", -- Aceita 0 ou 1 argumento (o caminho do arquivo)
    complete = "file" -- Habilita o auto-completar de caminhos de arquivos do Neovim
})

-- Sincroniza todos os arquivos .md dentro de um diretório (recursivamente).
-- O diretório deve estar dentro do notes_dir configurado.
-- Uso: :AnkiSyncDir [caminho]   (sem argumento usa o notes_dir configurado)
vim.api.nvim_create_user_command("AnkiSyncDir", function(opts)
    local dirpath = (opts.args ~= "" and opts.args) or nil
    package.loaded["neovim-anki-sync.table"] = nil
    package.loaded["neovim-anki-sync.parser"] = nil
    package.loaded["neovim-anki-sync.client"] = nil
    package.loaded["neovim-anki-sync"] = nil
    require("neovim-anki-sync").sync_dir(dirpath)
end, {
    nargs = "?",       -- Aceita 0 ou 1 argumento (caminho do diretório)
    complete = "dir",  -- Tab-complete de diretórios
})

-- Remove todos os decks vazios do Anki (sem cartões).
-- Uso: :AnkiCleanup
vim.api.nvim_create_user_command("AnkiCleanup", function()
    package.loaded["neovim-anki-sync.table"] = nil
    package.loaded["neovim-anki-sync.parser"] = nil
    package.loaded["neovim-anki-sync.client"] = nil
    package.loaded["neovim-anki-sync"] = nil
    require("neovim-anki-sync").cleanup_empty_decks()
end, {
    nargs = 0,
})
