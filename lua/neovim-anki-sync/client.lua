local M = {}

M.anki_url = "http://127.0.0.1:8765"

-- Executa uma requisição síncrona ao AnkiConnect
function M.request(action, params)
    local payload = {
        action = action,
        version = 6,
        params = params or {}
    }
    
    -- Codifica a tabela Lua em JSON usando a API do Neovim
    local json_payload = vim.fn.json_encode(payload)
    
    -- Executa curl de forma segura passando os argumentos em uma lista (evita injeção de shell)
    local cmd = {
        "curl",
        "-s",
        "-X", "POST",
        "-d", json_payload,
        M.anki_url
    }
    
    local response = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error
    
    if exit_code ~= 0 then
        return nil, "Erro de rede: curl falhou com código de saída " .. tostring(exit_code)
    end
    
    if not response or response == "" then
        return nil, "Resposta vazia do AnkiConnect"
    end
    
    local ok, decoded = pcall(vim.fn.json_decode, response)
    if not ok then
        return nil, "Falha ao decodificar JSON da resposta do AnkiConnect: " .. tostring(response)
    end
    
    -- Verifica se o AnkiConnect retornou algum erro interno
    if decoded["error"] and decoded["error"] ~= vim.NIL and decoded["error"] ~= "" then
        return nil, tostring(decoded["error"])
    end
    
    return decoded["result"]
end

-- Busca notas usando uma query (ex: modelo ou deck)
function M.find_notes(query)
    return M.request("findNotes", { query = query })
end

-- Retorna informações detalhadas das notas pelos IDs
function M.notes_info(note_ids)
    return M.request("notesInfo", { notes = note_ids })
end

-- Adiciona múltiplas notas em lote
function M.add_notes(notes)
    return M.request("addNotes", { notes = notes })
end

-- Atualiza os campos de uma nota
function M.update_note_fields(note)
    return M.request("updateNoteFields", { note = note })
end

-- Deleta notas do Anki pelos IDs
function M.delete_notes(note_ids)
    return M.request("deleteNotes", { notes = note_ids })
end

return M
