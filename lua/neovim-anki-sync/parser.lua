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

-- Converte sintaxe básica de Markdown inline para HTML (bold, italic, mark, inline code, links)
-- Preserva anotações Anki Cloze {{c1::...}}
function M.markdown_inline_to_html(text)
    if not text or text == "" then return "" end

    -- 1. Preserva inline code primeiro para evitar colisões
    local code_spans = {}
    text = text:gsub("`([^`]+)`", function(code)
        table.insert(code_spans, code)
        return "@@@CODESPAN" .. #code_spans .. "@@@"
    end)

    -- 2. Preserva anotações de Cloze do Anki (ex: {{c1::...}} ou {{c1::...::hint}})
    local cloze_spans = {}
    text = text:gsub("{{c%d+::.-}}", function(cloze)
        table.insert(cloze_spans, cloze)
        return "@@@CLOZESPAN" .. #cloze_spans .. "@@@"
    end)

    -- 3. Links Markdown: [texto](url)
    text = text:gsub("%[([^%]]+)%]%(([^%)]+)%)", '<a href="%2">%1</a>')

    -- 4. Negrito: **bold** ou __bold__
    text = text:gsub("%*%*([^*]+)%*%*", "<b>%1</b>")
    text = text:gsub("%_%_([^_]+)%_%_", "<b>%1</b>")

    -- 5. Destaque: ==highlight==
    text = text:gsub("%=%=(.-)%=%=", "<mark>%1</mark>")

    -- 6. Itálico: *italic* ou _italic_
    text = text:gsub("%*([^*]+)%*", "<i>%1</i>")
    text = text:gsub("([%s%p]|^)%_([^_]+)%_([%s%p]|$)", "%1<i>%2</i>%3")

    -- 7. Restaura clozes
    for i, cloze in ipairs(cloze_spans) do
        text = text:gsub("@@@CLOZESPAN" .. i .. "@@@", function() return cloze end)
    end

    -- 8. Restaura code spans com tag <code>
    for i, code in ipairs(code_spans) do
        text = text:gsub("@@@CODESPAN" .. i .. "@@@", function()
            local clean_code = code:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
            return "<code>" .. clean_code .. "</code>"
        end)
    end

    return text
end

-- Varre as linhas do arquivo e retorna a lista crua de cartões encontrados
function M.parse_lines(lines)
    local cards = {}
    local current_card = nil
    
    local global_properties = {}
    local reading_globals = true
    
    local breadcrumbs = {}
    local bullet_stack = {}
    local in_code_block = false
    
    for line_idx, line in ipairs(lines) do
        -- Rastreia blocos de código com cerca (``` ou ~~~)
        if line:match("^%s*```") or line:match("^%s*~~~") then
            in_code_block = not in_code_block
            if current_card then
                table.insert(current_card.body_lines, line)
            end
        elseif in_code_block then
            -- Dentro de um bloco de código, apenas anexa ao cartão ativo (se houver)
            if current_card then
                table.insert(current_card.body_lines, line)
            end
        else
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
            
            local indent_str = line:match("^(%s*)")
            local card_indent_len = #indent_str
            
            local uuid = line:match("<!%-%-%s*id:%s*(.-)%s*%-%->")
            
            -- Copia os breadcrumbs atuais para o cartão
            local card_breadcrumbs = {}
            for _, b in pairs(breadcrumbs) do
                table.insert(card_breadcrumbs, b)
            end
            
            -- Copia os parent bullets atuais para o cartão
            local card_parent_bullets = {}
            for _, b in ipairs(bullet_stack) do
                if b.indent < card_indent_len then
                    table.insert(card_parent_bullets, b.text)
                end
            end
            
            current_card = {
                raw_header = line,
                line_number = line_idx,
                uuid = uuid,
                body_lines = {},
                properties = {},
                breadcrumbs = card_breadcrumbs,
                parent_bullets = card_parent_bullets,
                indent_len = card_indent_len
            }
        elseif current_card then
            -- Linha dentro de um cartão
            local line_indent_str = line:match("^(%s*)")
            local line_indent_len = #line_indent_str
            local is_empty = line:match("^%s*$")
            
            if is_empty or line_indent_len > current_card.indent_len then
                -- Verifica se a linha é uma propriedade
                local k, v = parse_property(line)
                if k then
                    current_card.properties[k] = v
                else
                    table.insert(current_card.body_lines, line)
                end
            else
                -- A linha não é um filho do cartão atual
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
        end -- Fecha o bloco else de not in_code_block
    end -- Fecha o loop for line_idx, line in ipairs(lines)
    
    if current_card then
        table.insert(cards, current_card)
    end
    
    -- Converte linhas de corpo com bullets para HTML mantendo a hierarquia e blocos de código
    local function markdown_list_to_html(lines)
        local html = ""
        local stack = {}
        local in_fenced_block = false
        local code_block_lines = {}

        for _, line in ipairs(lines) do
            if line:match("^%s*```") or line:match("^%s*~~~") then
                if in_fenced_block then
                    in_fenced_block = false
                    local code_content = table.concat(code_block_lines, "\n")
                    code_content = code_content:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                    if #stack > 0 then
                        html = html .. "<pre><code>" .. code_content .. "</code></pre>"
                    else
                        html = html .. "<pre><code>" .. code_content .. "</code></pre><br/>"
                    end
                    code_block_lines = {}
                else
                    in_fenced_block = true
                    code_block_lines = {}
                end
            elseif in_fenced_block then
                table.insert(code_block_lines, line)
            else
                local indent, bullet, text = line:match("^(%s*)([%-%*])%s(.*)")
                if indent then
                    local indent_len = #indent
                    while #stack > 0 and stack[#stack] > indent_len do
                        html = html .. "</li></ul>"
                        table.remove(stack)
                    end
                    
                    if #stack > 0 and stack[#stack] == indent_len then
                        html = html .. "</li>"
                    end
                    
                    if #stack == 0 or stack[#stack] < indent_len then
                        html = html .. "<ul>"
                        table.insert(stack, indent_len)
                    end
                    
                    html = html .. "<li>" .. M.markdown_inline_to_html(vim.trim(text))
                else
                    if vim.trim(line) ~= "" then
                        if #stack > 0 then
                            html = html .. "<br/>" .. M.markdown_inline_to_html(vim.trim(line))
                        else
                            html = html .. M.markdown_inline_to_html(vim.trim(line)) .. "<br/>"
                        end
                    end
                end
            end
        end
        
        while #stack > 0 do
            html = html .. "</li></ul>"
            table.remove(stack)
        end
        
        return html
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
        clean_front = M.markdown_inline_to_html(clean_front)
        
        local clean_body = markdown_list_to_html(raw_card.body_lines)
        if clean_body == "" and vim.trim(body) ~= "" then
            clean_body = M.markdown_inline_to_html(vim.trim(body))
        end
        
        -- Verifica se o usuário já especificou algum cloze manualmente
        local has_cloze = (clean_front .. clean_body):match("{{c%d+::")
        if not has_cloze then
            if clean_body ~= "" then
                clean_body = "{{c1::\n" .. clean_body .. "\n}}"
            else
                -- Anki requires at least one cloze deletion for cloze note types
                clean_front = clean_front .. " {{c1::}}"
            end
        end
        
        -- Multiline card logic: Combines parent and children in the front field
        local final_front = clean_front .. "\n" .. clean_body
        
        -- O verso fica vazio no formato multiline, já que o próprio cloze revela a resposta
        local final_back = ""
        local full_content = final_front
        
        -- Extrai tags em linha do cabeçalho
        local inline_tags = {}
        for tag in raw_card.raw_header:gmatch("#([%w_-]+)") do
            if tag ~= "card" then
                table.insert(inline_tags, tag)
            end
        end
        
        table.insert(processed_cards, {
            front = final_front,
            back = final_back,
            uuid = raw_card.uuid,
            hash = M.hash(full_content),
            properties = raw_card.properties,
            global_properties = global_properties,
            line_number = raw_card.line_number,
            raw_header = raw_card.raw_header,
            breadcrumbs = raw_card.breadcrumbs,
            parent_bullets = raw_card.parent_bullets,
            inline_tags = inline_tags
        })
    end
    
    return processed_cards
end

--- Analisa as linhas de um buffer carregado no Neovim e injeta UUIDs diretamente no buffer
function M.parse_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil, "Buffer inválido"
    end
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cards = M.parse_lines(lines)
    local modified = false
    
    for _, card in ipairs(cards) do
        if not card.uuid or card.uuid == "" then
            local new_uuid = M.generate_uuid()
            card.uuid = new_uuid
            
            local orig_line = lines[card.line_number]
            local new_line = orig_line .. " <!-- id: " .. new_uuid .. " -->"
            lines[card.line_number] = new_line
            vim.api.nvim_buf_set_lines(bufnr, card.line_number - 1, card.line_number, false, { new_line })
            modified = true
        end
    end
    
    return cards, nil, modified
end

--- Analisa um arquivo pelo caminho em disco. Se o arquivo estiver aberto em buffer, delega para parse_buffer.
function M.parse_file(filepath)
    -- Verifica se o arquivo está atualmente carregado em algum buffer do Neovim
    local real_path = vim.fn.resolve(vim.fn.fnamemodify(filepath, ":p"))
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            if bufname ~= "" and vim.fn.resolve(vim.fn.fnamemodify(bufname, ":p")) == real_path then
                return M.parse_buffer(bufnr)
            end
        end
    end

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
    
    return cards, nil, needs_write
end

return M
