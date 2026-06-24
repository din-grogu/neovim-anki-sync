if vim.g.loaded_neovim_anki_sync then
    return
end
vim.g.loaded_neovim_anki_sync = true

-- Registra o comando global no Neovim
vim.api.nvim_create_user_command("AnkiSync", function(opts)
    local filepath = (opts.args ~= "" and opts.args) or nil
    require("neovim-anki-sync").sync(filepath)
end, {
    nargs = "?", -- Aceita 0 ou 1 argumento (o caminho do arquivo)
    complete = "file" -- Habilita o auto-completar de caminhos de arquivos do Neovim
})
