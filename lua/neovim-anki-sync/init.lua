local client = require("neovim-anki-sync.client")
local parser = require("neovim-anki-sync.parser")

local M = {}

-- Default configuration
M.config = {
    deck = "Default",            -- Fallback deck when file is outside notes_dir
    model = "NeovimAnkiCard-Cloze-v2",    -- Note type name in Anki (changed to support v2 layout with breadcrumbs)
    anki_url = "http://127.0.0.1:8765",
    notes_dir = nil              -- Root directory for hierarchical deck mapping (optional)
}

-- Configure the plugin with user options
function M.setup(opts)
    opts = opts or {}
    M.config = vim.tbl_deep_extend("force", M.config, opts)
    client.anki_url = M.config.anki_url
end

-- Helper functions to hex encode/decode strings
local function hex_encode(str)
    return (str:gsub('.', function (c)
        return string.format('%02x', string.byte(c))
    end))
end

local function hex_decode(str)
    return (str:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

--- Resolve notes_dir and relative file paths.
--- If M.config.notes_dir is not configured, it tries to detect the git root,
--- falling back to the current working directory of Neovim.
local function get_notes_dir_and_relative(filepath)
    filepath = vim.fn.resolve(vim.fn.fnamemodify(filepath, ":p"))
    
    local notes_dir = M.config.notes_dir
    if not notes_dir or notes_dir == "" then
        local git_dir = vim.fs.find(".git", { path = filepath, upward = true })[1]
        if git_dir then
            notes_dir = vim.fs.dirname(git_dir)
        else
            notes_dir = vim.fn.getcwd()
        end
    end
    
    notes_dir = vim.fn.resolve(vim.fn.fnamemodify(notes_dir, ":p"))
    if not notes_dir:match("/$") then
        notes_dir = notes_dir .. "/"
    end
    
    local file_dir = vim.fn.fnamemodify(filepath, ":p:h")
    if not file_dir:match("/$") then
        file_dir = file_dir .. "/"
    end
    
    local relative_dir = ""
    if file_dir:sub(1, #notes_dir) == notes_dir then
        relative_dir = file_dir:sub(#notes_dir + 1)
        relative_dir = relative_dir:gsub("/$", "")
    end
    
    local filename = vim.fn.fnamemodify(filepath, ":t")
    local relative_file
    if relative_dir == "" then
        relative_file = filename
    else
        relative_file = relative_dir .. "/" .. filename
    end
    
    return notes_dir, relative_dir, relative_file
end

--- Resolve the Anki deck name from relative_dir and filename.
local function resolve_deck_name(relative_dir, filename)
    local base_deck = ""
    if relative_dir == "" then
        base_deck = M.config.deck
    else
        base_deck = (relative_dir:gsub("/", "::"))
    end
    
    local name_without_ext = vim.fn.fnamemodify(filename, ":r")
    if base_deck == "" then
        return name_without_ext
    else
        return base_deck .. "::" .. name_without_ext
    end
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
            inOrderFields = { "Text", "Back", "Breadcrumb", "UUID", "Config" },
            isCloze = true,
            css = [[
.card {
 font-family: arial;
 font-size: 20px;
 text-align: left;
 color: black;
 background-color: white;
}
.bubble {
 font-family: arial;
 font-size: 12px;
 color: rgb(65, 65, 65);
 background-color: rgb(226, 236, 240);
 border-radius: 6px;
 padding: 2px 6px;
 margin-bottom: 4px;
 display: inline-block;
}
.bubble:empty {
 display: none;
}
.text {
 font-family: arial;
 font-size: 16px;
 color: black;
 margin-top: 10px;
}
.cloze {
 font-weight: bold;
 color: blue;
}
body.nightMode {
 background-color: #2c2c2c;
 color: #fcfcfc;
}
body.nightMode .card {
 color: #fcfcfc;
 background-color: #2c2c2c;
}
body.nightMode .text {
 color: #bfbfbf;
}
body.nightMode .cloze {
 color: lightblue;
}
body.nightMode .bubble {
 color: #bfbfbf;
 background-color: #4d4d4d;
}
]],
            cardTemplates = {
                {
                    Name = "Card 1",
                    Front = [[{{#Breadcrumb}}<div class="bubble">{{Breadcrumb}}</div><br/>{{/Breadcrumb}}
<div class="text">{{cloze:Text}}</div>]],
                    Back = [[{{#Breadcrumb}}<div class="bubble">{{Breadcrumb}}</div><br/>{{/Breadcrumb}}
<div class="text">{{cloze:Text}}</div>

{{#Back}}
<hr id="answer">
<div class="text">{{Back}}</div>
{{/Back}}]]
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
    -- createDeck is safe and idempotent in AnkiConnect
    local ok, err = client.request("createDeck", { deck = deck_name })
    if not ok then
        return false, "Failed to create deck: " .. tostring(err)
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

    -- 2. Resolve paths and deck name
    local notes_dir, relative_dir, relative_file = get_notes_dir_and_relative(filepath)
    local filename = vim.fn.fnamemodify(filepath, ":t")
    local deck_name = resolve_deck_name(relative_dir, filename)

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

    -- 6. Fetch existing notes from Anki for this file or UUIDs
    local hex_path = hex_encode(relative_file)
    
    -- Query A: Notes synced to this file path
    local query_file = string.format("\"note:%s\" \"Config:*path:%s*\"", M.config.model, hex_path)
    local file_note_ids, err_file = client.find_notes(query_file)
    if not file_note_ids then
        vim.notify("Failed to find file notes: " .. tostring(err_file), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    
    -- Query B: Notes matching current local UUIDs
    local uuids = {}
    for _, card in ipairs(local_cards) do
        table.insert(uuids, string.format("\"UUID:%s\"", card.uuid))
    end
    local query_uuids = string.format("\"note:%s\" (%s)", M.config.model, table.concat(uuids, " OR "))
    local uuid_note_ids, err_uuids = client.find_notes(query_uuids)
    if not uuid_note_ids then
        vim.notify("Failed to find UUID notes: " .. tostring(err_uuids), vim.log.levels.ERROR, { title = "Anki Sync" })
        return false
    end
    
    -- Merge note IDs from both queries
    local all_note_ids_set = {}
    local all_note_ids = {}
    for _, id in ipairs(file_note_ids) do
        if not all_note_ids_set[id] then
            all_note_ids_set[id] = true
            table.insert(all_note_ids, id)
        end
    end
    for _, id in ipairs(uuid_note_ids) do
        if not all_note_ids_set[id] then
            all_note_ids_set[id] = true
            table.insert(all_note_ids, id)
        end
    end

    local existing_notes_by_uuid = {}
    if #all_note_ids > 0 then
        local notes, info_err = client.notes_info(all_note_ids)
        if not notes then
            vim.notify("Failed to get note info: " .. tostring(info_err), vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end

        -- Fetch card info to get the deck name of each note's cards
        local card_ids = {}
        for _, note in ipairs(notes) do
            if note.cards then
                for _, cid in ipairs(note.cards) do
                    table.insert(card_ids, cid)
                end
            end
        end

        local card_decks = {}
        if #card_ids > 0 then
            local cards_info, err_cards = client.request("cardsInfo", { cards = card_ids })
            if not cards_info then
                vim.notify("Failed to get cards info: " .. tostring(err_cards), vim.log.levels.ERROR, { title = "Anki Sync" })
                return false
            end
            for _, card in ipairs(cards_info) do
                card_decks[card.cardId] = card.deckName
            end
        end

        for _, note in ipairs(notes) do
            local uuid = note.fields.UUID and note.fields.UUID.value
            local config_val = note.fields.Config and note.fields.Config.value or ""
            local hash = config_val:match("hash:(%x+)")
            local path = config_val:match("path:(%x+)")
            if path then
                path = hex_decode(path)
            end

            local current_deck = nil
            if note.cards and #note.cards > 0 then
                current_deck = card_decks[note.cards[1]]
            end

            if uuid and uuid ~= "" then
                existing_notes_by_uuid[uuid] = {
                    noteId = note.noteId,
                    cardIds = note.cards,
                    hash = hash,
                    path = path,
                    deckName = current_deck,
                    tags = note.tags or {}
                }
            end
        end
    end

    -- 7. Compare and build sync plan
    local to_create = {}
    local to_update = {}
    local to_keep = {}
    local local_uuids = {}

    local default_deck_name = deck_name
    for _, card in ipairs(local_cards) do
        local_uuids[card.uuid] = true
        local anki_note = existing_notes_by_uuid[card.uuid]
        
        -- Context (Breadcrumbs & Parent Bullets)
        -- Build breadcrumbs from relative directory and filename, then append card headers
        local full_breadcrumbs = {}
        if relative_dir ~= "" then
            for segment in string.gmatch(relative_dir, "[^/]+") do
                table.insert(full_breadcrumbs, segment)
            end
        end
        table.insert(full_breadcrumbs, vim.fn.fnamemodify(filename, ":r"))
        
        if card.breadcrumbs then
            for _, b in ipairs(card.breadcrumbs) do
                table.insert(full_breadcrumbs, b)
            end
        end
        
        local breadcrumbs_str = ""
        if #full_breadcrumbs > 0 then
            breadcrumbs_str = table.concat(full_breadcrumbs, " &gt; ")
        end
        card.breadcrumbs_html = breadcrumbs_str
        
        -- Render parent bullets (Markdown style hierarchy)
        local bullets_html = ""
        if card.parent_bullets and #card.parent_bullets > 0 then
            for _, bullet in ipairs(card.parent_bullets) do
                bullets_html = bullets_html .. "<ul><li>" .. bullet
            end
            
            -- Close the bullet tags around the front text
            bullets_html = bullets_html .. "<ul><li>" .. card.front .. "</li></ul>"
            
            for i = 1, #card.parent_bullets do
                bullets_html = bullets_html .. "</li></ul>"
            end
        else
            bullets_html = "<ul><li>" .. card.front .. "</li></ul>"
        end
        card.final_front = bullets_html
        
        -- Tags
        local tags = { "neovim-sync" }
        local tag_set = { ["neovim-sync"] = true }
        local function add_tag(t)
            if t and not tag_set[t] then
                tag_set[t] = true
                table.insert(tags, t)
            end
        end
        for _, t in ipairs(card.inline_tags or {}) do add_tag(t) end
        local function parse_tags(tag_str)
            if not tag_str then return end
            for t in tag_str:gmatch("[^,%s]+") do add_tag(t) end
        end
        parse_tags(card.properties.tags)
        parse_tags(card.global_properties.tags)
        card.tags = tags
        
        -- Deck override
        local explicit_deck = card.properties.deck or card.global_properties.deck
        if explicit_deck and explicit_deck ~= "" then
            card.target_deck = explicit_deck:gsub("/", "::")
        else
            card.target_deck = default_deck_name
        end

        if not anki_note then
            table.insert(to_create, card)
        else
            card.noteId = anki_note.noteId
            card.cardIds = anki_note.cardIds

            local deck_changed = anki_note.deckName ~= card.target_deck
            local path_changed = anki_note.path ~= relative_file
            local hash_changed = anki_note.hash ~= card.hash

            if deck_changed or path_changed or hash_changed then
                card.deck_changed = deck_changed
                card.path_changed = path_changed
                card.hash_changed = hash_changed
                table.insert(to_update, card)
            else
                table.insert(to_keep, card)
            end
        end
    end

    -- Notes to delete (belonged to this file path, but no longer exist locally)
    local to_delete = {}
    for uuid, anki_note in pairs(existing_notes_by_uuid) do
        if anki_note.path == relative_file and not local_uuids[uuid] then
            table.insert(to_delete, anki_note.noteId)
        end
    end

    -- 8. Execute sync operations

    -- Create
    if #to_create > 0 then
        local new_notes = {}
        for _, card in ipairs(to_create) do
            table.insert(new_notes, {
                deckName = card.target_deck,
                modelName = M.config.model,
                fields = {
                    Text = card.final_front,
                    Back = card.back,
                    Breadcrumb = card.breadcrumbs_html,
                    UUID = card.uuid,
                    Config = string.format("hash:%s path:%s", card.hash, hex_path)
                },
                options = { allowDuplicate = true },
                tags = card.tags
            })
        end
        local create_res, create_err = client.add_notes(new_notes)
        if not create_res then
            local hint = ""
            if tostring(create_err):match("cannot create note for unknown reason") then
                hint = "\n\nHINT: This error usually means you are trying to sync Cloze cards (or multiline cards which use clozes under the hood) to a Basic note type (like '" .. M.config.model .. "').\nTo fix this:\n1. Restart Neovim to load the new default model 'NeovimAnkiCard-Cloze-v2'.\n2. If you overrode the model name in your config, update it or remove the override.\n3. Alternatively, manually change the Note Type of '" .. M.config.model .. "' to 'Cloze' inside Anki (Tools > Manage Note Types > select model > Change Note Type > select Cloze)."
            end
            vim.notify("Failed to create Anki notes: " .. tostring(create_err) .. hint, vim.log.levels.ERROR, { title = "Anki Sync" })
            return false
        end
    end

    -- Update (including changing deck/path)
    if #to_update > 0 then
        for _, card in ipairs(to_update) do
            -- A. Move deck if changed
            if card.deck_changed and card.cardIds and #card.cardIds > 0 then
                local ok, move_err = client.request("changeDeck", {
                    cards = card.cardIds,
                    deck = card.target_deck
                })
                if not ok then
                    vim.notify("Failed to move note " .. tostring(card.noteId) .. " to deck " .. deck_name .. ": " .. tostring(move_err), vim.log.levels.ERROR, { title = "Anki Sync" })
                    return false
                end
            end

            -- B. Update fields and Config
            local ok, upd_err = client.update_note_fields({
                id = card.noteId,
                fields = {
                    Text = card.final_front,
                    Back = card.back,
                    Breadcrumb = card.breadcrumbs_html,
                    UUID = card.uuid,
                    Config = string.format("hash:%s path:%s", card.hash, hex_path)
                }
            })
            if not ok then
                vim.notify("Failed to update note " .. tostring(card.noteId) .. ": " .. tostring(upd_err), vim.log.levels.ERROR, { title = "Anki Sync" })
                return false
            end
            
            if card.tags and #card.tags > 0 then
                client.request("addTags", { notes = {card.noteId}, tags = table.concat(card.tags, " ") })
            end
        end
    end

    -- Delete
    if #to_delete > 0 then
        local ok, del_err = client.delete_notes(to_delete)
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

-- Expose helpers for testing
M._get_notes_dir_and_relative = get_notes_dir_and_relative
M._resolve_deck_name = resolve_deck_name

return M
