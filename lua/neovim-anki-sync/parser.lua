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

-- Extrai propriedades Logseq de uma linha (ex: `deck:: MeuBaralho`)
local function parse_property(line)
    local key, value = line:match("^%s*(%w[%w%-]*)::%s*(.+)")
    if key and value then
        return key:lower(), vim.trim(value)
    end
    return nil, nil
end

-- Varre as linhas do arquivo e retorna a lista crua de cartões encontrados
function M.parse_lines(lines)
    local cards = {}
    local current_card = nil
    
    local global_properties = {}
    local reading_globals = true
    
    local breadcrumbs = {}
    local bullet_stack = {}
    
    for line_idx, line in ipairs(lines) do
        -- Lógica de propriedades globais no início do arquivo
        if reading_globals then
            local k, v = parse_property(line)
            if k then
                global_properties[k] = v
            elseif vim.trim(line) ~= "" and not line:match("^%s*#") then
                reading_globals = false
            end
        end
        
        -- Atualiza Breadcrumbs baseado em cabeçalhos (Markdown)
        local header_level, header_text = line:match("^%s*(#+)%s+(.*)")
        if header_level then
            local level = #header_level
            -- Trunca níveis mais profundos
            while #breadcrumbs >= level do
                table.remove(breadcrumbs)
            end
            breadcrumbs[level] = header_text
            -- Reset bullet stack when entering a new header
            bullet_stack = {}
        end
        
        -- Detecta item de lista (bullet) para contexto
        local indent, bullet_text = line:match("^(%s*)[%-%*]%s(.*)")
        
        -- Detecta o início de um cartão
        local is_bullet_card = line:match("^%s*[%-%*]%s.*#card")
        local is_header_card = line:match("^%s*#+%s.*#card")
        
        if is_bullet_card or is_header_card then
            if current_card then
                table.insert(cards, current_card)
            end
            
            local uuid = line:match("<!%-%-%s*id:%s*(.-)%s*%-%->")
            
            -- Copia os breadcrumbs atuais para o cartão
            local card_breadcrumbs = {}
            for _, b in pairs(breadcrumbs) do
                table.insert(card_breadcrumbs, b)
            end
            
            -- Copia os parent bullets atuais para o cartão
            local card_parent_bullets = {}
            for _, b in ipairs(bullet_stack) do
                table.insert(card_parent_bullets, b.text)
            end
            
            current_card = {
                raw_header = line,
                line_number = line_idx,
                uuid = uuid,
                body_lines = {},
                properties = {},
                breadcrumbs = card_breadcrumbs,
                parent_bullets = card_parent_bullets
            }
        elseif current_card then
            -- Linha dentro de um cartão
            local is_indented = line:match("^%s+")
            local is_empty = line:match("^%s*$")
            
            if is_indented or is_empty then
                -- Verifica se a linha é uma propriedade
                local k, v = parse_property(line)
                if k then
                    current_card.properties[k] = v
                else
                    table.insert(current_card.body_lines, line)
                end
            else
                -- Linha não identada termina o cartão
                table.insert(cards, current_card)
                current_card = nil
            end
        end
        
        -- Se for um bullet, mas não for um header, atualiza o stack
        if bullet_text and not header_level then
            local indent_len = #indent
            -- Trunca bullets com indentação maior ou igual
            while #bullet_stack > 0 and bullet_stack[#bullet_stack].indent >= indent_len do
                table.remove(bullet_stack)
            end
            
            -- Limpa o texto do bullet se tiver #card (para não acumular)
            local clean_bullet = bullet_text:gsub("#card", ""):gsub("<!%-%-%s*id:%s*(.-)%s*%-%->", "")
            clean_bullet = vim.trim(clean_bullet)
            
            table.insert(bullet_stack, {indent = indent_len, text = clean_bullet})
        end
    end
    
    if current_card then
        table.insert(cards, current_card)
    end
    
    -- Pós-processamento
    local processed_cards = {}
    for _, raw_card in ipairs(cards) do
        local body = table.concat(raw_card.body_lines, "\n")
        
        local clean_front = raw_card.raw_header
        clean_front = clean_front:gsub("#card", "")
        clean_front = clean_front:gsub("<!%-%-%s*id:%s*(.-)%s*%-%->", "")
        clean_front = clean_front:gsub("^%s*[%-%*]%s*", "")
        clean_front = clean_front:gsub("^%s*#+%s*", "")
        clean_front = vim.trim(clean_front)
        
        local clean_body = vim.trim(body)
        local full_content = clean_front .. "\n" .. clean_body
        
        -- Extrai tags em linha do cabeçalho
        local inline_tags = {}
        for tag in raw_card.raw_header:gmatch("#([%w_-]+)") do
            if tag ~= "card" then
                table.insert(inline_tags, tag)
            end
        end
        
        table.insert(processed_cards, {
            uuid = raw_card.uuid,
            front = clean_front,
            back = clean_body,
            hash = M.hash(full_content),
            line_number = raw_card.line_number,
            raw_header = raw_card.raw_header,
            breadcrumbs = raw_card.breadcrumbs,
            parent_bullets = raw_card.parent_bullets,
            properties = raw_card.properties,
            global_properties = global_properties,
            inline_tags = inline_tags
        })
    end
    
    return processed_cards
end

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
    
    for _, card in ipairs(cards) do
        if not card.uuid or card.uuid == "" then
            local new_uuid = M.generate_uuid()
            card.uuid = new_uuid
            
            local orig_line = lines[card.line_number]
            lines[card.line_number] = orig_line .. " <!-- id: " .. new_uuid .. " -->"
            needs_write = true
        end
    end
    
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
