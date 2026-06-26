-- tests/neovim-sync-test.lua
-- Run via: nvim --headless -l tests/neovim-sync-test.lua

-- 1. Configure Lua path to include the plugin's lua/ directory
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local client = require("neovim-anki-sync.client")
local parser = require("neovim-anki-sync.parser")
local sync = require("neovim-anki-sync")

-- 2. Mock vim.notify to capture feedback messages
local last_notifications = {}
_G.vim.notify = function(msg, level, opts)
    table.insert(last_notifications, msg)
    print("[VIM NOTIFY] (" .. tostring(level) .. ") " .. msg)
end

-- 3. Detect if AnkiConnect is active
local has_real_anki = false
local ok, version = pcall(function()
    return client.request("version")
end)
if ok and version then
    has_real_anki = true
    print("AnkiConnect detected on port 8765. Running live integration tests.")
else
    print("AnkiConnect offline. Activating MOCK simulation layer for unit tests.")
end

-- 4. Mock AnkiConnect layer
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
            local query = params.query
            local ids = {}
            for id, note in pairs(mock_db.notes) do
                local match = false
                if query:match("UUID:") then
                    local uuid_val = note.fields.UUID.value
                    if uuid_val and uuid_val ~= "" and query:find(uuid_val, 1, true) then
                        match = true
                    end
                elseif query:match("path:") then
                    local path_pattern = query:match("path:(%x+)")
                    local config_val = note.fields.Config.value
                    if path_pattern and config_val and config_val:find("path:" .. path_pattern, 1, true) then
                        match = true
                    end
                else
                    if query:find("note:" .. note.modelName, 1, true) then
                        match = true
                    end
                end
                
                if match then
                    table.insert(ids, id)
                end
            end
            return ids
        elseif action == "notesInfo" then
            local result = {}
            for _, id in ipairs(params.notes) do
                local note = mock_db.notes[id]
                if note then
                    table.insert(result, {
                        noteId = id,
                        modelName = note.modelName,
                        fields = note.fields,
                        cards = note.cards
                    })
                end
            end
            return result
        elseif action == "cardsInfo" then
            local result = {}
            for _, cid in ipairs(params.cards) do
                for note_id, note in pairs(mock_db.notes) do
                    for _, note_cid in ipairs(note.cards) do
                        if note_cid == cid then
                            table.insert(result, {
                                cardId = cid,
                                deckName = note.deckName,
                                modelName = note.modelName,
                                fields = note.fields
                            })
                            break
                        end
                    end
                end
            end
            return result
        elseif action == "changeDeck" then
            for _, cid in ipairs(params.cards) do
                for note_id, note in pairs(mock_db.notes) do
                    for _, note_cid in ipairs(note.cards) do
                        if note_cid == cid then
                            note.deckName = params.deck
                            break
                        end
                    end
                end
            end
            return true
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
                    },
                    cards = { mock_id_counter + 10000 }
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
            return nil, "Note not found"
        elseif action == "deleteNotes" then
            for _, id in ipairs(params.notes) do
                mock_db.notes[id] = nil
            end
            return true
        end
        return nil, "Unmocked action: " .. tostring(action)
    end
end

-- 5. Test execution
local function run_tests()
    -- Use a temporary directory structure for testing
    local test_base = "tests/test_notes"
    local test_subdir = test_base .. "/Concursos/Estrategia/CFBM"
    local test_filepath = test_subdir .. "/cards.md"
    local flat_filepath = test_base .. "/root_cards.md"

    -- Clean up any previous test artifacts
    os.remove(test_filepath)
    os.remove(flat_filepath)
    os.execute("rm -rf " .. test_base)
    os.execute("mkdir -p " .. test_subdir)
    mock_db.notes = {}

    -- Initialize the plugin with notes_dir pointing to our test root
    local abs_test_base = vim.fn.fnamemodify(test_base, ":p")
    sync.setup({
        deck = "Default",
        model = "NeovimTestModel",
        notes_dir = abs_test_base
    })

    -- ---------------------------------------------------------------
    print("\n--- TEST 1: Hierarchical deck mapping from directory structure ---")
    -- ---------------------------------------------------------------

    -- Create card file inside subdirectory
    local f = io.open(test_filepath, "w")
    f:write([[
# CFBM Study Notes

- What is a public tender? #card
  A government-organized competitive exam for public positions.

- What is administrative law? #card
  The branch of law governing government agencies.
]])
    f:close()

    local ok1 = sync.sync(test_filepath)
    assert(ok1 == true, "Initial sync failed")

    -- Verify the notification mentions the hierarchical deck name
    local notification = last_notifications[#last_notifications]
    local expected_deck = "Concursos::Estrategia::CFBM"
    assert(notification:match(expected_deck), "Deck should be '" .. expected_deck .. "' but got: " .. notification)
    print("Hierarchical deck '" .. expected_deck .. "' correctly resolved!")

    -- Verify UUIDs were injected
    local parsed = parser.parse_file(test_filepath)
    assert(#parsed == 2, "Should have found 2 cards")
    assert(parsed[1].uuid ~= nil, "Card 1 should have a UUID")
    assert(parsed[2].uuid ~= nil, "Card 2 should have a UUID")
    print("UUIDs injected: " .. parsed[1].uuid .. ", " .. parsed[2].uuid)

    -- ---------------------------------------------------------------
    print("\n--- TEST 2: File at root of notes_dir uses fallback deck ---")
    -- ---------------------------------------------------------------

    local f2 = io.open(flat_filepath, "w")
    f2:write([[
- A root-level card #card
  This card has no subdirectory hierarchy.
]])
    f2:close()

    last_notifications = {}
    local ok2 = sync.sync(flat_filepath)
    assert(ok2 == true, "Root-level sync failed")
    notification = last_notifications[#last_notifications]
    assert(notification:match("Default"), "Root-level file should use fallback deck 'Default', got: " .. notification)
    print("Root-level file correctly mapped to fallback deck 'Default'!")

    -- ---------------------------------------------------------------
    print("\n--- TEST 3: Idempotent sync (no changes) ---")
    -- ---------------------------------------------------------------

    last_notifications = {}
    local ok3 = sync.sync(test_filepath)
    assert(ok3 == true)
    notification = last_notifications[#last_notifications]
    assert(notification:match("Unchanged: 2"), "Should have 2 unchanged cards, got: " .. notification)
    print("Idempotent sync verified!")

    -- ---------------------------------------------------------------
    print("\n--- TEST 4: Update a card ---")
    -- ---------------------------------------------------------------

    local lines = {}
    local f_lines = io.open(test_filepath, "r")
    for line in f_lines:lines() do
        if line:match("competitive exam for public positions") then
            line = "  A government selection process through competitive examination."
        end
        table.insert(lines, line)
    end
    f_lines:close()

    local f_write = io.open(test_filepath, "w")
    f_write:write(table.concat(lines, "\n") .. "\n")
    f_write:close()

    last_notifications = {}
    local ok4 = sync.sync(test_filepath)
    assert(ok4 == true)
    notification = last_notifications[#last_notifications]
    assert(notification:match("Updated: 1"), "Should have updated 1 card, got: " .. notification)
    assert(notification:match("Unchanged: 1"), "Should have 1 unchanged card, got: " .. notification)
    print("Card update verified!")

    -- ---------------------------------------------------------------
    print("\n--- TEST 5: Delete a card ---")
    -- ---------------------------------------------------------------

    local clean_lines = {}
    local skip_mode = false
    local f_del = io.open(test_filepath, "r")
    for line in f_del:lines() do
        if line:match("administrative law") then
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
    local ok5 = sync.sync(test_filepath)
    assert(ok5 == true)
    notification = last_notifications[#last_notifications]
    assert(notification:match("Deleted: 1"), "Should have deleted 1 card, got: " .. notification)
    assert(notification:match("Unchanged: 1"), "Should have 1 unchanged card, got: " .. notification)
    print("Card deletion verified!")

    -- ---------------------------------------------------------------
    print("\n--- TEST 6: Move cards/file to a different subdirectory/deck ---")
    -- ---------------------------------------------------------------

    local new_subdir = test_base .. "/Concursos/OutroDecker"
    local new_filepath = new_subdir .. "/cards.md"
    os.execute("mkdir -p " .. new_subdir)
    
    -- Rename/move the file to the new directory
    os.rename(test_filepath, new_filepath)
    
    -- Read the UUID of the remaining card in the moved file
    local moved_parsed = parser.parse_file(new_filepath)
    assert(#moved_parsed == 1, "Should have 1 card in moved file")
    local moved_uuid = moved_parsed[1].uuid

    last_notifications = {}
    local ok6 = sync.sync(new_filepath)
    assert(ok6 == true, "Sync after moving file failed")
    
    notification = last_notifications[#last_notifications]
    local expected_new_deck = "Concursos::OutroDecker"
    assert(notification:match(expected_new_deck), "Deck should be '" .. expected_new_deck .. "' but got: " .. notification)
    
    -- Verify in mock_db that the card's deck name was updated and config path was updated
    local found_note = nil
    local note_count = 0
    for _, note in pairs(mock_db.notes) do
        if note.fields.UUID.value == moved_uuid then
            found_note = note
            note_count = note_count + 1
        end
    end
    assert(found_note ~= nil, "Note not found in mock DB")
    assert(note_count == 1, "Expected exactly 1 note in mock DB for this UUID, found: " .. tostring(note_count))
    assert(found_note.deckName == "Concursos::OutroDecker", "Mock note deck name not updated, got: " .. tostring(found_note.deckName))
    assert(found_note.fields.Config.value:match("path:"), "Mock note path config not updated")
    print("Move file and hierarchical deck update verified successfully!")

    -- Clean up test artifacts
    os.execute("rm -rf " .. test_base)

    print("\n==================================================")
    print("             ALL TESTS PASSED!                    ")
    print("==================================================")
end

local success, err = pcall(run_tests)
if not success then
    print("\n[TEST ERROR]: " .. tostring(err))
    -- Clean up on failure too
    os.execute("rm -rf tests/test_notes")
    os.exit(1)
else
    os.exit(0)
end
