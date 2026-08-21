package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path
local test_guard = require("sudoku_frontend_test_guard")
test_guard.install()

describe("sudoku plugin menu", function()
    local DataStorage
    local Sudoku
    local game
    local menu_items
    local storage
    local save_path

    local function item_with(text)
        for _, item in ipairs(menu_items.sudokuplus.sub_item_table) do
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

    local created_baks = {}
    local function track_bak(text)
        if type(text) == "string" then
            local bak = text:match("(%S+%.bak)")
            if bak then
                created_baks[#created_baks + 1] = bak
            end
        end
    end

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        game = require("game")
        storage = require("storage")
        Sudoku = require("main")
        menu_items = {}
        Sudoku:addToMainMenu(menu_items)
        save_path = DataStorage:getDataDir() .. "/sudokuplus_save"
        os.remove(save_path)
    end)

    after_each(function()
        os.remove(save_path)
        for _, p in ipairs(created_baks) do
            os.remove(p)
        end
        created_baks = {}
    end)

    it("registers a Sudoku+ submenu with continue, new-game, statistics, help, and the notes toggle", function()
        assert.is_not_nil(menu_items.sudokuplus)
        assert.is_table(menu_items.sudokuplus.sub_item_table)
        local texts = {}
        for _, item in ipairs(menu_items.sudokuplus.sub_item_table) do
            texts[#texts + 1] = item.text
        end
        assert.are.same({ "Continue", "New game", "Statistics", "Help", "Auto-fill notes" }, texts)
    end)

    it("runs inside the guarded per-spec KO_HOME", function()
        assert.are.equal(os.getenv("KO_HOME"), DataStorage:getDataDir())
        assert.is_true(test_guard.is_installed())
        local sentinel = os.getenv("SUDOKU_TEST_SENTINEL_ROOT")
        assert.is_string(sentinel)
        local protected_path = sentinel .. "/sudokuplus_save"
        local attempts = {
            {
                "os.remove",
                function()
                    os.remove(protected_path)
                end,
            },
            {
                "io.input",
                function()
                    io.input(protected_path)
                end,
            },
            {
                "io.output",
                function()
                    io.output(protected_path)
                end,
            },
            {
                "io.lines",
                function()
                    io.lines(protected_path)
                end,
            },
            {
                "loadfile",
                function()
                    loadfile(protected_path)
                end,
            },
            {
                "dofile",
                function()
                    dofile(protected_path)
                end,
            },
            {
                "os.execute",
                function()
                    os.execute("test -f " .. protected_path)
                end,
            },
            {
                "io.popen",
                function()
                    io.popen("test -f " .. protected_path)
                end,
            },
        }
        for _, attempt in ipairs(attempts) do
            local ok = pcall(attempt[2])
            assert.is_false(ok, attempt[1] .. " must reject protected data")
        end
    end)

    it("opens help menu via Help item", function()
        local help_item = item_with("Help")
        assert.is_not_nil(help_item)
        assert.is_true(help_item.keep_menu_open)
        local shown_widget
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown_widget = widget
        end
        finally(function()
            UIManager.show = original_show
        end)
        help_item.callback()
        assert.is_not_nil(shown_widget)
    end)

    it("offers all six difficulties and custom option under New game", function()
        local new_game = item_with("New game")
        assert.is_table(new_game.sub_item_table)
        local labels = {}
        for _, entry in ipairs(new_game.sub_item_table) do
            labels[#labels + 1] = entry.text
        end
        assert.are.same({ "Beginner", "Easy", "Medium", "Hard", "Master", "Expert", "Custom…" }, labels)
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

    it("backs up corrupt JSON save on continue, shows info and disables continue (B2)", function()
        local file = io.open(save_path, "wb")
        file:write('{"version": corrupt_json')
        file:close()

        local continue = item_with("Continue")
        assert.is_true(continue.enabled_func())

        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
            track_bak(widget and widget.text)
        end
        continue.callback()
        UIManager.show = original_show

        assert.is_not_nil(shown)
        assert.is_true(string.find(shown.text, "corrupted") ~= nil)
        assert.is_false(storage.exists(save_path), "corrupted save must be moved")
        assert.is_false(continue.enabled_func(), "continue must now be disabled")
    end)

    it("backs up semantically invalid save on continue, shows info and disables continue (B2)", function()
        local file = io.open(save_path, "wb")
        file:write('{"version": 3, "board": "invalid_length"}')
        file:close()

        local continue = item_with("Continue")
        assert.is_true(continue.enabled_func())

        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
            track_bak(widget and widget.text)
        end
        continue.callback()
        UIManager.show = original_show

        assert.is_not_nil(shown)
        assert.is_true(string.find(shown.text, "corrupted") ~= nil)
        assert.is_true(string.find(shown.text, "invalid difficulty") ~= nil)
        assert.is_false(storage.exists(save_path), "invalid save must be moved")
        assert.is_false(continue.enabled_func(), "continue must now be disabled")
    end)

    it("backs up future unsupported version save on continue and reports version error", function()
        local file = io.open(save_path, "wb")
        file:write('{"version": 99, "board": "530070000"}')
        file:close()

        local continue = item_with("Continue")
        assert.is_true(continue.enabled_func())

        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
            track_bak(widget and widget.text)
        end
        continue.callback()
        UIManager.show = original_show

        assert.is_not_nil(shown)
        assert.is_true(string.find(shown.text, "corrupted") ~= nil)
        assert.is_true(string.find(shown.text, "unsupported save version: 99") ~= nil)
        assert.is_false(storage.exists(save_path), "future version save must be moved")
        assert.is_false(continue.enabled_func(), "continue must now be disabled")
    end)

    it("backs up timer-drifted save on continue and reports drift error", function()
        local valid_puzzle = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
        local valid_solution = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
        local board = require("core.board")
        local g = game.new({
            puzzle = board.from_string(valid_puzzle),
            solution = board.from_string(valid_solution),
            difficulty = "easy",
            now = function()
                return 1000
            end,
        })
        local payload = g:serialize()
        payload.timer.running = true
        payload.timer.started = os.time() - 8 * 86400
        storage.save(save_path, payload)

        local continue = item_with("Continue")
        assert.is_true(continue.enabled_func())

        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
            track_bak(widget and widget.text)
        end
        continue.callback()
        UIManager.show = original_show

        assert.is_not_nil(shown)
        assert.is_true(string.find(shown.text, "corrupted") ~= nil)
        assert.is_true(string.find(shown.text, "invalid timer state") ~= nil)
        assert.is_false(storage.exists(save_path), "drifted save must be moved")
        assert.is_false(continue.enabled_func(), "continue must now be disabled")
    end)

    it("shows failure message and keeps continue enabled when backup rename fails", function()
        local file = io.open(save_path, "wb")
        file:write('{"version": corrupt_json')
        file:close()

        local continue = item_with("Continue")
        assert.is_true(continue.enabled_func())

        -- luacheck: push ignore 122
        local real_rename = os.rename
        os.rename = function(old, new)
            if old == save_path then
                return nil, "rename failed permission denied"
            end
            return real_rename(old, new)
        end

        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
            track_bak(widget and widget.text)
        end
        continue.callback()
        UIManager.show = original_show
        os.rename = real_rename
        -- luacheck: pop

        assert.is_not_nil(shown)
        assert.is_true(string.find(shown.text, "Failed to restore") ~= nil)
        assert.is_true(string.find(shown.text, "rename failed") ~= nil)
        assert.is_true(storage.exists(save_path), "save must remain in place if backup failed")
        assert.is_true(continue.enabled_func(), "continue must remain enabled when save still exists")
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
                    sub_item_table = menu_items.sudokuplus.sub_item_table,
                },
            },
        }
        menu.item_table = menu_items.sudokuplus.sub_item_table
        menu:updateItems(1)
        assert.is_not_nil(menu)
    end)

    it("flips the auto-fill notes setting through the toggle", function()
        G_reader_settings:saveSetting("sudokuplus_autofill_notes", false)
        local toggle = item_with("Auto-fill notes")
        assert.is_false(toggle.checked_func())
        toggle.callback()
        assert.is_true(G_reader_settings:isTrue("sudokuplus_autofill_notes"))
        toggle.callback()
        assert.is_false(G_reader_settings:isTrue("sudokuplus_autofill_notes"))
    end)

    it("starts a custom game from the Custom… menu item", function()
        local custom_item = item_with("Custom…")
        assert.is_not_nil(custom_item)

        local tier_dialog, strat_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Strategy tier", 1, true) then
                tier_dialog = widget
            elseif widget and widget.buttons and widget.title and widget.title:find("Strategies", 1, true) then
                strat_dialog = widget
            end
        end
        UIManager.close = function() end

        local started_opts
        local original_start = Sudoku.startGame
        Sudoku.startGame = function(_, diff, opts)
            started_opts = { diff = diff, opts = opts }
        end

        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
            Sudoku.startGame = original_start
        end)

        custom_item.callback()
        assert.is_not_nil(tier_dialog, "tapping Custom… opens tier picker")

        -- Select Master tier (row 2, button 1)
        local master_btn
        for _, row in ipairs(tier_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Master" then
                    master_btn = btn
                end
            end
        end
        assert.is_not_nil(master_btn)
        master_btn.callback()

        assert.is_not_nil(strat_dialog, "selecting tier opens strategy picker")

        -- Find Generate button in strat_dialog
        local generate_btn
        for _, row in ipairs(strat_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Generate" then
                    generate_btn = btn
                end
            end
        end
        assert.is_not_nil(generate_btn)
        generate_btn.callback()

        assert.is_not_nil(started_opts)
        assert.are.equal("custom", started_opts.diff)
        assert.are.equal("master", started_opts.opts.target_tier)
        assert.is_true(#started_opts.opts.required_techniques > 0)
    end)

    it("offers to continue custom generation with +50% budget when generation fails", function()
        local generator = require("core.generator")
        local original_generate = generator.generate_game
        local generated_opts = {}
        generator.generate_game = function(opts)
            generated_opts[#generated_opts + 1] = opts
            return nil, "forced custom generation failure"
        end

        local confirm_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.ok_text and widget.ok_text:find("Continue", 1, true) then
                confirm_dialog = widget
            end
        end
        UIManager.close = function() end

        finally(function()
            generator.generate_game = original_generate
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        Sudoku:startGame("custom", {
            target_tier = "master",
            required_techniques = { "swordfish" },
            attempts = 100,
        })

        assert.are.equal(1, #generated_opts)
        assert.are.equal(100, generated_opts[1].max_attempts)
        assert.is_not_nil(confirm_dialog, "retry confirmation dialog is shown on failure")
        assert.is_true(confirm_dialog.ok_text:find("150", 1, true) ~= nil)

        -- Tap continue: starts next attempt round with 150 attempts and fresh seed
        confirm_dialog.ok_callback()
        assert.are.equal(2, #generated_opts)
        assert.are.equal(150, generated_opts[2].max_attempts)
        assert.is_not_nil(generated_opts[2].seed)
    end)

    it("preserves exact reproduction seed when retrying custom replay", function()
        local generator = require("core.generator")
        local original_generate = generator.generate_game
        local replay_opts = {}
        generator.generate_game = function(opts)
            replay_opts[#replay_opts + 1] = opts
            return nil, "forced replay generation failure"
        end

        local confirm_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.ok_text and widget.ok_text:find("Continue", 1, true) then
                confirm_dialog = widget
            end
        end
        UIManager.close = function() end

        finally(function()
            generator.generate_game = original_generate
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        local target_seed = 987654321
        Sudoku:replayGame(target_seed, "custom", "master", { "swordfish" })

        assert.are.equal(1, #replay_opts)
        assert.are.equal(target_seed, replay_opts[1].seed)
        assert.are.equal(100, replay_opts[1].max_attempts)

        confirm_dialog.ok_callback()
        assert.are.equal(2, #replay_opts)
        assert.are.equal(target_seed, replay_opts[2].seed, "must preserve reproduction seed across replay retries")
        assert.are.equal(150, replay_opts[2].max_attempts)
    end)

    it("restores active saved game when cancelling custom generation retry", function()
        local generator = require("core.generator")
        local original_generate = generator.generate_game
        generator.generate_game = function()
            return nil, "forced failure"
        end

        local confirm_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.ok_text and widget.ok_text:find("Continue", 1, true) then
                confirm_dialog = widget
            end
        end
        UIManager.close = function() end

        local continued = false
        local original_continue = Sudoku.continueGame
        Sudoku.continueGame = function()
            continued = true
        end

        local original_exists = storage.exists
        storage.exists = function()
            return true
        end

        finally(function()
            generator.generate_game = original_generate
            UIManager.show = original_show
            UIManager.close = original_close
            Sudoku.continueGame = original_continue
            storage.exists = original_exists
        end)

        Sudoku:startGame("custom", {
            target_tier = "master",
            required_techniques = { "swordfish" },
        })

        assert.is_not_nil(confirm_dialog)
        confirm_dialog.cancel_callback()
        assert.is_true(continued, "cancelling custom retry must restore active game if one exists")
    end)
end)
