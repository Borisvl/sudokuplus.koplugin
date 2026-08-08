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
        bb:free()
    end)

    it("selects the tapped cell and outlines it without hiding its content", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 4)
        assert.are.equal(0, view.selected.row)
        assert.are.equal(4, view.selected.col)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 4)
        assert.are.equal(
            tonumber(theme.digit.a),
            tonumber(bb:getPixel(rect.x + 1, rect.y + 1).a),
            "selection outline on the cell border"
        )
        tap_cell(view, 1, 4)
        view:paintTo(bb, 0, 0)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(rect.x + 1, rect.y + 1).a),
            "outline cleared when the selection moves"
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
end)
