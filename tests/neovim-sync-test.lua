-- tests/neovim-sync-test.lua
-- Script de teste para rodar via nvim --headless -l tests/neovim-sync-test.lua

-- 1. Configura path do Lua para incluir a pasta lua/ do plugin
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local client = require("neovim-anki-sync.client")
local parser = require("neovim-anki-sync.parser")
local sync = require("neovim-anki-sync")

-- 2. Mock de vim.notify para capturar feedbacks
local last_notifications = {}
_G.vim.notify = function(msg, level, opts)
    table.insert(last_notifications, msg)
    print("[VIM NOTIFY] (" .. tostring(level) .. ") " .. msg)
end

-- 3. Detecta se AnkiConnect está ativo
local has_real_anki = false
local ok, version = pcall(function()
    return client.request("version")
end)
if ok and version then
    has_real_anki = true
    print("AnkiConnect real detectado na porta 8765. Rodando teste de integração real.")
else
    print("AnkiConnect offline. Ativando camada MOCK de simulação do AnkiConnect para teste unitário.")
end

-- 4. Camada Mock do AnkiConnect
local mock_db = {
    models = { "Default" },
    decks = { "Default" },
    notes = {} -- ID -> Note object
}
local mock_id_counter = 1000

if not has_real_anki then
    client.request = function(action, params)
        if action == "version" then
            return 6
        elseif action == "modelNames" then
            return mock_db.models
        elseif action == "deckNames" then
            return mock_db.decks
        elseif action == "createDeck" then
            table.insert(mock_db.decks, params.deck)
            return true
        elseif action == "createModel" then
            table.insert(mock_db.models, params.modelName)
            return true
        elseif action == "findNotes" then
            -- Retorna todas as notas criadas
            local ids = {}
            for id, _ in pairs(mock_db.notes) do
                table.insert(ids, id)
            end
            return ids
        elseif action == "notesInfo" then
            local result = {}
            for _, id in ipairs(params.notes) do
                local note = mock_db.notes[id]
                if note then
                    table.insert(result, {
                        noteId = id,
                        deckName = note.deckName,
                        modelName = note.modelName,
                        fields = note.fields
                    })
                end
            end
            return result
        elseif action == "addNotes" then
            local ids = {}
            for _, note in ipairs(params.notes) do
                mock_id_counter = mock_id_counter + 1
                mock_db.notes[mock_id_counter] = {
                    deckName = note.deckName,
                    modelName = note.modelName,
                    fields = {
                        Front = { value = note.fields.Front },
                        Back = { value = note.fields.Back },
                        UUID = { value = note.fields.UUID },
                        Config = { value = note.fields.Config }
                    }
                }
                table.insert(ids, mock_id_counter)
            end
            return ids
        elseif action == "updateNoteFields" then
            local note = mock_db.notes[params.note.id]
            if note then
                for k, v in pairs(params.note.fields) do
                    note.fields[k] = { value = v }
                end
                return true
            end
            return nil, "Nota não encontrada"
        elseif action == "deleteNotes" then
            for _, id in ipairs(params.notes) do
                mock_db.notes[id] = nil
            end
            return true
        end
        return nil, "Ação não mockada: " .. tostring(action)
    end
end

-- 5. Execução do Teste de Integração
local function run_tests()
    local test_filepath = "tests/test_cards.md"
    
    -- Inicializa o plugin
    sync.setup({
        deck = "NeovimTestDeck",
        model = "NeovimTestModel"
    })
    
    -- Garante limpeza pré-teste
    os.remove(test_filepath)
    mock_db.notes = {}
    
    -- Criar arquivo markdown de teste inicial
    local f = io.open(test_filepath, "w")
    f:write([[
# Cartões de Teste

- Cartão A #card
  Verso do cartão A.

- Cartão B #card
  Verso do cartão B.
]])
    f:close()
    
    print("\n--- PASSO 1: Sincronização Inicial (Criação de novos cartões e injeção de UUID) ---")
    local ok1 = sync.sync(test_filepath)
    assert(ok1 == true, "Falha na sincronização inicial")
    
    -- Verifica se os UUIDs foram injetados no arquivo
    local f_read = io.open(test_filepath, "r")
    local content = f_read:read("*all")
    f_read:close()
    
    assert(content:match("<!%-%-%s*id:%s*.-%s*%-%->") ~= nil, "UUIDs não foram injetados no arquivo")
    print("UUIDs injetados com sucesso no arquivo Markdown!")
    
    -- Salva os UUIDs gerados para testes subsequentes
    local parsed_cards = parser.parse_file(test_filepath)
    assert(#parsed_cards == 2, "Deveriam existir 2 cartões")
    local uuid_a = parsed_cards[1].uuid
    local uuid_b = parsed_cards[2].uuid
    print("UUID Cartão A: " .. uuid_a)
    print("UUID Cartão B: " .. uuid_b)
    
    print("\n--- PASSO 2: Rodar Sync Novamente (Sem nenhuma modificação) ---")
    last_notifications = {}
    local ok2 = sync.sync(test_filepath)
    assert(ok2 == true)
    local notification = last_notifications[#last_notifications]
    assert(notification:match("Inalterados: 2") ~= nil, "Deveria ter mantido os 2 cartões inalterados")
    print("Sincronização redundante evitada com sucesso!")
    
    print("\n--- PASSO 3: Modificar um cartão localmente (Atualização) ---")
    -- Modifica o verso do cartão B
    local lines = {}
    local f_lines = io.open(test_filepath, "r")
    for line in f_lines:lines() do
        if line:match("Verso do cartão B%.") then
            line = "  Verso do cartão B modificado."
        end
        table.insert(lines, line)
    end
    f_lines:close()
    
    local f_write = io.open(test_filepath, "w")
    f_write:write(table.concat(lines, "\n") .. "\n")
    f_write:close()
    
    last_notifications = {}
    local ok3 = sync.sync(test_filepath)
    assert(ok3 == true)
    notification = last_notifications[#last_notifications]
    assert(notification:match("Atualizados: 1") ~= nil, "Deveria ter atualizado 1 cartão")
    assert(notification:match("Inalterados: 1") ~= nil, "Deveria ter mantido 1 cartão inalterado")
    print("Cartão atualizado com sucesso!")
    
    print("\n--- PASSO 4: Deletar um cartão localmente (Remoção) ---")
    -- Remove o cartão A
    local clean_lines = {}
    local skip_mode = false
    local f_del = io.open(test_filepath, "r")
    for line in f_del:lines() do
        if line:match("Cartão A") then
            skip_mode = true
        elseif skip_mode and not line:match("^%s") and line ~= "" then
            skip_mode = false
        end
        if not skip_mode then
            table.insert(clean_lines, line)
        end
    end
    f_del:close()
    
    local f_write_del = io.open(test_filepath, "w")
    f_write_del:write(table.concat(clean_lines, "\n") .. "\n")
    f_write_del:close()
    
    last_notifications = {}
    local ok4 = sync.sync(test_filepath)
    assert(ok4 == true)
    notification = last_notifications[#last_notifications]
    assert(notification:match("Removidos: 1") ~= nil, "Deveria ter removido 1 cartão")
    assert(notification:match("Inalterados: 1") ~= nil, "Deveria ter mantido 1 cartão inalterado")
    print("Cartão excluído com sucesso do Anki!")
    
    -- Limpeza final
    os.remove(test_filepath)
    print("\n==================================================")
    print("             TODOS OS TESTES PASSARAM!            ")
    print("==================================================")
end

local success, err = pcall(run_tests)
if not success then
    print("\n[ERRO NO TESTE]: " .. tostring(err))
    os.exit(1)
else
    os.exit(0)
end
