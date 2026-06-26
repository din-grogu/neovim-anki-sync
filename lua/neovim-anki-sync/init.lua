local client = require("neovim-anki-sync.client")
local parser = require("neovim-anki-sync.parser")

local M = {}

-- Default configuration
M.config = {
    deck = "Default",            -- Fallback deck when file is outside notes_dir
    model = "NeovimAnkiCard",    -- Note type name in Anki
    anki_url = "http://127.0.0.1:8765",
    notes_dir = nil              -- Root directory for hierarchical deck mapping (optional)
}

-- Configure the plugin with user options
function M.setup(opts)
    opts = opts or {}
    M.config = vim.tbl_deep_extend("force", M.config, opts)
    client.anki_url = M.config.anki_url
end

--- Resolve the Anki deck name from a filepath based on directory hierarchy.
--- If `notes_dir` is configured, the relative path from `notes_dir` to the
--- file's parent directory is converted to the Anki sub-deck separator `::`.
---
--- Example:
---   notes_dir = "/home/user/notes"
---   filepath  = "/home/user/notes/Concursos/Estratégia/CFBM/cards.md"
---   result    = "Concursos::Estratégia::CFBM"
---
--- If the file is directly inside `notes_dir` (no subdirectories), the
--- fallback `M.config.deck` is used instead.
local function resolve_deck_name(filepath)
    local notes_dir = M.config.notes_dir
    if not notes_dir then
        return M.config.deck
    end

    -- Normalize both paths: resolve symlinks, trailing slashes, etc.
    notes_dir = vim.fn.resolve(vim.fn.fnamemodify(notes_dir, ":p"))
    filepath = vim.fn.resolve(vim.fn.fnamemodify(filepath, ":p"))

    -- Get the directory containing the file
    local file_dir = vim.fn.fnamemodify(filepath, ":h")

    -- Ensure trailing slash for prefix matching
    if not notes_dir:match("/$") then
        notes_dir = notes_dir .. "/"
    end
    if not file_dir:match("/$") then
        file_dir = file_dir .. "/"
    end

    -- Check if the file lives under notes_dir
    if not file_dir:sub(1, #notes_dir) == notes_dir then
        return M.config.deck
    end

    -- Extract the relative path
    local relative = file_dir:sub(#notes_dir + 1)

    -- Remove trailing slash
    relative = relative:gsub("/$", "")

    -- If the file is directly inside notes_dir (no subdirectory), use fallback deck
    if relative == "" then
        return M.config.deck
    end

    -- Convert directory separators to Anki's sub-deck separator `::`
    local deck_name = relative:gsub("/", "::")

    return deck_name
end

-- Ensure the custom note model exists in Anki
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
            return false, "Failed to create Anki model: " .. tostring(create_err)
        end
    end

    return true
end

-- Ensure a given deck exists in Anki, creating it if necessary
local function ensure_deck(deck_name)
    local decks, deck_err = client.request("deckNames")
    if not decks then
        return false, "Failed to fetch Anki decks: " .. tostring(deck_err)
    end
    local has_deck = false
    for _, d in ipairs(decks) do
        if d == deck_name then
            has_deck = true
            break
        end
    end
    if not has_deck then
        client.request("createDeck", { deck = deck_name })
    end
    return true
end

-- Main sync coordinator
function M.sync(filepath)
    -- If no filepath provided, use the current buffer
    if not filepath or filepath == "" then
        filepath = vim.api.nvim_buf_get_name(0)
    end

    if not filepath or filepath == "" then
        vim.notify("No valid file to sync.", vim.log.levels.WARN, { title = "Anki Sync" })
        return false
    end

    -- 1. Check connection to Anki
    local version, conn_err = client.request("version")
    if not version then
        vim.notify("Could not connect to Anki. Make sure Anki is running.\nError: " .. tostring(conn_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end

    -- 2. Resolve deck name from directory hierarchy
    local deck_name = resolve_deck_name(filepath)

    -- 3. Ensure deck exists
    local deck_ok, deck_err = ensure_deck(deck_name)
    if not deck_ok then
        vim.notify(deck_err, vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end

    -- 4. Ensure note model exists
    local model_ok, model_err = ensure_anki_model()
    if not model_ok then
        vim.notify(model_err, vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end

    -- 5. Parse the local file and inject UUIDs if needed
    local local_cards, parse_err = parser.parse_file(filepath)
    if not local_cards then
        vim.notify("Failed to parse file: " .. tostring(parse_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end

    if #local_cards == 0 then
        vim.notify("No cards (#card) found in file.", vim.log.levels.INFO, { title = "Anki Sync" })
        return true
    end

    -- Reload buffer if UUIDs were injected
    vim.cmd("checktime")

    -- 6. Fetch existing notes from Anki scoped to this deck and model
    local query = string.format("\"note:%s\" \"deck:%s\"", M.config.model, deck_name)
    local note_ids, find_err = client.find_notes(query)
    if not note_ids then
        vim.notify("Failed to find Anki notes: " .. tostring(find_err), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end

    local existing_anki_cards = {}
    if #note_ids > 0 then
        local notes, info_err = client.notes_info(note_ids)
        if not notes then
            vim.notify("Failed to get note info: " .. tostring(info_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end

        for _, note in ipairs(notes) do
            local uuid = note.fields.UUID and note.fields.UUID.value
            local config_val = note.fields.Config and note.fields.Config.value or ""
            local hash = config_val:match("hash:(%x+)")

            if uuid and uuid ~= "" then
                existing_anki_cards[uuid] = {
                    noteId = note.noteId,
                    hash = hash
                }
            end
        end
    end

    -- 7. Compare and build sync plan
    local to_create = {}
    local to_update = {}
    local to_keep = {}
    local local_uuids = {}

    for _, card in ipairs(local_cards) do
        local_uuids[card.uuid] = true
        local anki_card = existing_anki_cards[card.uuid]

        if not anki_card then
            table.insert(to_create, card)
        elseif anki_card.hash ~= card.hash then
            card.noteId = anki_card.noteId
            table.insert(to_update, card)
        else
            table.insert(to_keep, card)
        end
    end

    -- Notes to delete from Anki (exist in Anki but not in local file)
    local to_delete = {}
    for uuid, anki_card in pairs(existing_anki_cards) do
        if not local_uuids[uuid] then
            table.insert(to_delete, { noteId = anki_card.noteId, uuid = uuid })
        end
    end

    -- 8. Execute sync operations

    -- Create
    if #to_create > 0 then
        local new_notes = {}
        for _, card in ipairs(to_create) do
            table.insert(new_notes, {
                deckName = deck_name,
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
            vim.notify("Failed to create Anki notes: " .. tostring(create_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end
    end

    -- Update
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
                vim.notify("Failed to update note " .. tostring(card.noteId) .. ": " .. tostring(upd_err), vim.log.levels.ERROR, { title = "Anki Sync" })
                return false
            end
        end
    end

    -- Delete
    if #to_delete > 0 then
        local delete_ids = {}
        for _, card in ipairs(to_delete) do
            table.insert(delete_ids, card.noteId)
        end
        local ok, del_err = client.delete_notes(delete_ids)
        if not ok then
            vim.notify("Failed to delete Anki notes: " .. tostring(del_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end
    end

    -- 9. Notify the user
    local summary = string.format(
        "Anki Sync complete [%s]:\n- Created: %d\n- Updated: %d\n- Deleted: %d\n- Unchanged: %d",
        deck_name, #to_create, #to_update, #to_delete, #to_keep
    )
    vim.notify(summary, vim.log.levels.INFO, { title = "Anki Sync" })
    return true
end

-- Expose resolve_deck_name for testing
M._resolve_deck_name = resolve_deck_name

return M
