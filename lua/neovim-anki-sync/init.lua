local client = require("neovim-anki-sync.client")
local parser = require("neovim-anki-sync.parser")

local M = {}

-- Configurações padrões
M.config = {
    deck = "Default",
    model = "NeovimAnkiCard",
    anki_url = "http://127.0.0.1:8765"
}

-- Configura o plugin com opções do usuário
function M.setup(opts)
    opts = opts or {}
    M.config = vim.tbl_deep_extend("force", M.config, opts)
    client.anki_url = M.config.anki_url
end

-- Garante que o modelo personalizado existe no Anki
local function ensure_anki_model()
    local models, err = client.request("modelNames")
    if not models then
        return false, err
    end
    
    local has_model = false
    for _, m in ipairs(models) do
        if m == M.config.model then
            has_model = true
            break
        end
    end
    
    if not has_model then
        -- Cria o modelo personalizado caso não exista
        local ok, create_err = client.request("createModel", {
            modelName = M.config.model,
            inOrderFields = { "Front", "Back", "UUID", "Config" },
            css = ".card {\n font-family: arial;\n font-size: 20px;\n text-align: center;\n color: black;\n background-color: white;\n}\n",
            cardTemplates = {
                {
                    Name = "Card 1",
                    Front = "{{Front}}",
                    Back = "{{FrontSide}}\n\n<hr id=answer>\n\n{{Back}}"
                }
            }
        })
        if not ok then
            return false, "Falha ao criar o modelo no Anki: " .. tostring(create_err)
        end
    end
    
    return true
end

-- Coordenador principal de sincronização
function M.sync(filepath)
    -- Se não fornecer filepath, pega o do buffer atual
    if not filepath or filepath == "" then
        filepath = vim.api.nvim_buf_get_name(0)
    end
    
    if not filepath or filepath == "" then
        vim.notify("Nenhum arquivo válido para sincronizar.", vim.log.levels.WARN, { title = "Anki Sync" })
        return false
    end
    
    -- 1. Verifica conexão com o Anki
    local version, conn_err = client.request("version")
    if not version then
        vim.notify("Não foi possível conectar ao Anki. Certifique-se de que o Anki está aberto.\nErro: " .. tostring(conn_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    
    -- 2. Garante que o deck existe
    local decks, deck_err = client.request("deckNames")
    if not decks then
        vim.notify("Erro ao buscar decks do Anki: " .. tostring(deck_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    local has_deck = false
    for _, d in ipairs(decks) do
        if d == M.config.deck then
            has_deck = true
            break
        end
    end
    if not has_deck then
        client.request("createDeck", { deck = M.config.deck })
    end
    
    -- 3. Garante que o modelo existe
    local model_ok, model_err = ensure_anki_model()
    if not model_ok then
        vim.notify(model_err, vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    
    -- 4. Parse do arquivo local e injeção de UUIDs se necessário
    local local_cards, parse_err = parser.parse_file(filepath)
    if not local_cards then
        vim.notify("Falha ao parsear arquivo: " .. tostring(parse_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    
    -- Se não houver cartões, notifica e encerra
    if #local_cards == 0 then
        vim.notify("Nenhum cartão (#card) encontrado no arquivo.", vim.log.levels.INFO, { title = "Anki Sync" })
        return true
    end
    
    -- Se houve injeção de UUIDs, recarrega o buffer atual no Neovim para o usuário ver
    vim.cmd("checktime")
    
    -- 5. Busca notas existentes no Anki para o modelo configurado
    local query = string.format("note:%s", M.config.model)
    local note_ids, find_err = client.find_notes(query)
    if not note_ids then
        vim.notify("Erro ao buscar notas do Anki: " .. tostring(find_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    
    local existing_anki_cards = {}
    if #note_ids > 0 then
        local notes, info_err = client.notes_info(note_ids)
        if not notes then
            vim.notify("Erro ao obter info das notas: " .. tostring(info_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end
        
        for _, note in ipairs(notes) do
            local uuid = note.fields.UUID and note.fields.UUID.value
            local config_val = note.fields.Config and note.fields.Config.value or ""
            local hash = config_val:match("hash:(%x+)")
            
            if uuid and uuid ~= "" then
                existing_anki_cards[uuid] = {
                    noteId = note.noteId,
                    hash = hash,
                    deck = note.deckName
                }
            end
        end
    end
    
    -- 6. Compara e monta plano de alteração
    local to_create = {}
    local to_update = {}
    local to_keep = {}
    local local_uuids = {}
    
    for _, card in ipairs(local_cards) do
        local_uuids[card.uuid] = true
        local anki_card = existing_anki_cards[card.uuid]
        
        if not anki_card then
            table.insert(to_create, card)
        elseif anki_card.hash ~= card.hash or anki_card.deck ~= M.config.deck then
            card.noteId = anki_card.noteId
            table.insert(to_update, card)
        else
            table.insert(to_keep, card)
        end
    end
    
    -- Notas para deletar do Anki (estão no Anki com o modelo mas não no arquivo local)
    local to_delete = {}
    for uuid, anki_card in pairs(existing_anki_cards) do
        if not local_uuids[uuid] then
            table.insert(to_delete, { noteId = anki_card.noteId, uuid = uuid })
        end
    end
    
    -- 7. Executa as operações no Anki
    
    -- Criar
    if #to_create > 0 then
        local new_notes = {}
        for _, card in ipairs(to_create) do
            table.insert(new_notes, {
                deckName = M.config.deck,
                modelName = M.config.model,
                fields = {
                    Front = card.front,
                    Back = card.back,
                    UUID = card.uuid,
                    Config = "hash:" .. card.hash
                },
                options = { allowDuplicate = true },
                tags = { "neovim-sync" }
            })
        end
        local create_res, create_err = client.add_notes(new_notes)
        if not create_res then
            vim.notify("Erro ao criar notas no Anki: " .. tostring(create_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end
    end
    
    -- Atualizar
    if #to_update > 0 then
        for _, card in ipairs(to_update) do
            local ok, upd_err = client.update_note_fields({
                id = card.noteId,
                fields = {
                    Front = card.front,
                    Back = card.back,
                    UUID = card.uuid,
                    Config = "hash:" .. card.hash
                }
            })
            if not ok then
                vim.notify("Erro ao atualizar nota " .. tostring(card.noteId) .. ": " .. tostring(upd_err), vim.log.levels.ERROR, { title = "Anki Sync" })
                return false
            end
        end
    end
    
    -- Deletar
    if #to_delete > 0 then
        local delete_ids = {}
        for _, card in ipairs(to_delete) do
            table.insert(delete_ids, card.noteId)
        end
        local ok, del_err = client.delete_notes(delete_ids)
        if not ok then
            vim.notify("Erro ao deletar notas no Anki: " .. tostring(del_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end
    end
    
    -- 8. Notifica o usuário
    local summary = string.format(
        "Sincronização Anki finalizada:\n- Criados: %d\n- Atualizados: %d\n- Removidos: %d\n- Inalterados: %d",
        #to_create, #to_update, #to_delete, #to_keep
    )
    vim.notify(summary, vim.log.levels.INFO, { title = "Anki Sync" })
    return true
end

return M
