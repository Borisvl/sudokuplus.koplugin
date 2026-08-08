package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku plugin menu", function()
    local Sudoku
    local menu_items

    local function toggle_item()
        for _, item in ipairs(menu_items.sudoku.sub_item_table) do
            if item.text == "Auto-fill notes" then
                return item
            end
        end
        error("no Auto-fill notes item")
    end

    setup(function()
        require("commonrequire")
        Sudoku = require("main")
        menu_items = {}
        Sudoku:addToMainMenu(menu_items)
    end)

    it("registers a Sudoku submenu with a new-game entry and the notes toggle", function()
        assert.is_not_nil(menu_items.sudoku)
        assert.is_table(menu_items.sudoku.sub_item_table)
        local texts = {}
        for _, item in ipairs(menu_items.sudoku.sub_item_table) do
            texts[#texts + 1] = item.text
        end
        assert.are.same({ "New game", "Auto-fill notes" }, texts)
    end)

    it("renders the submenu without crashing (checked_func evaluated)", function()
        local Device = require("device")
        local TouchMenu = require("ui/widget/touchmenu")
        local menu = TouchMenu:new {
            width = Device.screen:getWidth(),
            tab_item_table = {
                {
                    icon = "resources/icons/mdlight/appbar.tools.svg",
                    text = "Tools",
                    sub_item_table = menu_items.sudoku.sub_item_table,
                },
            },
        }
        menu.item_table = menu_items.sudoku.sub_item_table
        menu:updateItems(1)
        assert.is_not_nil(menu)
    end)

    it("flips the auto-fill notes setting through the toggle", function()
        G_reader_settings:saveSetting("sudoku_autofill_notes", false)
        local toggle = toggle_item()
        assert.is_false(toggle.checked_func())
        toggle.callback()
        assert.is_true(G_reader_settings:isTrue("sudoku_autofill_notes"))
        toggle.callback()
        assert.is_false(G_reader_settings:isTrue("sudoku_autofill_notes"))
    end)
end)
