package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku plugin menu", function()
    local DataStorage
    local Sudoku
    local game
    local menu_items
    local storage
    local save_path

    local function item_with(text)
        for _, item in ipairs(menu_items.sudoku.sub_item_table) do
            if item.text == text then
                return item
            end
        end
        error("no menu item " .. text)
    end

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        game = require("game")
        storage = require("storage")
        Sudoku = require("main")
        menu_items = {}
        Sudoku:addToMainMenu(menu_items)
        save_path = DataStorage:getDataDir() .. "/sudoku_save"
        os.remove(save_path)
    end)

    after_each(function()
        os.remove(save_path)
    end)

    it("registers a Sudoku submenu with resume, new-game and notes toggle", function()
        assert.is_not_nil(menu_items.sudoku)
        assert.is_table(menu_items.sudoku.sub_item_table)
        local texts = {}
        for _, item in ipairs(menu_items.sudoku.sub_item_table) do
            texts[#texts + 1] = item.text
        end
        assert.are.same({ "Resume game", "New game", "Auto-fill notes" }, texts)
    end)

    it("enables Resume game only when a save exists", function()
        local resume = item_with("Resume game")
        assert.is_false(resume.enabled_func())
        local file = io.open(save_path, "wb")
        assert.is_not_nil(file)
        file:write("{}")
        file:close()
        assert.is_true(resume.enabled_func())
    end)

    it("resumes the saved game from the menu item", function()
        local board = require("core.board")
        local clock = { t = 1000 }
        local g = assert(game.new {
            puzzle = board.from_string(
                "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
            ),
            solution = board.from_string(
                "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
            ),
            difficulty = "easy",
            now = function()
                return clock.t
            end,
        })
        assert.is_true(g:place(0, 2, 2))
        g:pause()
        assert.is_true(storage.save(save_path, g:serialize()))

        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
        end
        item_with("Resume game").callback()
        UIManager.show = original_show

        assert.is_not_nil(shown, "Resume game must show the game view")
        assert.are.equal(2, shown.game:get(0, 2))
        assert.is_true(shown.game.timer.running, "resumed game must start its timer")
    end)

    it("starts a new game with a wall-clock timer", function()
        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
        end
        Sudoku:startGame()
        UIManager.show = original_show
        assert.is_not_nil(shown, "New game must show the game view")
        local t = shown.game.now()
        assert.is_true(t >= os.time() - 2 and t <= os.time() + 2, "timer must use wall-clock seconds")
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
        local toggle = item_with("Auto-fill notes")
        assert.is_false(toggle.checked_func())
        toggle.callback()
        assert.is_true(G_reader_settings:isTrue("sudoku_autofill_notes"))
        toggle.callback()
        assert.is_false(G_reader_settings:isTrue("sudoku_autofill_notes"))
    end)
end)
