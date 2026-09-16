local M = {}

--- Limpa uma linha de tabela removendo marcador de bullet se for o caso
function M.clean_row(line)
    if not line then return "" end
    local trimmed = vim.trim(line)
    local after_bullet = trimmed:match("^[%-%*]%s+(.*)")
    if after_bullet and after_bullet:find("|") then
        return vim.trim(after_bullet)
    end
    return trimmed
end

--- Divide uma linha de tabela Markdown em células, respeitando pipes escapados (\|) e código inline.
function M.split_cells(line)
    if not line or line == "" then return {} end
    local trimmed = M.clean_row(line)

    -- 1. Preserva barras invertidas escapadas \\
    local escaped_slashes = {}
    trimmed = trimmed:gsub("\\\\", function()
        table.insert(escaped_slashes, "\\")
        return "@@@ESCAPEDSLASH" .. #escaped_slashes .. "@@@"
    end)

    -- 2. Preserva pipes escapados \|
    local escaped_pipes = {}
    trimmed = trimmed:gsub("\\|", function()
        table.insert(escaped_pipes, "|")
        return "@@@ESCAPEDPIPE" .. #escaped_pipes .. "@@@"
    end)

    -- 3. Preserva blocos de código inline `...` e protege pipes internos
    local code_spans = {}
    trimmed = trimmed:gsub("`([^`]+)`", function(code)
        local protected = code:gsub("|", "@@@CODEPIPE@@@")
        table.insert(code_spans, protected)
        return "`@@@CODESPAN" .. #code_spans .. "@@@`"
    end)

    -- 4. Remove pipes delimitadores opcionais no início e no fim da linha
    if trimmed:sub(1, 1) == "|" then
        trimmed = trimmed:sub(2)
    end
    if trimmed:sub(-1) == "|" then
        trimmed = trimmed:sub(1, -2)
    end

    -- 5. Divide as células pelo delimitador | sem descartar células vazias
    local raw_cells = {}
    local from = 1
    local delim_from, delim_to = string.find(trimmed, "|", from, true)
    while delim_from do
        table.insert(raw_cells, string.sub(trimmed, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(trimmed, "|", from, true)
    end
    table.insert(raw_cells, string.sub(trimmed, from))

    -- 6. Restaura placeholders e limpa espaços ao redor de cada célula
    local cells = {}
    for _, cell in ipairs(raw_cells) do
        -- Restaura código inline
        cell = cell:gsub("`@@@CODESPAN(%d+)@@@`", function(idx)
            local code = code_spans[tonumber(idx)] or ""
            code = code:gsub("@@@CODEPIPE@@@", "|")
            return "`" .. code .. "`"
        end)

        -- Restaura pipes escapados
        cell = cell:gsub("@@@ESCAPEDPIPE(%d+)@@@", function(idx)
            return escaped_pipes[tonumber(idx)] or "|"
        end)

        -- Restaura barras escapadas
        cell = cell:gsub("@@@ESCAPEDSLASH(%d+)@@@", function(idx)
            return escaped_slashes[tonumber(idx)] or "\\"
        end)

        table.insert(cells, vim.trim(cell))
    end

    return cells
end

--- Verifica se a linha tem características de uma linha de tabela Markdown
function M.is_table_row(line)
    if not line then return false end
    local trimmed = vim.trim(line)
    if trimmed == "" then return false end
    if line:match("^%s*#+%s") then return false end
    local cleaned = M.clean_row(trimmed)
    if cleaned:match("^[%-%*]%s") then return false end
    return cleaned:find("|") ~= nil
end

--- Verifica se a linha é uma linha separadora/delimitadora de cabeçalho Markdown (| --- | :---: |)
function M.is_delimiter_row(line)
    if not line then return false end
    local trimmed = vim.trim(line)
    if trimmed == "" then return false end
    local cleaned = M.clean_row(trimmed)
    if cleaned:match("^[%-%*]%s") then return false end
    if not cleaned:find("|") then return false end
    -- Deve conter apenas |, :, -, e espaços
    if cleaned:match("[^%s%|%:%-]") then return false end

    local cells = M.split_cells(cleaned)
    if #cells == 0 then return false end

    for _, cell in ipairs(cells) do
        -- Cada célula deve ter pelo menos um hífen e no máximo dois : (um em cada ponta)
        if not cell:match("^:?%-+:?$") then
            return false
        end
    end
    return true
end

--- Extrai os alinhamentos de cada coluna a partir da linha delimitadora
function M.parse_alignments(delimiter_line)
    local cells = M.split_cells(delimiter_line)
    local alignments = {}
    for _, cell in ipairs(cells) do
        local has_left = cell:sub(1, 1) == ":"
        local has_right = cell:sub(-1) == ":"
        if has_left and has_right then
            table.insert(alignments, "center")
        elseif has_right then
            table.insert(alignments, "right")
        elseif has_left then
            table.insert(alignments, "left")
        else
            table.insert(alignments, nil)
        end
    end
    return alignments
end

--- Determina se uma tabela Markdown é iniciada a partir do índice idx do vetor de linhas
function M.is_table_start(lines, idx)
    if not lines or idx >= #lines then return false end
    local line1 = lines[idx]
    local line2 = lines[idx + 1]

    if not M.is_table_row(line1) then return false end
    if not M.is_delimiter_row(line2) then return false end

    local headers = M.split_cells(line1)
    local delims = M.split_cells(line2)
    return #headers > 0 and #delims > 0
end

--- Extrai o bloco contíguo de linhas de uma tabela Markdown
function M.extract_table_block(lines, idx)
    local table_lines = { lines[idx], lines[idx + 1] }
    local curr = idx + 2
    while curr <= #lines do
        local line = lines[curr]
        if M.is_table_row(line) and not M.is_delimiter_row(line) then
            table.insert(table_lines, line)
            curr = curr + 1
        else
            break
        end
    end
    return table_lines, curr
end

--- Converte um bloco de linhas de tabela Markdown em HTML semântico com classe anki-table
function M.markdown_table_to_html(table_lines, inline_converter)
    inline_converter = inline_converter or function(s) return s end
    if not table_lines or #table_lines < 2 then return "" end

    local header_line = table_lines[1]
    local delimiter_line = table_lines[2]

    local headers = M.split_cells(header_line)
    local alignments = M.parse_alignments(delimiter_line)
    local num_cols = math.max(#headers, #alignments)

    local parts = { '<table class="anki-table">' }

    -- thead
    table.insert(parts, "<thead><tr>")
    for col_idx = 1, num_cols do
        local th_text = headers[col_idx] or ""
        local align = alignments[col_idx]
        local style_attr = align and string.format(' style="text-align: %s;"', align) or ""
        table.insert(parts, string.format("<th%s>%s</th>", style_attr, inline_converter(th_text)))
    end
    table.insert(parts, "</tr></thead>")

    -- tbody
    if #table_lines > 2 then
        table.insert(parts, "<tbody>")
        for r = 3, #table_lines do
            local row_cells = M.split_cells(table_lines[r])
            table.insert(parts, "<tr>")
            for col_idx = 1, num_cols do
                local td_text = row_cells[col_idx] or ""
                local align = alignments[col_idx]
                local style_attr = align and string.format(' style="text-align: %s;"', align) or ""
                table.insert(parts, string.format("<td%s>%s</td>", style_attr, inline_converter(td_text)))
            end
            table.insert(parts, "</tr>")
        end
        table.insert(parts, "</tbody>")
    end

    table.insert(parts, "</table>")
    return table.concat(parts, "")
end

return M
