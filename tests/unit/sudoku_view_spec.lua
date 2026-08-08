package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku view", function()
    local Blitbuffer
    local DataStorage
    local bit
    local board
    local game
    local layout
    local stats
    local storage
    local SudokuView
    local theme

    local PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
    local SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
    local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
    local NAKED_SINGLE_SOLUTION = "385421967194756328627983145571892634839645271246137589462579813918364752753218496"

    local clock = { value = 1000 }
    local now = function()
        return clock.value
    end
    local save_path
    local stats_path

    local function solution_cell(row, col)
        return tonumber(SOLUTION:sub(row * 9 + col + 1, row * 9 + col + 1))
    end

    local function blank_solution(cells)
        local chars = {}
        for i = 1, 81 do
            chars[i] = SOLUTION:sub(i, i)
        end
        for _, cell in ipairs(cells) do
            chars[cell[1] * 9 + cell[2] + 1] = "0"
        end
        return table.concat(chars)
    end

    local function new_game(puzzle, solution)
        local g, err = game.new {
            puzzle = board.from_string(puzzle),
            solution = board.from_string(solution),
            difficulty = "easy",
            now = now,
        }
        assert.is_not_nil(g, err)
        return g
    end

    local function new_view(g, extra)
        local options = { game = g, width = 758, height = 1024 }
        for key, value in pairs(extra or {}) do
            options[key] = value
        end
        return SudokuView:new(options)
    end

    local function cell_center(view, row, col)
        local rect = layout.cell_rect(view.layout, row, col)
        return rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2)
    end

    local function button_center(view, row_name, id)
        for _, button in ipairs(view.layout[row_name].buttons) do
            if button.id == id then
                return button.x + math.floor(button.w / 2), button.y + math.floor(button.h / 2)
            end
        end
        error("no button " .. tostring(id) .. " in " .. row_name)
    end

    local function tap(view, x, y)
        -- dispatch through the real event path (handleEvent unpacks the
        -- event args: handlers receive (args, gesture))
        local Event = require("ui/event")
        view:handleEvent(Event:new("Tap", nil, { pos = { x = x, y = y } }))
    end

    local function tap_cell(view, row, col)
        local x, y = cell_center(view, row, col)
        tap(view, x, y)
    end

    local function tap_button(view, row_name, id)
        local x, y = button_center(view, row_name, id)
        tap(view, x, y)
    end

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        DataStorage = require("datastorage")
        bit = require("bit")
        board = require("core.board")
        game = require("game")
        layout = require("ui.layout")
        stats = require("stats")
        storage = require("storage")
        SudokuView = require("ui.sudokuview")
        theme = require("ui.theme")
        save_path = DataStorage:getDataDir() .. "/sudoku_test_save"
        stats_path = DataStorage:getDataDir() .. "/sudoku_test_stats"
    end)

    after_each(function()
        os.remove(save_path)
        os.remove(stats_path)
    end)

    it("paints the grid, digits and bars without error", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        bb:free()
    end)

    it("starts without a selection and paints no black cell", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        assert.is_nil(view.selected)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 2)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a),
            "an empty cell must stay white at game start"
        )
        bb:free()
    end)

    it("ignores number-bar taps without a selection", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        assert.are.equal(0, view.game:revision(), "no move without a selection")
        assert.is_nil(view.selected)
    end)

    it("paints crisp cell lines: thin inside boxes, thick between boxes", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local l = view.layout
        local thick_x = l.grid.x + l.thick
        local inside_x = thick_x + 1
        local thin_x = l.grid.x + layout.cell_offset(0, l.grid.cell, l.thin, l.thick) + l.grid.cell
        local black = tonumber(theme.grid_thick.a)
        local gray = tonumber(theme.grid_thin.a)
        local white = tonumber(theme.background.a)
        assert.are.equal(black, tonumber(bb:getPixel(l.grid.x + 1, l.grid.y + 1).a))
        assert.are.equal(white, tonumber(bb:getPixel(inside_x, l.grid.y + l.thick + 1).a))
        assert.are.equal(gray, tonumber(bb:getPixel(thin_x, l.grid.y + l.thick + 1).a))
        -- the box boundary between cells 2 and 3 is painted thick and black
        local lines = layout.grid_lines(l)
        assert.are.equal(l.thick, lines.horizontal[3].thickness)
        assert.are.equal(black, tonumber(bb:getPixel(l.grid.x + l.thick + 1, lines.horizontal[3].y).a))
        -- and the box boundary between cells 3 and 4 stays thin
        assert.are.equal(l.thin, lines.horizontal[4].thickness)
        assert.are.equal(gray, tonumber(bb:getPixel(l.grid.x + l.thick + 1, lines.horizontal[4].y).a))
        bb:free()
    end)

    it("inverts the selected cell but keeps its digit readable", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 0)
        assert.are.equal(0, view.selected.row)
        assert.are.equal(0, view.selected.col)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 0)
        assert.are.equal(0x00, tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a), "selected cell is inverted")
        local white = false
        for y = rect.y + 2, rect.y + rect.h - 3 do
            for x = rect.x + 2, rect.x + rect.w - 3 do
                if tonumber(bb:getPixel(x, y).a) == 0xFF then
                    white = true
                end
            end
        end
        assert.is_true(white, "digit must stay readable on the inverted cell")
        tap_cell(view, 1, 4)
        view:paintTo(bb, 0, 0)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a),
            "cell restored when the selection moves"
        )
        bb:free()
    end)

    it("places a digit from the number bar onto the selected cell", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        assert.are.equal(2, view.game:get(0, 3))
    end)

    it("removes a placed digit when its button is pressed again", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        assert.are.equal(2, view.game:get(0, 3))
        tap_button(view, "number_row", 2)
        assert.are.equal(0, view.game:get(0, 3))
    end)

    it("toggles notes in notes mode", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "tool_row", "notes")
        local value = solution_cell(0, 3)
        local v_bit = bit.lshift(1, value - 1)
        -- notes start empty; a tap adds the note, a second tap removes it
        tap_button(view, "number_row", value)
        assert.is_true(bit.band(view.game:get_notes(0, 3), v_bit) ~= 0)
        tap_button(view, "number_row", value)
        assert.are.equal(0, bit.band(view.game:get_notes(0, 3), v_bit))
    end)

    it("erases a value from the selected cell", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        tap_button(view, "number_row", "erase")
        assert.are.equal(0, view.game:get(0, 3))
    end)

    it("undoes and redoes moves through the tool row", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 5)
        tap_button(view, "number_row", 7)
        assert.are.equal(2, view.game:get(0, 3))
        assert.are.equal(7, view.game:get(0, 5))
        tap_button(view, "tool_row", "undo")
        assert.are.equal(0, view.game:get(0, 5))
        assert.are.equal(2, view.game:get(0, 3))
        tap_button(view, "tool_row", "redo")
        assert.are.equal(7, view.game:get(0, 5))
    end)

    it("leaves givens untouched", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 0)
        tap_button(view, "number_row", 2)
        assert.are.equal(5, view.game:get(0, 0))
    end)

    it("paints the notes of a cell as small digits", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "tool_row", "notes")
        local value = solution_cell(0, 3)
        tap_button(view, "number_row", value)
        tap_cell(view, 0, 0)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 3)
        local found = false
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do
                if tonumber(bb:getPixel(x, y).a) == tonumber(theme.note.a) then
                    found = true
                end
            end
        end
        assert.is_true(found, "no note ink in cell")
        bb:free()
    end)

    it("keeps notes readable on the inverted selection", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "tool_row", "notes")
        local value = solution_cell(0, 3)
        tap_button(view, "number_row", value)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 3)
        local white = false
        for y = rect.y + 2, rect.y + rect.h - 3 do
            for x = rect.x + 2, rect.x + rect.w - 3 do
                if tonumber(bb:getPixel(x, y).a) == 0xFF then
                    white = true
                end
            end
        end
        assert.is_true(white, "note must stay readable on the inverted cell")
        bb:free()
    end)

    it("centers a placed digit vertically inside its cell", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 0)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 3)
        local min_y, max_y
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do
                if tonumber(bb:getPixel(x, y).a) == tonumber(theme.digit.a) then
                    min_y = math.min(min_y or y, y)
                    max_y = math.max(max_y or y, y)
                end
            end
        end
        assert.is_not_nil(min_y, "no digit ink in cell")
        local ink_center = (min_y + max_y) / 2
        local rect_center = rect.y + rect.h / 2
        assert.is_true(math.abs(ink_center - rect_center) <= 3, "digit not vertically centered in cell")
        bb:free()
    end)

    it("shows check-revealed wrong cells in the check state", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        tap_button(view, "tool_row", "check")
        assert.are.equal(1, view.game:check_errors())
        local revealed = view.game:revealed()
        assert.are.equal(1, #revealed)
        assert.are.equal(0, revealed[1][1])
        assert.are.equal(3, revealed[1][2])
    end)

    it("records a finished game in stats and clears the save", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local view = new_view(new_game(puzzle, SOLUTION), {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 8, 0)
        tap_button(view, "number_row", solution_cell(8, 0))
        assert.is_true(view.game:is_finished())
        assert.are.equal(1, #s.finished)
        local loaded = storage.load(stats_path)
        assert.is_not_nil(loaded)
        assert.are.equal(1, #loaded.finished)
        assert.are.equal("easy", loaded.finished[1].difficulty)
        assert.is_nil(io.open(save_path, "rb"))
    end)

    it("offers a new game and statistics on win", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local started, stats_requested
        local view = new_view(new_game(puzzle, SOLUTION), {
            new_game_cb = function(difficulty)
                started = difficulty
            end,
            show_stats_cb = function()
                stats_requested = true
            end,
        })
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.cancel_text then
                dialog = widget
            end
        end
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 8, 0)
        tap_button(view, "number_row", solution_cell(8, 0))
        UIManager.show = original_show
        assert.is_not_nil(dialog, "win must show a dialog")
        assert.is_true(dialog.text:find("Puzzle solved", 1, true) ~= nil)
        assert.are.equal("New game", dialog.choice1_text)
        assert.are.equal("Statistics", dialog.choice2_text)
        assert.is_nil(started)
        dialog.choice1_callback()
        assert.are.equal("easy", started, "new game restarts at the same difficulty")
        assert.is_nil(stats_requested)
        dialog.choice2_callback()
        assert.is_true(stats_requested, "statistics open from the win dialog")
    end)

    it("reveals a hint in three taps: name, pattern, apply", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local banner = view.layout.banner
        local action = { row = 4, col = 4, value = 5 }
        local cell = layout.cell_rect(view.layout, action.row, action.col)

        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        assert.are.equal(1, #view.game:hints(), "the first tap records the missed strategy")
        assert.are.equal(0, view.game:get(action.row, action.col), "nothing is applied yet")
        view:paintTo(bb, 0, 0)
        local ink = false
        for y = banner.y + 2, banner.y + banner.h - 3 do
            for x = banner.x + 2, banner.x + banner.w - 3 do
                if tonumber(bb:getPixel(x, y).a) ~= tonumber(theme.background.a) then
                    ink = true
                end
            end
        end
        assert.is_true(ink, "the banner shows the technique name")

        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage)
        assert.are.equal(1, #view.game:hints(), "the missed strategy is recorded only once")
        view:paintTo(bb, 0, 0)
        assert.are.equal(
            tonumber(theme.hint_fill.a),
            tonumber(bb:getPixel(cell.x + 2, cell.y + 2).a),
            "the pattern cell is highlighted"
        )

        tap_button(view, "tool_row", "hint")
        assert.are.equal(0, view._hint_stage, "the reveal ends after applying")
        assert.are.equal(action.value, view.game:get(action.row, action.col), "the third tap applies the placement")
        view:paintTo(bb, 0, 0)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(cell.x + 2, cell.y + 2).a),
            "the highlight is cleared after applying"
        )
        bb:free()

        tap_button(view, "tool_row", "undo")
        assert.are.equal(0, view.game:get(action.row, action.col), "the hint placement is undoable")
    end)

    it("cancels a hint reveal on any other interaction", function()
        local view = new_view(new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local cell = layout.cell_rect(view.layout, 8, 8)

        tap_button(view, "tool_row", "hint")
        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage)
        tap_cell(view, 0, 0)
        assert.are.equal(0, view._hint_stage, "a cell tap cancels the reveal")
        view:paintTo(bb, 0, 0)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(cell.x + 2, cell.y + 2).a),
            "the highlight is cleared on cancel"
        )
        assert.are.equal(0, view.game:get(8, 8), "nothing was applied")

        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        tap_button(view, "number_row", 4)
        assert.are.equal(0, view._hint_stage, "a move cancels the reveal")
        assert.are.equal(0, view.game:get(8, 8))
        bb:free()
    end)

    it("suggests re-adding notes when a cleared cell blocks the hint", function()
        local g = new_game(PUZZLE, SOLUTION)
        assert.is_true(g:toggle_note(8, 0, 1))
        assert.is_true(g:toggle_note(8, 0, 1), "cleared cell becomes ground truth")
        g.hint = function()
            return { status = "none", reason = "no_applicable_technique", revision = g:revision() }
        end
        local view = new_view(g)
        local shown
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.text then
                shown = widget
            end
        end
        tap_button(view, "tool_row", "hint")
        UIManager.show = original_show
        assert.is_not_nil(shown, "a message must be shown")
        assert.is_true(shown.text:find("notes", 1, true) ~= nil, "the message mentions notes")
        assert.is_true(shown.text:find("(9, 1)", 1, true) ~= nil, "the message names the blocked cell")
    end)

    it("gives up: records a give-up and clears the save", function()
        local s = stats.new()
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        view:onGiveUp()
        assert.are.equal(1, #s.given_up)
        assert.is_nil(io.open(save_path, "rb"))
    end)

    it("quits: pauses the timer and saves the game for later", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g, { save_path = save_path })
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 2)
        view:onClose()
        local data = storage.load(save_path)
        assert.is_not_nil(data)
        local restored, err = game.restore(data, { now = now })
        assert.is_not_nil(restored, err)
        assert.are.equal(2, restored:get(0, 3))
        assert.is_false(restored.timer.running)
    end)

    it("pauses the timer on suspend and resumes on wake", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        clock.value = clock.value + 10
        assert.is_true(g:elapsed() >= 10)
        view:onSuspend()
        local paused = g:elapsed()
        clock.value = clock.value + 100
        assert.are.equal(paused, g:elapsed())
        view:onResume()
        clock.value = clock.value + 5
        assert.is_true(g:elapsed() > paused)
    end)

    it("pauses the timer while the pause menu is open", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        view:openMenu()
        assert.is_true(view.menu_open)
        assert.is_false(g.timer.running)
        view:closeMenu()
        assert.is_false(view.menu_open)
        assert.is_true(g.timer.running)
    end)

    describe("refresh modes and regions", function()
        local UIManager
        local calls
        local original_set_dirty

        local function paint_view(view)
            local bb = Blitbuffer.new(758, 1024)
            bb:fill(Blitbuffer.COLOR_WHITE)
            view:paintTo(bb, 0, 0)
            bb:free()
        end

        local function last_call()
            assert.is_true(#calls > 0, "no setDirty call recorded")
            return calls[#calls]
        end

        local function last_tool_call(view)
            for i = #calls, 1, -1 do
                local call = calls[i]
                if call.region and call.region.y >= view.layout.tool_row.y then
                    return call
                end
            end
            return nil
        end

        local function rect_key(rect)
            return rect.x .. "," .. rect.y .. "," .. rect.w .. "," .. rect.h
        end

        -- The set of refreshed region keys, without the tool row strip.
        local function grid_region_set(view)
            local grid_bottom = view.layout.grid.y + view.layout.grid.h
            local set = {}
            for _, call in ipairs(calls) do
                if call.region and call.region.y < grid_bottom then
                    set[rect_key(call.region)] = true
                end
            end
            return set
        end

        local function count_set(set)
            local n = 0
            for _ in pairs(set) do
                n = n + 1
            end
            return n
        end

        local function assert_rect(region, rect)
            assert.is_not_nil(region, "expected a refresh region")
            assert.are.equal(rect.x, region.x)
            assert.are.equal(rect.y, region.y)
            assert.are.equal(rect.w, region.w)
            assert.are.equal(rect.h, region.h)
        end

        before_each(function()
            UIManager = require("ui/uimanager")
            calls = {}
            original_set_dirty = UIManager.setDirty
            UIManager.setDirty = function(self, widget, mode, region)
                table.insert(calls, { widget = widget, mode = mode, region = region })
            end
        end)

        after_each(function()
            UIManager.setDirty = original_set_dirty
        end)

        it("uses a full-screen refresh before the first paint", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            view:refresh()
            assert.are.equal("full", last_call().mode)
        end)

        it("refreshes only the selected cell on selection", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 3, 4)
            local call = last_call()
            assert.are.equal("ui", call.mode)
            assert_rect(call.region, layout.cell_rect(view.layout, 3, 4))
        end)

        it("refreshes the old and new cell separately when the selection moves", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 3, 4)
            calls = {}
            tap_cell(view, 5, 7)
            local set = grid_region_set(view)
            assert.are.equal(2, #calls, "two separate cell refreshes, no bounding box")
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 3, 4))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 5, 7))])
        end)

        it("refreshes each affected cell separately when placing a digit", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 5)
            calls = {}
            tap_button(view, "number_row", 3)
            local set = grid_region_set(view)
            -- 3 sits at (0,1) in the row and (4,5) in the column: the target
            -- cell and both peers refresh individually, never as one rectangle.
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 5))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 1))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 4, 5))])
            assert.are.equal(3, count_set(set))
            local tool = last_tool_call(view)
            assert.is_not_nil(tool, "undo/redo state changed, tool row must refresh")
            assert.are.equal("ui", tool.mode)
            assert_rect(tool.region, view.layout.tool_row)
        end)

        it("refreshes the tool row only when notes mode toggles", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_button(view, "tool_row", "notes")
            local call = last_call()
            assert.are.equal("ui", call.mode)
            assert_rect(call.region, view.layout.tool_row)
            assert.are.equal(0, count_set(grid_region_set(view)), "no grid region needed")
        end)

        it("skips the tool row when undo/redo state did not change", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 5)
            tap_button(view, "number_row", 3) -- first move enables undo
            calls = {}
            tap_button(view, "number_row", 4) -- second move: undo stays enabled
            local set = grid_region_set(view)
            -- the second tap replaces 3 with 4: (0,5), (0,1) and (4,5) (peers
            -- holding the replaced 3, whose conflicts disappear) refresh
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 5))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 1))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 4, 5))])
            assert.are.equal(3, count_set(set), "the replaced cell and its conflict peers refresh")
            assert.is_nil(last_tool_call(view), "tool row must not refresh on the second move")
        end)

        it("refreshes only the cells an undo or redo can affect", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 6)
            tap_button(view, "number_row", 2) -- (6,6) holds 2
            calls = {}
            tap_button(view, "tool_row", "undo")
            local set = grid_region_set(view)
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 6))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 6, 6))])
            assert.is_not_nil(last_tool_call(view), "undo/redo state changed")
            assert.are.equal(2, count_set(set))
            calls = {}
            tap_button(view, "tool_row", "redo")
            set = grid_region_set(view)
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 6))])
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 6, 6))])
            assert.is_not_nil(last_tool_call(view))
            assert.are.equal(2, count_set(set))
        end)

        it("refreshes only the newly revealed cells on check", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 3)
            tap_button(view, "number_row", 2) -- (0,3) is wrong: solution digit is 6
            calls = {}
            tap_button(view, "tool_row", "check")
            local set = grid_region_set(view)
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 3))])
            assert.are.equal(1, count_set(set), "only the revealed cell refreshes")
            assert.is_nil(last_tool_call(view), "tool row state did not change")
        end)

        it("uses a coarse full-screen partial when closing the pause menu", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            view:openMenu()
            view:closeMenu()
            local call = last_call()
            assert.are.equal("ui", call.mode)
            assert.is_nil(call.region)
        end)

        it("refreshes the banner and pattern cells through the hint reveal", function()
            local view = new_view(new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION))
            paint_view(view)

            tap_button(view, "tool_row", "hint")
            local call = last_call()
            assert.are.equal("ui", call.mode)
            assert_rect(call.region, view.layout.banner)

            calls = {}
            tap_button(view, "tool_row", "hint")
            local set = grid_region_set(view)
            assert.is_not_nil(
                set[rect_key(layout.cell_rect(view.layout, 8, 8))],
                "the pattern cell refreshes when highlighted"
            )
            local banner_call
            for _, c in ipairs(calls) do
                if c.region and c.region.y == view.layout.banner.y then
                    banner_call = c
                end
            end
            assert.is_not_nil(banner_call, "the banner refreshes on stage 2")

            calls = {}
            tap_button(view, "tool_row", "hint")
            set = grid_region_set(view)
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 8, 8))], "the applied cell refreshes")
            assert.are.equal(1, count_set(set), "no coarse refresh for a hint placement")
        end)

        it("full-refreshes on resume", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            view:onResume()
            assert.are.equal("full", last_call().mode)
        end)

        it("updates dimen, layout and the tap range on dimension changes", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            local Geom = require("ui/geometry")
            view:onSetDimensions(Geom:new { x = 0, y = 0, w = 1000, h = 1200 })
            assert.are.equal(1000, view.width)
            assert.are.equal(1200, view.height)
            assert.are.equal(1000, view.dimen.w)
            assert.are.equal(1200, view.dimen.h)
            assert.are.equal(1000, view.layout.width)
            assert.are.equal(1200, view.layout.height)
            assert.are.equal(1000, view.ges_events.Tap[1].range.w)
            assert.are.equal(1200, view.ges_events.Tap[1].range.h)
            assert.are.equal("full", last_call().mode)
        end)
    end)
end)
