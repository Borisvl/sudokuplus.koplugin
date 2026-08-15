package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku stats view", function()
    local Blitbuffer
    local stats
    local statsview
    local UIManager

    local PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
    local SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

    local function record(overrides)
        local base = {
            status = "finished",
            id = nil,
            seed = 424242,
            difficulty = "easy",
            duration = 60,
            hints = {},
            mistakes = 0,
            check_errors = 0,
            started_at = 1000,
            ended_at = 1060,
            moves = 10,
            filled = 5,
            correct = 5,
            puzzle = PUZZLE,
            solution = SOLUTION,
            board = PUZZLE,
        }
        for key, value in pairs(overrides or {}) do
            base[key] = value
        end
        return base
    end

    local function in_progress(overrides)
        local merged = record()
        merged.status = "in_progress"
        merged.ended_at = nil
        for key, value in pairs(overrides or {}) do
            merged[key] = value
        end
        return merged
    end

    -- finished easy game, given-up hard game, abandoned medium game
    local function sample_stats()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        assert.is_not_nil(stats.track(s, in_progress({ id = id, difficulty = "easy" })))
        assert.is_not_nil(
            stats.add(s, record({ id = id, difficulty = "easy", duration = 100, hints = { "naked_pairs" } }))
        )
        assert.is_not_nil(stats.add(s, record({ id = 2, status = "give_up", difficulty = "hard", duration = 30 })))
        assert.is_not_nil(stats.track(s, in_progress({ id = 3, difficulty = "medium" })))
        assert.is_not_nil(stats.abandon(s, 3, 2000))
        return s
    end

    local function find_item(item_table, needle)
        for _, item in ipairs(item_table) do
            if item.text and item.text:find(needle, 1, true) then
                return item
            end
        end
        return nil
    end

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        stats = require("stats")
        statsview = require("ui.statsview")
        UIManager = require("ui/uimanager")
    end)

    it("builds a dashboard menu with overview rows", function()
        local menu = statsview.dashboard(sample_stats())
        assert.is_not_nil(menu.item_table)
        assert.is_not_nil(find_item(menu.item_table, "Started: 3"), "overview shows started count")
        assert.is_not_nil(find_item(menu.item_table, "Finished: 1"), "overview shows finished count")
        assert.is_not_nil(find_item(menu.item_table, "Given up: 1"), "overview shows given-up count")
        assert.is_not_nil(find_item(menu.item_table, "Abandoned: 1"), "overview shows abandoned count")
        assert.is_not_nil(find_item(menu.item_table, "In progress: 0"), "overview shows in-progress count")
        assert.is_not_nil(find_item(menu.item_table, "Completion rate: 33%"), "completion rate is finished / started")
        assert.is_not_nil(find_item(menu.item_table, "Win rate: 50%"), "win rate is finished / completed")
        assert.is_not_nil(find_item(menu.item_table, "Total playtime"), "total playtime is shown")
        assert.is_not_nil(find_item(menu.item_table, "Current streak"), "streaks are shown")
        assert.is_not_nil(find_item(menu.item_table, "Total mistakes"), "mistakes are shown")
    end)

    it("builds a dashboard menu for an empty stats table", function()
        local menu = statsview.dashboard(stats.new())
        assert.is_not_nil(menu.item_table)
        assert.is_true(#menu.item_table >= 4)
    end)

    it("offers expandable difficulty and technique sections", function()
        local menu = statsview.dashboard(sample_stats())
        local difficulty_item = find_item(menu.item_table, "By difficulty")
        assert.is_not_nil(difficulty_item)
        assert.is_true(#difficulty_item.sub_item_table > 0, "the difficulty section expands")

        local techniques_item = find_item(menu.item_table, "Most missed strategies")
        assert.is_not_nil(techniques_item)
        assert.is_true(#techniques_item.sub_item_table > 0, "the technique section expands")
    end)

    it("opens the games list from the dashboard", function()
        local menu = statsview.dashboard(sample_stats())
        local history_item = find_item(menu.item_table, "Game history")
        assert.is_not_nil(history_item)
        local shown
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
        end
        history_item.callback()
        UIManager.show = original_show
        assert.is_not_nil(shown)
        assert.are.equal("Game history", shown.title)
        assert.are.equal(3, #shown.item_table, "all logged games are listed")
    end)

    it("lists games newest first", function()
        local s = sample_stats()
        local menu = statsview.games_list(s, {})
        assert.are.equal(3, #menu.item_table)
        assert.is_true(menu.item_table[1].text:find("#3", 1, true) ~= nil, "the newest game is on top")
        assert.is_true(menu.item_table[3].text:find("#1", 1, true) ~= nil, "the oldest game is at the bottom")
    end)

    it("shows status and time in the game rows", function()
        local menu = statsview.games_list(sample_stats(), {})
        local finished = menu.item_table[3].text
        assert.is_true(finished:find("Finished", 1, true) ~= nil)
        assert.is_true(finished:find("00:01:40", 1, true) ~= nil, "the duration is formatted")
        local given_up = menu.item_table[2].text
        assert.is_true(given_up:find("Given up", 1, true) ~= nil)
        local abandoned = menu.item_table[1].text
        assert.is_true(abandoned:find("Abandoned", 1, true) ~= nil)
    end)

    it("opens a game detail page from a history row", function()
        local s = sample_stats()
        local replayed
        local menu = statsview.games_list(s, {
            replay_cb = function(seed, difficulty)
                replayed = { seed = seed, difficulty = difficulty }
            end,
        })
        local shown
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown = widget
        end
        menu.item_table[3].callback()
        UIManager.show = original_show
        assert.is_not_nil(shown)
        assert.is_not_nil(shown.entry)
        assert.are.equal(1, shown.entry.id)
        assert.are.equal("finished", shown.entry.status)
        assert.is_nil(replayed)
        shown.replay_cb(987654, "hard")
        assert.is_not_nil(replayed, "the replay callback is wired through")
        assert.are.equal(987654, replayed.seed)
        assert.are.equal("hard", replayed.difficulty)
    end)

    it("closes the whole stats stack before replaying", function()
        local s = sample_stats()
        local closed = {}
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        local dashboard = statsview.dashboard(s, {})
        local list, detail
        UIManager.show = function(_, widget)
            if widget and widget.entry then
                detail = widget
            elseif widget and widget.item_table then
                list = widget
            end
        end
        local history_item
        for _, item in ipairs(dashboard.item_table) do
            if item.text and item.text:find("Game history", 1, true) then
                history_item = item
            end
        end
        assert.is_not_nil(history_item)
        history_item.callback()
        assert.is_not_nil(list)
        list.item_table[1].callback()
        assert.is_not_nil(detail)
        UIManager.show = original_show

        closed = {}
        detail.replay_cb(1, "easy")
        UIManager.close = original_close
        assert.are.equal(3, #closed, "detail, list and dashboard are all closed")
        assert.are.same(detail, closed[1])
        assert.are.same(list, closed[2])
        assert.are.same(dashboard, closed[3])
    end)

    it("paints a game detail page with the mini grid without error", function()
        local GameDetail = require("ui.gamedetail")
        local s = sample_stats()
        local entry = stats.list(s)[3]
        local detail = GameDetail:new {
            entry = entry,
            width = 758,
            height = 1024,
        }
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local ok = xpcall(function()
            detail:paintTo(bb, 0, 0)
        end, function(err)
            print("PAINT FAILED:\n" .. debug.traceback(err, 2))
        end)
        bb:free()
        assert.is_true(ok)
    end)

    it("paints a game detail page without a seed or replay callback", function()
        local GameDetail = require("ui.gamedetail")
        local entry = record()
        entry.seed = nil
        local detail = GameDetail:new {
            entry = entry,
            width = 758,
            height = 1024,
        }
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        detail:paintTo(bb, 0, 0)
        bb:free()
    end)

    it("paints the detail page of a game without a board snapshot", function()
        local GameDetail = require("ui.gamedetail")
        local data = {
            version = 2,
            streak = 1,
            best_streak = 1,
            next_id = 2,
            games = {
                {
                    id = 1,
                    status = "finished",
                    difficulty = "easy",
                    duration = 60,
                    hints = {},
                    mistakes = 0,
                    check_errors = 0,
                    started_at = 100,
                    ended_at = 160,
                },
            },
        }
        local loaded = assert(stats.from_table(data))
        local entry = stats.list(loaded)[1]
        assert.is_nil(entry.board, "entries without board carry no board snapshot")
        local detail = GameDetail:new {
            entry = entry,
            width = 758,
            height = 1024,
        }
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local ok = xpcall(function()
            detail:paintTo(bb, 0, 0)
        end, function(err)
            print("PAINT FAILED:\n" .. err)
        end)
        bb:free()
        assert.is_true(ok, "a migrated game must paint an empty grid, not crash")
    end)

    it("replays the exact puzzle from the detail page", function()
        local GameDetail = require("ui.gamedetail")
        local entry = record({ seed = 987654, difficulty = "hard" })
        local replayed
        local detail = GameDetail:new {
            entry = entry,
            width = 758,
            height = 1024,
            replay_cb = function(seed, difficulty)
                replayed = { seed = seed, difficulty = difficulty }
            end,
        }
        local function find_button(widget)
            for _, child in ipairs(widget) do
                if type(child) == "table" and child.text == "Play again" and child.callback then
                    return child
                end
                local found = find_button(child)
                if found then
                    return found
                end
            end
            return nil
        end
        local button = find_button(detail)
        assert.is_not_nil(button, "a playable game offers Play again")
        button.callback()
        assert.is_not_nil(replayed)
        assert.are.equal(987654, replayed.seed)
        assert.are.equal("hard", replayed.difficulty)
    end)
end)
