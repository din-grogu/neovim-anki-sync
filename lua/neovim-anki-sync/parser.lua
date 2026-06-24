local M = {}

-- Gerador de UUID simples
function M.generate_uuid()
    math.randomseed(os.time() + os.clock() * 1000)
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

-- Função de hashing DJB2 em Lua
function M.hash(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 4294967296
    end
    return string.format("%x", hash)
end

-- Varre as linhas do arquivo e retorna a lista crua de cartões encontrados
function M.parse_lines(lines)
    local cards = {}
    local current_card = nil
    
    for line_idx, line in ipairs(lines) do
        -- Detecta o início de um cartão: item de lista ou cabeçalho contendo '#card'
        local is_bullet_card = line:match("^%s*[%-%*]%s.*#card")
        local is_header_card = line:match("^%s*#+%s.*#card")
        
        if is_bullet_card or is_header_card then
            if current_card then
                table.insert(cards, current_card)
            end
            
            -- Extrai UUID existente se houver
            local uuid = line:match("<!%-%-%s*id:%s*(.-)%s*%-%->")
            
            current_card = {
                raw_header = line,
                line_number = line_idx,
                uuid = uuid,
                body_lines = {}
            }
        elseif current_card then
            -- Verifica se a linha pertence ao corpo do cartão atual (indentada ou vazia)
            local is_indented = line:match("^%s+")
            local is_empty = line:match("^%s*$")
            
            if is_indented or is_empty then
                table.insert(current_card.body_lines, line)
            else
                -- Linha sem indentação finaliza o cartão atual
                table.insert(cards, current_card)
                current_card = nil
            end
        end
    end
    
    if current_card then
        table.insert(cards, current_card)
    end
    
    -- Pós-processamento e cálculo de hashes
    local processed_cards = {}
    for _, raw_card in ipairs(cards) do
        local body = table.concat(raw_card.body_lines, "\n")
        
        -- Limpa a frente do cartão removendo a tag '#card' e o comentário de ID
        local clean_front = raw_card.raw_header
        clean_front = clean_front:gsub("#card", "")
        clean_front = clean_front:gsub("<!%-%-%s*id:%s*(.-)%s*%-%->", "")
        
        -- Remove marcadores de lista ou cabeçalho
        clean_front = clean_front:gsub("^%s*[%-%*]%s*", "")
        clean_front = clean_front:gsub("^%s*#+%s*", "")
        clean_front = vim.trim(clean_front)
        
        local clean_body = vim.trim(body)
        local full_content = clean_front .. "\n" .. clean_body
        
        table.insert(processed_cards, {
            uuid = raw_card.uuid,
            front = clean_front,
            back = clean_body,
            hash = M.hash(full_content),
            line_number = raw_card.line_number,
            raw_header = raw_card.raw_header
        })
    end
    
    return processed_cards
end

-- Carrega o arquivo, extrai os cartões, gera e injeta UUIDs em falta diretamente no arquivo
function M.parse_file(filepath)
    local f = io.open(filepath, "r")
    if not f then
        return nil, "Não foi possível abrir o arquivo: " .. filepath
    end
    
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    
    local cards = M.parse_lines(lines)
    local needs_write = false
    
    -- Injeta UUIDs nos cartões que não possuem
    for _, card in ipairs(cards) do
        if not card.uuid or card.uuid == "" then
            local new_uuid = M.generate_uuid()
            card.uuid = new_uuid
            
            -- Adiciona o comentário do UUID no final da linha do cabeçalho original
            local orig_line = lines[card.line_number]
            lines[card.line_number] = orig_line .. " <!-- id: " .. new_uuid .. " -->"
            needs_write = true
        end
    end
    
    -- Grava as alterações de volta no arquivo
    if needs_write then
        local out = io.open(filepath, "w")
        if out then
            out:write(table.concat(lines, "\n") .. "\n")
            out:close()
        end
    end
    
    return cards
end

return M
