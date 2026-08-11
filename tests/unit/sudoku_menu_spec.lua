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
            for _, sub in ipairs(item.sub_item_table or {}) do
                if sub.text == text then
                    return sub
                end
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

    it("registers a Sudoku submenu with continue, new-game, statistics and the notes toggle", function()
        assert.is_not_nil(menu_items.sudoku)
        assert.is_table(menu_items.sudoku.sub_item_table)
        local texts = {}
        for _, item in ipairs(menu_items.sudoku.sub_item_table) do
            texts[#texts + 1] = item.text
        end
        assert.are.same({ "Continue", "New game", "Statistics", "Auto-fill notes" }, texts)
    end)

    it("offers all four difficulties under New game", function()
        local new_game = item_with("New game")
        assert.is_table(new_game.sub_item_table)
        local labels = {}
        for _, entry in ipairs(new_game.sub_item_table) do
            labels[#labels + 1] = entry.text
        end
        assert.are.same({ "Easy", "Medium", "Hard", "Expert" }, labels)
    end)

    it("starts a game of the chosen difficulty", function()
        local board = require("core.board")
        local generator = require("core.generator")
        local original_generate = generator.generate_game
        generator.generate_game = function(opts)
            assert.are.equal("expert", opts.difficulty)
            return {
                board = board.from_string(
                    "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
                ),
                solution = board.from_string(
                    "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
                ),
                difficulty = "expert",
                clues = 30,
            }
        end
        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
        end
        item_with("Expert").callback()
        UIManager.show = original_show
        generator.generate_game = original_generate
        assert.is_not_nil(shown, "New game must show the game view")
        assert.are.equal("expert", shown.game:difficulty())
    end)

    it("shows the statistics view from the menu", function()
        local shown
        local refreshtype
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget, mode)
            shown = widget
            refreshtype = mode
        end
        item_with("Statistics").callback()
        UIManager.show = original_show
        assert.is_not_nil(shown)
        assert.is_not_nil(shown.item_table, "the stats dashboard is a menu")
        assert.are.equal("Sudoku statistics", shown.title)
        assert.are.equal("full", refreshtype, "the stats page must refresh the whole screen")
    end)

    it("keeps the menu open when showing statistics", function()
        local stats_item = item_with("Statistics")
        assert.is_true(stats_item.keep_menu_open, "closing the stats page must return to the menu")
    end)

    it("enables Continue only when a save exists", function()
        local continue = item_with("Continue")
        assert.is_false(continue.enabled_func())
        local file = io.open(save_path, "wb")
        assert.is_not_nil(file)
        file:write("{}")
        file:close()
        assert.is_true(continue.enabled_func())
    end)

    it("continues the saved game from the menu item", function()
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
        item_with("Continue").callback()
        UIManager.show = original_show

        assert.is_not_nil(shown, "Continue must show the game view")
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

    it("seeds the puzzle PRNG from the wall clock at millisecond resolution", function()
        local board = require("core.board")
        local generator = require("core.generator")
        local time = require("ui/time")
        local original_generate = generator.generate_game
        local original_realtime = time.realtime
        local captured
        generator.generate_game = function(opts)
            captured = opts.rng
            return {
                board = board.from_string(
                    "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
                ),
                solution = board.from_string(
                    "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
                ),
                difficulty = "easy",
                clues = 30,
            }
        end
        -- 1234.567s after the epoch -> epoch ms 1234567 -> masked 32-bit state.
        time.realtime = function()
            return time.s(1234) + time.ms(567)
        end
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function() end
        Sudoku:startGame()
        UIManager.show = original_show
        generator.generate_game = original_generate
        time.realtime = original_realtime

        assert.is_not_nil(captured, "generation must receive a seeded rng")
        assert.are.equal(1234567, captured.state, "seed must be wall-clock milliseconds, masked to 32 bits")
    end)

    it("shows a generating notification before generating and closes it after", function()
        local generator = require("core.generator")
        local original_generate = generator.generate_game
        generator.generate_game = function(opts)
            assert.are.equal("hard", opts.difficulty)
            return nil, "forced generation failure"
        end
        local UIManager = require("ui/uimanager")
        local shown = {}
        local closed = {}
        local repainted = false
        local original_show = UIManager.show
        local original_close = UIManager.close
        local original_repaint = UIManager.forceRePaint
        UIManager.show = function(_, widget)
            shown[#shown + 1] = widget
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        UIManager.forceRePaint = function()
            repainted = true
        end
        item_with("Hard").callback()
        UIManager.show = original_show
        UIManager.close = original_close
        UIManager.forceRePaint = original_repaint
        generator.generate_game = original_generate

        assert.is_not_nil(shown[1], "a notification must be shown before generation")
        assert.are.equal("Generating…", shown[1].text)
        assert.is_true(repainted, "the notification must be painted before the blocking generation")
        assert.is_not_nil(shown[2], "the failure must surface an error dialog")
        assert.are.equal(shown[1], closed[1], "the notification must be dismissed after generation")
    end)

    it("keeps the saved game when generating a new one fails", function()
        local generator = require("core.generator")
        local original_generate = generator.generate_game
        generator.generate_game = function()
            return nil, "forced generation failure"
        end
        local file = io.open(save_path, "wb")
        file:write("{}")
        file:close()

        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function() end
        Sudoku:startGame()
        UIManager.show = original_show
        generator.generate_game = original_generate

        assert.is_not_nil(io.open(save_path, "rb"), "the abandoned save must survive a failed generation")
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
