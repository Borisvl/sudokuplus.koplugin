package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path
local test_guard = require("sudoku_frontend_test_guard")
test_guard.install()

local PLUGIN_ROOT = "plugins/sudokuplus.koplugin"

local function with_loaded(entries, callback)
    local previous = {}
    for _, entry in ipairs(entries) do
        local name = entry[1]
        previous[#previous + 1] = {
            name = name,
            present = package.loaded[name] ~= nil,
            value = package.loaded[name],
        }
        package.loaded[name] = entry[2]
    end

    local ok, err = pcall(callback)
    for _, entry in ipairs(previous) do
        if entry.present then
            package.loaded[entry.name] = entry.value
        else
            package.loaded[entry.name] = nil
        end
    end
    assert.is_true(ok, tostring(err))
end

describe("Sudoku+ module namespace", function()
    setup(function()
        require("commonrequire")
    end)

    it("does not consume a KOReader-shaped json module", function()
        local koreader_json = {
            decode = {
                simple = function()
                    return "koreader-json"
                end,
            },
        }
        with_loaded({
            { "json", koreader_json },
            { "sudokuplus.json", nil },
            { "sudokuplus.storage", nil },
        }, function()
            local plugin_storage = require("sudokuplus.storage")
            assert.is_table(plugin_storage)
            assert.are.equal(koreader_json, package.loaded.json)
            assert.are.equal("koreader-json", require("json").decode.simple())
            assert.is_table(package.loaded["sudokuplus.json"])
        end)
    end)

    it("does not register its private codec as global json", function()
        local koreader_json = { id = "koreader-json" }
        with_loaded({
            { "json", nil },
            { "sudokuplus.json", nil },
        }, function()
            local plugin_json = require("sudokuplus.json")
            assert.is_table(plugin_json)
            assert.is_nil(package.loaded.json)

            package.loaded.json = koreader_json
            assert.are.equal(koreader_json, require("json"))
            assert.are_not.equal(koreader_json, plugin_json)
        end)
    end)

    it("leaves unrelated generic plugin module ids untouched", function()
        local sentinel = { id = "unrelated-module", version = "foreign-version" }
        local generic_ids = {
            "_meta",
            "game",
            "game_serialize",
            "stats",
            "storage",
            "core.board",
            "core.generator",
            "core.solver",
            "ui.dialogs",
            "ui.help",
            "ui.statsview",
            "ui.sudokuview",
        }
        local entries = {}
        for _, name in ipairs(generic_ids) do
            entries[#entries + 1] = { name, sentinel }
        end
        for _, name in ipairs({
            "sudokuplus.game",
            "sudokuplus.stats",
            "sudokuplus.storage",
            "sudokuplus.core.generator",
            "sudokuplus.ui.help",
            "sudokuplus.ui.sudokuview",
        }) do
            entries[#entries + 1] = { name, nil }
        end

        with_loaded(entries, function()
            local plugin = dofile(PLUGIN_ROOT .. "/main.lua")
            assert.is_table(plugin)
            for _, name in ipairs(generic_ids) do
                assert.are.equal(sentinel, package.loaded[name], name)
            end
            assert.is_table(package.loaded["sudokuplus.game"])
            assert.is_table(package.loaded["sudokuplus.stats"])
            assert.is_table(package.loaded["sudokuplus.storage"])
            assert.is_table(package.loaded["sudokuplus.core.generator"])
            assert.is_table(package.loaded["sudokuplus.ui.help"])
            assert.is_table(package.loaded["sudokuplus.ui.sudokuview"])
        end)
    end)

    it("gets About version data without requiring generic _meta", function()
        local foreign_meta = { version = "foreign-version" }
        with_loaded({
            { "_meta", foreign_meta },
            { "sudokuplus.metadata", nil },
            { "sudokuplus.ui.help", nil },
        }, function()
            local help = require("sudokuplus.ui.help")
            local metadata = require("sudokuplus.metadata")
            local about = help.get_text("about")
            assert.is_not_nil(about:find(metadata.version, 1, true))
            assert.is_nil(about:find(foreign_meta.version, 1, true))
            assert.are.equal(foreign_meta, package.loaded._meta)
        end)
    end)
end)
