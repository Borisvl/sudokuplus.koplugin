package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path
local test_guard = require("sudoku_frontend_test_guard")
test_guard.install()

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

    local function first_cell_with(value)
        for r = 0, 8 do
            for c = 0, 8 do
                if solution_cell(r, c) == value then
                    return r, c
                end
            end
        end
        error("no cell with value " .. tostring(value))
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

    local function count_closed(list, widget)
        local n = 0
        for _, entry in ipairs(list) do
            if entry == widget then
                n = n + 1
            end
        end
        return n
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

    local function hold(view, x, y)
        local Event = require("ui/event")
        view:handleEvent(Event:new("Hold", nil, { pos = { x = x, y = y } }))
    end

    local function hold_cell(view, row, col)
        local x, y = cell_center(view, row, col)
        hold(view, x, y)
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
        assert.is_nil(view.armed)
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

    it("arms a number from the bar without a selection", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        assert.are.equal(2, view.armed)
        assert.are.equal(0, view.game:revision(), "arming never mutates the board")
        assert.is_nil(view.selected)
        tap_button(view, "number_row", 2)
        assert.is_nil(view.armed, "tapping the armed digit again disarms it")
    end)

    it("clears the board selection when a digit is armed", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_cell(view, 0, 0) -- select a given 5
        assert.is_not_nil(view.selected)
        tap_button(view, "number_row", 2)
        assert.are.equal(2, view.armed)
        assert.is_nil(view.selected, "arming clears the board selection")
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

    it("places the armed digit on a tapped cell", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        assert.are.equal(2, view.game:get(0, 3))
        assert.are.equal(2, view.armed, "the digit stays armed for further fills")
    end)

    it("erases a digit by tapping a cell that already holds it", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        assert.are.equal(2, view.game:get(0, 3))
        tap_cell(view, 0, 3)
        assert.are.equal(0, view.game:get(0, 3))
    end)

    it("toggles notes in notes mode", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "tool_row", "notes")
        local value = solution_cell(0, 3)
        local v_bit = bit.lshift(1, value - 1)
        -- notes start empty; a tap adds the note, a second tap removes it
        tap_button(view, "number_row", value)
        tap_cell(view, 0, 3)
        assert.is_true(bit.band(view.game:get_notes(0, 3), v_bit) ~= 0)
        tap_cell(view, 0, 3)
        assert.are.equal(0, bit.band(view.game:get_notes(0, 3), v_bit))
    end)

    it("writes a note with a long press when notes mode is off", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local value = solution_cell(0, 3)
        local v_bit = bit.lshift(1, value - 1)
        tap_button(view, "number_row", value)
        hold_cell(view, 0, 3)
        assert.is_true(bit.band(view.game:get_notes(0, 3), v_bit) ~= 0, "long press adds a note")
        assert.are.equal(0, view.game:get(0, 3), "no value is placed")
        hold_cell(view, 0, 3)
        assert.are.equal(0, bit.band(view.game:get_notes(0, 3), v_bit), "long press toggles the note off")
    end)

    it("writes a value with a long press when notes mode is on", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "tool_row", "notes")
        tap_button(view, "number_row", 2)
        hold_cell(view, 0, 3)
        assert.are.equal(2, view.game:get(0, 3), "long press places the value")
        hold_cell(view, 0, 3)
        assert.are.equal(0, view.game:get(0, 3), "long press erases the same value again")
    end)

    it("does nothing on a long press without an armed digit", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        hold_cell(view, 0, 3)
        assert.are.equal(0, view.game:revision())
        assert.is_nil(view.selected, "no cursor movement without an armed digit")
    end)

    it("undoes and redoes moves through the tool row", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", 7)
        tap_cell(view, 0, 5)
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
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 0)
        assert.are.equal(5, view.game:get(0, 0))
        assert.are.equal(0, view.game:revision())
    end)

    it("paints the notes of a cell as small digits", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local value = solution_cell(0, 3)
        tap_button(view, "number_row", value)
        hold_cell(view, 0, 3)
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
        tap_button(view, "tool_row", "notes")
        local value = solution_cell(0, 3)
        tap_button(view, "number_row", value)
        tap_cell(view, 0, 3)
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
        tap_button(view, "number_row", 2)
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
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        tap_button(view, "tool_row", "check")
        assert.are.equal(1, view.game:check_errors())
        local revealed = view.game:revealed()
        assert.are.equal(1, #revealed)
        assert.are.equal(0, revealed[1][1])
        assert.are.equal(3, revealed[1][2])
    end)

    local function bar_geometry(rect)
        return rect.x + math.floor(rect.w * 0.08),
            rect.x + rect.w - math.floor(rect.w * 0.08) - 1,
            rect.y + math.floor(rect.h / 2)
    end

    -- A dithered fill is a black/white pattern: the cell shows both colors
    -- in the region above the digit glyph and clear of the grid borders,
    -- while a plain cell is all white there.
    local function assert_dither(bb, rect, message)
        local black, white = false, false
        for dy = 3, 12 do
            for dx = 3, 12 do
                local a = tonumber(bb:getPixel(rect.x + dx, rect.y + dy).a)
                if a == 0 then
                    black = true
                elseif a == 255 then
                    white = true
                end
            end
        end
        assert.is_true(black, message .. " (needs black pixels)")
        assert.is_true(white, message .. " (needs white pixels)")
    end

    -- The strike shares the digit's ink, so a bar must be proven by its
    -- extent: a wide continuous run of ink pixels at the bar row.
    local function bar_row_ink(bb, rect, ink)
        local _, _, bar_y = bar_geometry(rect)
        local count = 0
        for x = rect.x, rect.x + rect.w - 1 do
            if tonumber(bb:getPixel(x, bar_y).a) == tonumber(ink) then
                count = count + 1
            end
        end
        return count
    end

    it("strikes through the digit of a check-revealed wrong cell", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        tap_button(view, "tool_row", "check")
        assert.are.equal(1, #view.game:revealed())
        tap_button(view, "number_row", 2) -- disarm
        tap_cell(view, 8, 5) -- move the cursor off the revealed cell
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 3)
        local bar_left, bar_right, _ = bar_geometry(rect)
        assert.are.equal(
            tonumber(theme.digit.a),
            tonumber(bb:getPixel(bar_left, rect.y + math.floor(rect.h / 2)).a),
            "the strike bar starts near the left edge of the revealed cell"
        )
        assert.are.equal(
            tonumber(theme.digit.a),
            tonumber(bb:getPixel(bar_right, rect.y + math.floor(rect.h / 2)).a),
            "the strike bar spans most of the revealed cell width"
        )
        assert.is_true(
            bar_row_ink(bb, rect, theme.digit.a) > math.floor(rect.w * 0.75),
            "the bar is a wide ink line, not glyph pixels"
        )
        assert.are.equal(
            tonumber(theme.wrong_fill.a),
            tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a),
            "the revealed cell keeps its wrong_fill background"
        )
        bb:free()
    end)

    it("does not strike correct or conflict-only cells", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        assert.is_true(view.game:place(0, 3, 1), "a 1 conflicting with the given 1 at (1, 3)")
        assert.are.equal(0, view.game:check_errors(), "no check was performed")
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local function bar_pixel(r, c)
            local rect = layout.cell_rect(view.layout, r, c)
            -- Offset 9 is inside the strike span and clear of the digit, so
            -- black means a strike bar.
            local bar_y = rect.y + math.floor(rect.h / 2)
            return tonumber(bb:getPixel(rect.x + math.floor(rect.w * 0.08) + 3, bar_y).a)
        end
        assert.are.equal(tonumber(theme.background.a), bar_pixel(2, 7), "a correct cell has no strike")
        assert.are.equal(tonumber(theme.wrong_fill.a), bar_pixel(1, 3), "a conflict cell is filled but not struck")
        assert.are.equal(tonumber(theme.wrong_fill.a), bar_pixel(0, 3), "a conflict cell is filled but not struck")
        bb:free()
    end)

    it("keeps the strike visible when the revealed cell is selected", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        tap_button(view, "tool_row", "check")
        tap_button(view, "number_row", 2) -- disarm before selecting the cell
        tap_cell(view, 0, 3) -- move the cursor onto the revealed cell
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 3)
        local bar_left, bar_right, _ = bar_geometry(rect)
        assert.are.equal(
            tonumber(theme.invert_fg.a),
            tonumber(bb:getPixel(bar_left, rect.y + math.floor(rect.h / 2)).a),
            "the strike uses the inverted ink on the selected cell"
        )
        assert.are.equal(
            tonumber(theme.invert_fg.a),
            tonumber(bb:getPixel(bar_right, rect.y + math.floor(rect.h / 2)).a),
            "the strike spans the selected cell"
        )
        assert.is_true(
            bar_row_ink(bb, rect, theme.invert_fg.a) > math.floor(rect.w * 0.75),
            "the strike stays a wide line on the selected cell"
        )
        bb:free()
    end)

    it("clears the strike once the revealed cell is fixed", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 2)
        tap_cell(view, 2, 0) -- a wrong digit (the solution has 1)
        tap_button(view, "tool_row", "check")
        tap_button(view, "number_row", 1)
        tap_cell(view, 2, 0) -- replace it with the solution digit
        tap_button(view, "number_row", 1) -- disarm so no match highlight lingers
        tap_cell(view, 8, 5) -- move the cursor off the fixed cell
        assert.are.equal(0, #view.game:revealed(), "fixing the cell clears the reveal")
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 2, 0)
        local bar_left, _, bar_y = bar_geometry(rect)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(bar_left, bar_y).a),
            "the strike is gone after the fix"
        )
        bb:free()
    end)

    it("records a finished game in stats and clears the save", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local view = new_view(new_game(puzzle, SOLUTION), {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_true(view.game:is_finished())
        assert.are.equal(1, #s.games)
        assert.are.equal("finished", s.games[1].status)
        assert.are.equal("easy", s.games[1].difficulty)
        local loaded = storage.load(stats_path)
        assert.is_not_nil(loaded)
        assert.are.equal(1, #loaded.games)
        assert.are.equal("finished", loaded.games[1].status)
        assert.are.equal("easy", loaded.games[1].difficulty)
        assert.is_nil(io.open(save_path, "rb"))
    end)

    it("keeps the active save until finished statistics can be retried", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local g = new_game(puzzle, SOLUTION)
        g.id = assert(stats.reserve_id(s))
        assert.is_true(storage.save(save_path, g:serialize()))
        local stats_save_fails = true
        local fake_storage = {
            save = function(path, data)
                if path == stats_path and stats_save_fails then
                    return nil, "stats disk full"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(g, {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
            storage_adapter = fake_storage,
        })
        local retry_dialog, win_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            elseif widget and widget.title and widget.title:find("Puzzle solved", 1, true) then
                win_dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)

        assert.is_not_nil(retry_dialog)
        assert.is_nil(win_dialog, "the win transition waits for required persistence")
        assert.is_true(storage.exists(save_path), "the active save remains recoverable")
        assert.are.equal(1, s.streak)

        stats_save_fails = false
        retry_dialog.ok_callback()
        assert.is_not_nil(win_dialog)
        assert.is_false(storage.exists(save_path))
        assert.are.equal(1, #s.games)
        assert.are.equal(1, s.streak, "retry must not apply terminal statistics twice")
    end)

    it("retries save deletion before exposing the completed transition", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local g = new_game(puzzle, SOLUTION)
        g.id = assert(stats.reserve_id(s))
        assert.is_true(storage.save(save_path, g:serialize()))
        local delete_fails = true
        local fake_storage = {
            save = storage.save,
            delete = function(path)
                if delete_fails then
                    return nil, "delete denied"
                end
                return storage.delete(path)
            end,
            exists = storage.exists,
        }
        local view = new_view(g, {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
            storage_adapter = fake_storage,
        })
        local retry_dialog, win_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            elseif widget and widget.title and widget.title:find("Puzzle solved", 1, true) then
                win_dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_not_nil(retry_dialog)
        assert.is_truthy(retry_dialog.text:find("remove the active game save", 1, true))
        assert.is_nil(win_dialog)
        assert.is_true(storage.exists(save_path))

        delete_fails = false
        retry_dialog.ok_callback()
        assert.is_not_nil(win_dialog)
        assert.is_false(storage.exists(save_path))
    end)

    it("offers a new game, statistics, and close on win", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local g = new_game(puzzle, SOLUTION)
        g.seed = 98765
        local view = new_view(g)
        local dialog, picker_dialog, stats_menu
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        local closed = {}
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Puzzle solved", 1, true) then
                dialog = widget
            elseif widget and widget.buttons and widget.title and widget.title:find("Choose difficulty", 1, true) then
                picker_dialog = widget
            elseif widget and widget.item_table then
                stats_menu = widget
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end

        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)

        assert.is_not_nil(dialog, "win must show a ButtonDialog")
        assert.is_true(dialog.title:find("Puzzle solved", 1, true) ~= nil)
        assert.is_true(dialog.title:find("Seed: 9876 5", 1, true) ~= nil, "win dialog title contains formatted seed")
        assert.is_true(dialog.title:find("Techniques: Singles only", 1, true) ~= nil)
        assert.are.equal("New game", dialog.buttons[1][1].text)
        assert.are.equal("Statistics", dialog.buttons[1][2].text)
        assert.are.equal("Close", dialog.buttons[2][1].text)

        -- 1. Test "New game": opens difficulty picker
        dialog.buttons[1][1].callback()
        assert.is_not_nil(picker_dialog, "tapping New game opens difficulty picker")
        assert.are.equal(dialog, closed[1], "the win dialog is closed before opening picker")

        -- 2. Test cancelling difficulty picker re-opens win dialog
        local cancel_button
        for _, row in ipairs(picker_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Cancel" then
                    cancel_button = btn
                end
            end
        end
        assert.is_not_nil(cancel_button)
        dialog = nil
        cancel_button.callback()
        assert.is_not_nil(dialog, "cancelling picker re-shows win dialog")

        -- 3. Test "Statistics": opens statsview without closing view
        stats_menu = nil
        dialog.buttons[1][2].callback()
        assert.is_not_nil(stats_menu, "tapping Statistics opens dashboard")
        assert.are.equal(0, count_closed(closed, view), "opening statistics must not close SudokuView")

        -- 4. Test "Close" button closes dialog and view
        dialog.buttons[2][1].callback()
        assert.are.equal(1, count_closed(closed, view), "tapping Close closes SudokuView")
    end)

    it("is idempotent onWin and guards against stacking win dialogs", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local view = new_view(new_game(puzzle, SOLUTION), {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        local shown = {}
        local closed = {}
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Puzzle solved", 1, true) then
                shown[#shown + 1] = widget
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)

        assert.are.equal(1, #shown)
        assert.are.equal(1, #s.games)
        assert.are.equal("finished", s.games[1].status)

        -- Fire onWin a second time
        view:onWin()
        assert.are.equal(2, #shown)
        assert.are.equal(shown[1], closed[1], "first dialog is closed so dialogs never stack")
        assert.are.equal(1, #s.games, "stats must not record game twice")
    end)

    it("closes dialog and view on outside-tap / Back (tap_close_callback) on win dialog", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local view = new_view(new_game(puzzle, SOLUTION))
        local dialog
        local closed = {}
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Puzzle solved", 1, true) then
                dialog = widget
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_not_nil(dialog)

        dialog.tap_close_callback()
        assert.are.equal(dialog, closed[1], "tap_close_callback closes dialog")
        assert.are.equal(view, closed[2], "tap_close_callback closes view")
    end)

    it("does not emit spurious log warnings when opening statistics on a finished game", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local view = new_view(new_game(puzzle, SOLUTION), {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        local logger = require("logger")
        local warnings = {}
        local original_warn = logger.warn
        logger.warn = function(msg)
            warnings[#warnings + 1] = msg
        end
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Puzzle solved", 1, true) then
                dialog = widget
            end
        end
        finally(function()
            logger.warn = original_warn
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_not_nil(dialog)

        dialog.buttons[1][2].callback() -- tap Statistics
        for _, w in ipairs(warnings) do
            assert.is_nil(w:find("game is already finished", 1, true), "no spurious warning on stats open: " .. w)
        end
    end)

    it("forwards Custom replay metadata from win statistics without closing the source view", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local replayed_seed, replayed_difficulty, replayed_tier, replayed_techniques
        local s = stats.new()
        local view = new_view(new_game(puzzle, SOLUTION), {
            stats = s,
            replay_cb = function(seed, difficulty, custom_tier, custom_techniques)
                replayed_seed = seed
                replayed_difficulty = difficulty
                replayed_tier = custom_tier
                replayed_techniques = custom_techniques
            end,
        })
        local shown_widgets = {}
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        local closed = {}
        UIManager.show = function(_, widget)
            shown_widgets[#shown_widgets + 1] = widget
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        local win_dialog = shown_widgets[1]
        assert.is_not_nil(win_dialog)

        win_dialog.buttons[1][2].callback()
        local stats_menu = shown_widgets[2]
        assert.is_not_nil(stats_menu)
        assert.are.equal(0, count_closed(closed, view))

        -- Find game history in stats_menu and replay
        local history_item
        for _, item in ipairs(stats_menu.item_table) do
            if item.text and item.text:find("Game history", 1, true) then
                history_item = item
            end
        end
        assert.is_not_nil(history_item)

        history_item.callback()
        local history_menu = shown_widgets[3]
        assert.is_not_nil(history_menu)
        assert.is_true(#history_menu.item_table >= 1)

        history_menu.item_table[1].callback()
        local detail_view = shown_widgets[4]
        assert.is_not_nil(detail_view)

        -- Trigger "Play again"
        assert.is_not_nil(detail_view.replay_cb)
        detail_view.replay_cb(12345, "custom", "master", { "swordfish", "x_wing" })
        assert.are.equal(12345, replayed_seed)
        assert.are.equal("custom", replayed_difficulty)
        assert.are.equal("master", replayed_tier)
        assert.are.same({ "swordfish", "x_wing" }, replayed_techniques)
        assert.are.equal(0, count_closed(closed, view), "the replacement coordinator owns the source view")
        assert.are.equal(1, count_closed(closed, win_dialog), "replaying from stats must close parent win dialog")
    end)

    it("replays from pause statistics without closing the source view", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        local replayed_seed, replayed_difficulty
        local g = new_game(PUZZLE, SOLUTION, function()
            return 1000
        end)
        g.id = id
        local view = new_view(g, {
            stats = s,
            replay_cb = function(seed, difficulty)
                replayed_seed = seed
                replayed_difficulty = difficulty
            end,
        })
        assert.is_true(g:place(0, 2, 4))
        view:afterMove()

        local shown_widgets = {}
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        local closed = {}
        UIManager.show = function(_, widget)
            shown_widgets[#shown_widgets + 1] = widget
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        view:openMenu()
        local pause_dialog = shown_widgets[1]
        assert.is_not_nil(pause_dialog)

        pause_dialog.buttons[1][2].callback() -- tap Statistics
        local stats_menu = shown_widgets[2]
        assert.is_not_nil(stats_menu)

        local history_item
        for _, item in ipairs(stats_menu.item_table) do
            if item.text and item.text:find("Game history", 1, true) then
                history_item = item
            end
        end
        assert.is_not_nil(history_item)

        history_item.callback()
        local history_menu = shown_widgets[3]
        assert.is_not_nil(history_menu)
        assert.is_true(#history_menu.item_table >= 1)

        history_menu.item_table[1].callback()
        local detail_view = shown_widgets[4]
        assert.is_not_nil(detail_view)

        -- Trigger "Play again"
        assert.is_not_nil(detail_view.replay_cb)
        detail_view.replay_cb(54321, "hard")
        assert.are.equal(54321, replayed_seed)
        assert.are.equal("hard", replayed_difficulty)
        assert.are.equal(0, count_closed(closed, view), "the replacement coordinator owns the source view")
        assert.are.equal(1, count_closed(closed, pause_dialog), "replaying from stats must close parent pause dialog")
    end)

    it("starts selected difficulty when chosen from win dialog", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local started
        local view = new_view(new_game(puzzle, SOLUTION), {
            new_game_cb = function(difficulty)
                started = difficulty
            end,
        })
        local dialog, picker_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        local closed = {}
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Puzzle solved", 1, true) then
                dialog = widget
            elseif widget and widget.buttons and widget.title and widget.title:find("Choose difficulty", 1, true) then
                picker_dialog = widget
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_not_nil(dialog)

        dialog.buttons[1][1].callback()
        assert.is_not_nil(picker_dialog)

        local hard_button
        for _, row in ipairs(picker_dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Hard" then
                    hard_button = button
                end
            end
        end
        assert.is_not_nil(hard_button)
        hard_button.callback()
        assert.are.equal("hard", started, "new game starts at chosen difficulty")
    end)

    it("re-opens win dialog when menu is tapped on a finished board", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local view = new_view(new_game(puzzle, SOLUTION))
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title and widget.title:find("Puzzle solved", 1, true) then
                dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_not_nil(dialog)

        -- Tap menu again
        dialog = nil
        view:openMenu()
        assert.is_not_nil(dialog, "openMenu on finished board re-shows win dialog")
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
        assert_dither(bb, cell, "the pattern cell is highlighted")

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

    it("applies all candidate eliminations of a multi-elimination hint on the third tap", function()
        local NAKED_PAIR_PUZZLE = "700009030000105006400260009002083951007000000005600000000000003100000060000004010"
        local solver = require("core.solver")
        local flags = require("core.techniques.flags")
        local b = board.from_string(NAKED_PAIR_PUZZLE)
        local s = solver.new(b)
        local sol = s:solve_any().board
        local g = assert(game.new {
            puzzle = b,
            solution = sol,
            difficulty = "custom",
            custom_tier = "medium",
            custom_techniques = { "naked_pairs" },
            allowed_techniques = flags.NAKED_PAIRS,
            autofill_notes = true,
            now = now,
        })
        local view = new_view(g)

        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        local hint_res = view._hint_result
        assert.is_not_nil(hint_res)
        assert.are.equal("naked_pairs", hint_res.technique.id)
        assert.is_not_nil(hint_res.actions)
        assert.is_true(#hint_res.actions > 1)

        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage)

        tap_button(view, "tool_row", "hint")
        assert.are.equal(0, view._hint_stage)

        -- All eliminated candidate notes in hint_res.actions must be removed
        for _, act in ipairs(hint_res.actions) do
            local mask = view.game:get_notes(act.row, act.col)
            local v_bit = bit.lshift(1, act.value - 1)
            assert.are.equal(0, bit.band(mask, v_bit))
        end

        -- Single undo restores all of them
        tap_button(view, "tool_row", "undo")
        for _, act in ipairs(hint_res.actions) do
            local mask = view.game:get_notes(act.row, act.col)
            local v_bit = bit.lshift(1, act.value - 1)
            assert.are.not_equal(0, bit.band(mask, v_bit))
        end
    end)

    it("applies a multi-elimination hint cleanly when notes are off (Option 1 UX)", function()
        local NAKED_PAIR_PUZZLE = "700009030000105006400260009002083951007000000005600000000000003100000060000004010"
        local solver = require("core.solver")
        local flags = require("core.techniques.flags")
        local b = board.from_string(NAKED_PAIR_PUZZLE)
        local s = solver.new(b)
        local sol = s:solve_any().board
        local g = assert(game.new {
            puzzle = b,
            solution = sol,
            difficulty = "custom",
            custom_tier = "medium",
            custom_techniques = { "naked_pairs" },
            allowed_techniques = flags.NAKED_PAIRS,
            autofill_notes = false,
            now = now,
        })
        local view = new_view(g)

        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)

        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage)

        -- Tap 3 applies the batch elimination without error notification
        tap_button(view, "tool_row", "hint")
        assert.are.equal(0, view._hint_stage)

        -- Eliminated candidates are recorded in manual_removed and notes are materialized
        local recorded_hints = view.game:hints()
        assert.are.equal(1, #recorded_hints)
        local has_any_materialized_notes = false
        for r = 0, 8 do
            for c = 0, 8 do
                if view.game:get_notes(r, c) > 0 then
                    has_any_materialized_notes = true
                    break
                end
            end
        end
        assert.is_true(has_any_materialized_notes, "eliminated cells must have remaining notes materialized")
    end)

    it("preserves hint stage 1 when inspecting the board, switching numbers, or selecting cells", function()
        local view = new_view(new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION))

        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)

        -- Arming/switching digits on the number row preserves the hint banner
        tap_button(view, "number_row", 4)
        assert.are.equal(4, view.armed)
        assert.are.equal(1, view._hint_stage, "arming a digit must preserve stage 1")

        -- Hardware digit cycling forward and backward preserves the hint banner
        view:onDigitNext()
        assert.is_not_nil(view.armed)
        assert.are.equal(1, view._hint_stage, "cycling digits forward must preserve stage 1")

        view:onDigitPrev()
        assert.is_not_nil(view.armed)
        assert.are.equal(1, view._hint_stage, "cycling digits backward must preserve stage 1")

        -- Selecting a cell preserves the hint banner
        tap_button(view, "number_row", view.armed) -- disarm
        tap_cell(view, 0, 0)
        assert.are.equal(0, view.selected.row)
        assert.are.equal(0, view.selected.col)
        assert.are.equal(1, view._hint_stage, "selecting a cell must preserve stage 1")

        -- Toggling notes mode preserves the hint banner
        tap_button(view, "tool_row", "notes")
        assert.are.equal(1, view._hint_stage, "toggling notes mode must preserve stage 1")

        -- Tapping Hint again advances directly to stage 2
        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage, "second hint tap must advance to stage 2")
        assert.are.equal(1, #view.game:hints(), "only 1 hint recorded")

        -- Tapping Hint a third time applies the action
        tap_button(view, "tool_row", "hint")
        assert.are.equal(0, view._hint_stage)
        assert.are.equal(6, view.game:get(8, 8))
        assert.are.equal(1, #view.game:hints(), "only 1 hint recorded after applying")
    end)

    it(
        "preserves stage 2 pattern cells and banner when inspecting the board, switching numbers, or selecting cells",
        function()
            local view = new_view(new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION))

            tap_button(view, "tool_row", "hint")
            tap_button(view, "tool_row", "hint")
            assert.are.equal(2, view._hint_stage)
            assert.is_true(view._hint_cells[8 * 9 + 8], "pattern cell (8,8) is marked")

            -- Arming/switching digits preserves stage 2 and pattern cells
            tap_button(view, "number_row", 4)
            assert.are.equal(4, view.armed)
            assert.are.equal(2, view._hint_stage)
            assert.is_true(view._hint_cells[8 * 9 + 8])

            -- Hardware digit cycling forward and backward preserves stage 2 and pattern cells
            view:onDigitNext()
            assert.are.equal(2, view._hint_stage)
            assert.is_true(view._hint_cells[8 * 9 + 8])
            view:onDigitPrev()
            assert.are.equal(2, view._hint_stage)
            assert.is_true(view._hint_cells[8 * 9 + 8])

            -- Selecting a cell preserves stage 2 and pattern cells
            tap_button(view, "number_row", view.armed) -- disarm
            tap_cell(view, 0, 0)
            assert.are.equal(2, view._hint_stage)
            assert.is_true(view._hint_cells[8 * 9 + 8])

            -- Toggling notes mode preserves stage 2 and pattern cells
            tap_button(view, "tool_row", "notes")
            assert.are.equal(2, view._hint_stage)
            assert.is_true(view._hint_cells[8 * 9 + 8])

            -- Tapping Hint applies the action
            tap_button(view, "tool_row", "hint")
            assert.are.equal(0, view._hint_stage)
            assert.are.equal(6, view.game:get(8, 8))
            assert.are.equal(1, #view.game:hints())
        end
    )

    it("cancels a hint reveal on mutating actions", function()
        local view = new_view(new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local cell = layout.cell_rect(view.layout, 8, 8)

        -- Request hint on valid board up to stage 2
        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage)

        -- Check errors cancels the hint reveal and clears pattern cells
        tap_button(view, "tool_row", "check")
        assert.are.equal(0, view._hint_stage, "check cancels the reveal")
        view:paintTo(bb, 0, 0)
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(cell.x + 2, cell.y + 2).a),
            "the pattern highlight is cleared on cancel"
        )

        -- Mutating place cancels stage 1 reveal
        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        tap_button(view, "number_row", 5)
        tap_cell(view, 8, 8)
        assert.are.equal(0, view._hint_stage, "placing a number cancels the reveal")
        assert.are.equal(5, view.game:get(8, 8))

        -- Undo cancels an active hint reveal
        tap_button(view, "number_row", 5) -- disarm 5
        tap_button(view, "tool_row", "hint")
        -- Note: with 5 at (8,8), board diverges so hint fails. Let's undo first.
        tap_button(view, "tool_row", "undo") -- board back to 0 at (8,8)
        assert.are.equal(0, view.game:get(8, 8))
        assert.are.equal(0, view._hint_stage)

        -- Request hint up to stage 2, then undo cancels it
        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        tap_button(view, "tool_row", "hint")
        assert.are.equal(2, view._hint_stage)
        tap_button(view, "tool_row", "undo") -- undoes initial place
        assert.are.equal(0, view._hint_stage, "undo cancels stage 2 reveal")

        -- Redo cancels an active hint reveal
        tap_button(view, "tool_row", "hint")
        assert.are.equal(1, view._hint_stage)
        tap_button(view, "tool_row", "redo")
        assert.are.equal(0, view._hint_stage, "redo cancels stage 1 reveal")

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

    it("highlights every cell holding the selected digit, values and notes", function()
        local g = new_game(PUZZLE, SOLUTION)
        assert.is_true(g:toggle_note(0, 3, 6), "a note 6 on an empty cell")
        local view = new_view(g)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        tap_cell(view, 1, 0) -- a given 6
        view:paintTo(bb, 0, 0)
        local function match_pixel(r, c)
            local rect = layout.cell_rect(view.layout, r, c)
            return tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a)
        end
        -- the other 6 givens are highlighted
        assert_dither(bb, layout.cell_rect(view.layout, 2, 7), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 3, 4), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 5, 8), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 6, 1), "a matching 6 is dithered")
        -- the cell whose notes hold 6 is highlighted too
        assert_dither(bb, layout.cell_rect(view.layout, 0, 3), "the note 6 cell is dithered")
        -- a cell without the digit stays plain
        assert.are.equal(tonumber(theme.background.a), match_pixel(0, 0))
        -- the selected cell is inverted, not filled
        assert.are.equal(0x00, match_pixel(1, 0))
        bb:free()
    end)

    it("arms a digit and highlights every cell showing it, values and notes", function()
        local g = new_game(PUZZLE, SOLUTION)
        assert.is_true(g:toggle_note(0, 3, 6), "a note 6 on an empty cell")
        local view = new_view(g)
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        tap_button(view, "number_row", 6)
        assert.are.equal(6, view.armed)
        view:paintTo(bb, 0, 0)
        local function match_pixel(r, c)
            local rect = layout.cell_rect(view.layout, r, c)
            return tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a)
        end
        -- every 6 given is highlighted, including the one in the corner
        assert_dither(bb, layout.cell_rect(view.layout, 1, 0), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 2, 7), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 3, 4), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 5, 8), "a matching 6 is dithered")
        assert_dither(bb, layout.cell_rect(view.layout, 6, 1), "a matching 6 is dithered")
        -- the cell whose notes hold 6 is highlighted too
        assert_dither(bb, layout.cell_rect(view.layout, 0, 3), "the note 6 cell is dithered")
        -- a cell without the digit stays plain
        assert.are.equal(tonumber(theme.background.a), match_pixel(0, 0))
        -- the armed digit button inverts
        local button
        for _, b in ipairs(view.layout.number_row.buttons) do
            if b.id == 6 then
                button = b
            end
        end
        assert.are.equal(0x00, tonumber(bb:getPixel(button.x + 2, button.y + 2).a), "the armed button is inverted")
        bb:free()
    end)

    it("switches the armed digit and updates the highlight", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        tap_button(view, "number_row", 6)
        tap_button(view, "number_row", 3)
        assert.are.equal(3, view.armed)
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 2, 7) -- a 6 cell
        assert.are.equal(
            tonumber(theme.background.a),
            tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a),
            "the previous digit's highlight clears"
        )
        local rect3 = layout.cell_rect(view.layout, 0, 1) -- a 3 cell
        assert_dither(bb, rect3, "the new digit's cells are dithered")
        bb:free()
    end)

    it("disarming falls back to the cursor-driven match", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        tap_button(view, "number_row", 6)
        tap_cell(view, 0, 5) -- an empty cell: the armed 6 is placed
        tap_button(view, "number_row", 6) -- disarm
        assert.is_nil(view.armed)
        tap_cell(view, 1, 0) -- a given 6: the cursor match highlights the 6s
        view:paintTo(bb, 0, 0)
        local rect = layout.cell_rect(view.layout, 0, 5)
        assert_dither(bb, rect, "the placed 6 is dithered by the cursor match")
        bb:free()
    end)

    it("toggles the digit highlight off when the same cell is tapped again", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local rect = layout.cell_rect(view.layout, 2, 7)
        tap_cell(view, 1, 0)
        view:paintTo(bb, 0, 0)
        assert_dither(bb, rect, "the match highlight is dithered")
        tap_cell(view, 1, 0)
        view:paintTo(bb, 0, 0)
        assert.are.equal(tonumber(theme.background.a), tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a))
        bb:free()
    end)

    it("clears the digit highlight when an empty cell is selected", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        local bb = Blitbuffer.new(758, 1024)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local rect = layout.cell_rect(view.layout, 2, 7)
        tap_cell(view, 1, 0)
        tap_cell(view, 0, 3) -- an empty cell
        view:paintTo(bb, 0, 0)
        assert.are.equal(tonumber(theme.background.a), tonumber(bb:getPixel(rect.x + 2, rect.y + 2).a))
        bb:free()
    end)

    it("keeps the armed highlight in sync after undo", function()
        local view = new_view(new_game(PUZZLE, SOLUTION))
        tap_button(view, "number_row", 6) -- arm 6
        tap_cell(view, 0, 3) -- place a 6
        assert.is_not_nil(view._match_cells[0 * 9 + 3], "the placed 6 joins the armed highlight")
        tap_button(view, "tool_row", "undo")
        assert.is_nil(view._match_cells[0 * 9 + 3], "the undone 6 leaves the armed highlight")
    end)

    it("gives up: records a give-up and clears the save", function()
        local s = stats.new()
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        view:onGiveUp()
        assert.are.equal(1, #s.games)
        assert.are.equal("give_up", s.games[1].status)
        assert.is_nil(io.open(save_path, "rb"))
    end)

    it("keeps the game open when give-up statistics fail and retries", function()
        local s = stats.new()
        local g = new_game(PUZZLE, SOLUTION)
        g.id = assert(stats.reserve_id(s))
        assert.is_true(g:place(0, 2, 4))
        assert.is_true(storage.save(save_path, g:serialize()))
        local stats_save_fails = true
        local fake_storage = {
            save = function(path, data)
                if path == stats_path and stats_save_fails then
                    return nil, "stats unavailable"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(g, {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
            storage_adapter = fake_storage,
        })
        local retry_dialog
        local closed = {}
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        view:onGiveUp()
        assert.is_not_nil(retry_dialog)
        assert.are.equal(0, count_closed(closed, view))
        assert.is_true(storage.exists(save_path))

        stats_save_fails = false
        retry_dialog.ok_callback()
        assert.are.equal(1, count_closed(closed, view))
        assert.is_false(storage.exists(save_path))
        assert.are.equal("give_up", s.games[1].status)
    end)

    it("quits: pauses the timer and saves the game for later", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g, { save_path = save_path })
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        view:onClose()
        local data = storage.load(save_path)
        assert.is_not_nil(data)
        local restored, err = game.restore(data, { now = now })
        assert.is_not_nil(restored, err)
        assert.are.equal(2, restored:get(0, 3))
        assert.is_false(restored.timer.running)
    end)

    it("waits for Retry or Discard when the pause checkpoint fails", function()
        local save_fails = true
        local fake_storage = {
            save = function(path, data)
                if save_fails then
                    return nil, "pause write failed"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            save_path = save_path,
            storage_adapter = fake_storage,
        })
        local retry_dialog, menu_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            elseif widget and widget.buttons then
                menu_dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
        end)

        view:openMenu()
        assert.is_not_nil(retry_dialog)
        assert.is_nil(menu_dialog, "the pause menu waits for the checkpoint decision")
        assert.is_false(view.game.timer.running)

        save_fails = false
        retry_dialog.ok_callback()
        assert.is_not_nil(menu_dialog)
        assert.is_not_nil(storage.load(save_path))

        retry_dialog = nil
        menu_dialog = nil
        save_fails = true
        view:openMenu()
        assert.is_not_nil(retry_dialog)
        retry_dialog.cancel_callback()
        assert.is_not_nil(menu_dialog, "Discard explicitly continues to the pause menu")
    end)

    it("checkpoints game and stats idempotently on FlushSettings", function()
        local Event = require("ui/event")
        local s = stats.new()
        local g = new_game(PUZZLE, SOLUTION)
        g.id = assert(stats.reserve_id(s))
        local view = new_view(g, {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)

        view:handleEvent(Event:new("FlushSettings"))
        view:handleEvent(Event:new("FlushSettings"))

        local saved_game = assert(storage.load(save_path))
        local saved_stats = assert(storage.load(stats_path))
        assert.is_true(view.game.timer.running, "a standalone flush resumes the active view after checkpointing")
        assert.is_false(saved_game.timer.running, "the durable timer snapshot remains paused")
        assert.are.equal("2", saved_game.board:sub(4, 4))
        assert.are.equal(1, #saved_stats.games)
        assert.are.equal("in_progress", saved_stats.games[1].status)
        assert.are.equal(2, saved_stats.next_id)
    end)

    it("keeps a failed FlushSettings checkpoint pending until Retry or Discard", function()
        local Event = require("ui/event")
        local save_fails = true
        local fake_storage = {
            save = function(path, data)
                if save_fails then
                    return nil, "flush write failed"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            save_path = save_path,
            storage_adapter = fake_storage,
        })
        local retry_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
        end)

        view:handleEvent(Event:new("FlushSettings"))
        assert.is_not_nil(retry_dialog)
        assert.is_false(view.game.timer.running)
        assert.is_not_nil(view._pending_persistence)

        retry_dialog.cancel_callback()
        assert.is_nil(view._pending_persistence)
        assert.is_true(view.game.timer.running, "Discard resumes the still-active game")
    end)

    it("does not add an unstarted game to the log when checkpointing", function()
        local s = stats.new()
        local g = new_game(PUZZLE, SOLUTION)
        g.id = assert(stats.reserve_id(s))
        local view = new_view(g, {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
        })

        assert.is_true(view:checkpoint("test"))
        local saved_stats = assert(storage.load(stats_path))
        assert.are.equal(0, #saved_stats.games)
        assert.are.equal(2, saved_stats.next_id, "the unstarted game's id reservation is durable")
    end)

    it("keeps the view open after a quit save failure and retries explicitly", function()
        local save_fails = true
        local fake_storage = {
            save = function(path, data)
                if path == save_path and save_fails then
                    return nil, "disk full"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            save_path = save_path,
            storage_adapter = fake_storage,
        })
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)

        local retry_dialog
        local closed = {}
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        view:onQuit()
        assert.is_not_nil(retry_dialog)
        assert.are.equal(0, count_closed(closed, view), "failed persistence must keep the game view open")
        assert.is_nil(storage.load(save_path))

        save_fails = false
        retry_dialog.ok_callback()
        assert.are.equal(1, count_closed(closed, view))
        assert.is_not_nil(storage.load(save_path))
    end)

    it("defers a suspend save failure and surfaces it on resume", function()
        local save_fails = true
        local fake_storage = {
            save = function(path, data)
                if save_fails then
                    return nil, "read-only filesystem"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            save_path = save_path,
            storage_adapter = fake_storage,
        })
        local retry_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
        end)

        view:onSuspend()
        assert.is_nil(retry_dialog, "suspend must not block on a modal dialog")
        view:onResume()
        assert.is_not_nil(retry_dialog, "resume surfaces the pending persistence failure")
        assert.is_false(view.game.timer.running)

        save_fails = false
        retry_dialog.ok_callback()
        assert.is_true(view.game.timer.running)
        assert.is_not_nil(storage.load(save_path))
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

    it("auto-saves the paused game on suspend", function()
        local view = new_view(new_game(PUZZLE, SOLUTION), { save_path = save_path })
        tap_button(view, "number_row", 2)
        tap_cell(view, 0, 3)
        view:onSuspend()
        local data = storage.load(save_path)
        assert.is_not_nil(data, "suspend must persist the game")
        local restored, err = game.restore(data, { now = now })
        assert.is_not_nil(restored, err)
        assert.are.equal(2, restored:get(0, 3))
        assert.is_false(restored.timer.running, "the suspended game is saved paused")
    end)

    it("does not re-save a finished game on suspend", function()
        local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
        local s = stats.new()
        local view = new_view(new_game(puzzle, SOLUTION), {
            save_path = save_path,
            stats = s,
            stats_path = stats_path,
        })
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function() end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        tap_button(view, "number_row", solution_cell(0, 3))
        tap_cell(view, 0, 3)
        tap_button(view, "number_row", solution_cell(8, 0))
        tap_cell(view, 8, 0)
        assert.is_true(view.game:is_finished())
        assert.is_nil(io.open(save_path, "rb"), "winning deletes the save file")

        -- Suspend the device while on the win screen
        view:onSuspend()
        assert.is_nil(io.open(save_path, "rb"), "suspend must not recreate the save file for a finished game")
        assert.is_nil(storage.load(save_path))
    end)

    it("resumes the timer when the pause menu is dismissed by tapping outside", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            dialog = widget
        end
        view:openMenu()
        UIManager.show = original_show
        assert.is_not_nil(dialog, "the pause menu must be shown")
        assert.is_false(g.timer.running)
        local Geom = require("ui/geometry")
        dialog:onTapClose({}, { pos = Geom:new { x = -100, y = -100 } })
        assert.is_false(view.menu_open)
        assert.is_true(g.timer.running, "the timer must resume after an outside tap")
    end)

    it("shows the hint count and resume/statistics in the pause menu", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                dialog = widget
            end
        end
        view:openMenu()
        UIManager.show = original_show
        assert.is_not_nil(dialog)
        assert.is_true(dialog.title:find("Hints: 0", 1, true) ~= nil, "the pause menu shows the hint count")

        dialog.buttons[1][1].callback()
        assert.is_true(g.timer.running, "the Resume button resumes the timer")
    end)

    it("names the difficulty in the pause menu title", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                dialog = widget
            end
        end
        view:openMenu()
        UIManager.show = original_show
        assert.is_not_nil(dialog)
        assert.is_true(dialog.title:find("Easy", 1, true) ~= nil, "the pause menu title names the difficulty")
    end)

    it("opens a difficulty picker from New game and starts a game with the chosen difficulty", function()
        local started
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            new_game_cb = function(difficulty)
                started = difficulty
            end,
        })
        local dialog
        local picker_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        local closed = {}
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                if not dialog then
                    dialog = widget
                else
                    picker_dialog = widget
                end
            end
        end
        UIManager.close = function(_, widget)
            closed[#closed + 1] = widget
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)
        view:openMenu()
        assert.is_not_nil(dialog)
        local new_game_button
        for _, row in ipairs(dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "New game" then
                    new_game_button = button
                end
            end
        end
        assert.is_not_nil(new_game_button, "the pause menu offers a new game")
        new_game_button.callback()
        assert.is_not_nil(picker_dialog, "tapping New game opens difficulty picker")
        assert.are.equal(dialog, closed[1], "the pause dialog is closed before showing picker")

        -- Test cancelling the picker resumes the game
        local cancel_button
        for _, row in ipairs(picker_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Cancel" then
                    cancel_button = btn
                end
            end
        end
        assert.is_not_nil(cancel_button)
        cancel_button.callback()
        assert.is_false(view.menu_open, "cancelling difficulty picker unpauses")
        assert.is_true(view.game.timer.running)

        -- Test tap_close_callback on picker
        view:openMenu()
        new_game_button.callback()
        picker_dialog.tap_close_callback()
        assert.is_false(view.menu_open)
        assert.is_true(view.game.timer.running)

        -- Select "Hard"
        view:openMenu()
        new_game_button.callback()
        local hard_button
        for _, row in ipairs(picker_dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Hard" then
                    hard_button = button
                end
            end
        end
        assert.is_not_nil(hard_button, "picker offers Hard difficulty")
        hard_button.callback()

        assert.are.equal("hard", started, "new game starts at chosen difficulty")
        assert.are.equal(0, count_closed(closed, view), "the old view remains until replacement succeeds")
    end)

    it("opens a custom difficulty picker from New game and starts a custom game", function()
        local started_diff, started_opts
        local view = new_view(new_game(PUZZLE, SOLUTION), {
            new_game_cb = function(diff, opts)
                started_diff = diff
                started_opts = opts
            end,
        })
        local dialog, picker_dialog, tier_dialog, strat_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons and widget.title then
                if widget.title:find("Mistakes", 1, true) then
                    dialog = widget
                elseif widget.title:find("Choose difficulty", 1, true) then
                    picker_dialog = widget
                elseif widget.title:find("Strategy tier", 1, true) then
                    tier_dialog = widget
                elseif widget.title:find("Strategies", 1, true) then
                    strat_dialog = widget
                end
            end
        end
        UIManager.close = function() end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)

        view:openMenu()
        assert.is_not_nil(dialog)
        local new_game_button
        for _, row in ipairs(dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "New game" then
                    new_game_button = btn
                end
            end
        end
        assert.is_not_nil(new_game_button)
        new_game_button.callback()
        assert.is_not_nil(picker_dialog)

        local custom_btn
        for _, row in ipairs(picker_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Custom…" then
                    custom_btn = btn
                end
            end
        end
        assert.is_not_nil(custom_btn)
        custom_btn.callback()
        assert.is_not_nil(tier_dialog)

        local expert_btn
        for _, row in ipairs(tier_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Expert" then
                    expert_btn = btn
                end
            end
        end
        assert.is_not_nil(expert_btn)
        expert_btn.callback()
        assert.is_not_nil(strat_dialog)

        local gen_btn
        for _, row in ipairs(strat_dialog.buttons) do
            for _, btn in ipairs(row) do
                if btn.text == "Generate" then
                    gen_btn = btn
                end
            end
        end
        assert.is_not_nil(gen_btn)
        gen_btn.callback()

        assert.are.equal("custom", started_diff)
        assert.are.equal("expert", started_opts.target_tier)
        assert.is_true(#started_opts.required_techniques > 0)
    end)

    it("displays formatted custom tier name in pause menu title", function()
        local g = new_game(PUZZLE, SOLUTION)
        g._difficulty = "custom"
        g.custom_tier = "master"
        local view = new_view(g)
        local dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                dialog = widget
            end
        end
        view:openMenu()
        UIManager.show = original_show
        assert.is_not_nil(dialog)
        assert.is_true(dialog.title:find("Custom (Master)", 1, true) ~= nil, "pause title includes custom tier")
    end)

    it("resets puzzle after confirmation and assigns a fresh game id", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        local g = new_game(PUZZLE, SOLUTION, function()
            return 1000
        end)
        g.id = id
        local view = new_view(g, {
            stats = s,
        })

        assert.is_true(g:place(0, 2, 4))
        assert.is_true(g:toggle_note(0, 3, 2))
        view:afterMove()
        assert.are.equal(1, #s.games, "initial moves tracked in stats")
        assert.are.equal("in_progress", s.games[1].status)

        local dialog
        local confirm_box
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                dialog = widget
            elseif widget and widget.ok_callback then
                confirm_box = widget
            end
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)
        view:openMenu()
        assert.is_not_nil(dialog)

        local reset_button
        for _, row in ipairs(dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Reset puzzle" then
                    reset_button = button
                end
            end
        end
        assert.is_not_nil(reset_button, "the pause menu offers reset puzzle")
        reset_button.callback()
        assert.is_not_nil(confirm_box, "tapping Reset puzzle opens confirmation dialog")

        -- Confirm reset
        confirm_box.ok_callback()

        assert.are.equal(0, g:get(0, 2), "board is reverted")
        assert.are.equal(0, g:get_notes(0, 3), "notes are cleared")
        assert.are.equal(0, g:elapsed(), "timer is reset")
        assert.is_false(view.menu_open, "menu is closed")
        assert.is_true(g.timer.running, "timer resumes after reset")
        assert.are.equal(0, #s.games, "in-progress stats record was dropped")

        -- Subsequent move creates a fresh in-progress entry with new id and started_at
        assert.is_true(g:place(0, 2, 4))
        view:afterMove()
        assert.are.equal(1, #s.games)
        assert.are.equal(g.id, s.games[1].id)
        assert.are.equal(clock.value, s.games[1].started_at)
    end)

    it("keeps the original game intact when reset persistence fails and retries", function()
        local s = stats.new()
        local old_id = assert(stats.reserve_id(s))
        local g = new_game(PUZZLE, SOLUTION)
        g.id = old_id
        assert.is_true(g:place(0, 2, 4))
        local failed_path
        local fake_storage = {
            save = function(path, data)
                if path == failed_path then
                    return nil, "reset write failed"
                end
                return storage.save(path, data)
            end,
            delete = storage.delete,
            exists = storage.exists,
        }
        local view = new_view(g, {
            stats = s,
            save_path = save_path,
            stats_path = stats_path,
            storage_adapter = fake_storage,
        })
        view:afterMove()
        assert.is_true(storage.save(save_path, g:serialize()))

        local menu_dialog, reset_dialog, retry_dialog
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            if widget and widget.ok_text == "Reset" then
                reset_dialog = widget
            elseif widget and widget.ok_text == "Retry" then
                retry_dialog = widget
            elseif widget and widget.buttons then
                menu_dialog = widget
            end
        end
        finally(function()
            UIManager.show = original_show
        end)

        view:openMenu()
        local reset_button
        for _, row in ipairs(menu_dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Reset puzzle" then
                    reset_button = button
                end
            end
        end
        reset_button.callback()
        failed_path = stats_path
        reset_dialog.ok_callback()

        assert.is_not_nil(retry_dialog)
        assert.are.equal(4, g:get(0, 2), "failed reset leaves the live board unchanged")
        assert.are.equal(old_id, g.id)
        assert.are.equal("4", assert(storage.load(save_path)).board:sub(3, 3))

        local stats_retry_dialog = retry_dialog
        failed_path = save_path
        stats_retry_dialog.ok_callback()
        assert.are_not.equal(stats_retry_dialog, retry_dialog)
        assert.are.equal(4, g:get(0, 2), "a failed reset-game write also leaves the board unchanged")
        assert.are.equal(old_id, g.id)

        failed_path = nil
        retry_dialog.ok_callback()
        assert.are.equal(0, g:get(0, 2))
        assert.is_true(g.id > old_id)
        assert.are.equal("0", assert(storage.load(save_path)).board:sub(3, 3))
        assert.are.equal(0, #s.games)
    end)

    it("fills all notes from the pause menu and handles errors", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        assert.are.equal(0, g:get_notes(0, 2))

        local dialog
        local notified
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                dialog = widget
            elseif widget and widget.text then
                notified = widget.text
            end
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)
        view:openMenu()
        assert.is_not_nil(dialog)

        local fill_notes_button
        for _, row in ipairs(dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Fill all notes" then
                    fill_notes_button = button
                end
            end
        end
        assert.is_not_nil(fill_notes_button, "the pause menu offers fill all notes")
        fill_notes_button.callback()

        assert.is_true(g:get_notes(0, 2) > 0, "notes are populated")
        assert.is_false(view.menu_open, "menu is closed")
        assert.is_true(g:can_undo(), "fill all notes is undoable")
        assert.is_true(g:undo())
        assert.are.equal(0, g:get_notes(0, 2), "undo reverts notes")

        -- Test error notification when board has conflicts
        assert.is_true(g:place(0, 2, 5)) -- conflict with given 5 at (0,0)
        view:openMenu()
        fill_notes_button.callback()
        assert.is_not_nil(notified, "shows notification on conflict")
        assert.is_false(view.menu_open, "menu closes gracefully on error")
    end)

    it("prompts confirmation before giving up", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        local dialog
        local confirm_box
        local UIManager = require("ui/uimanager")
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget)
            if widget and widget.buttons then
                dialog = widget
            elseif widget and widget.ok_callback then
                confirm_box = widget
            end
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)
        view:openMenu()
        assert.is_not_nil(dialog)

        local give_up_button
        for _, row in ipairs(dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Give up" then
                    give_up_button = button
                end
            end
        end
        assert.is_not_nil(give_up_button, "the pause menu offers give up")
        give_up_button.callback()
        assert.is_not_nil(confirm_box, "tapping Give up opens confirmation dialog")

        -- Test cancel
        confirm_box.cancel_callback()
        assert.is_false(g:is_finished(), "cancelling does not give up")
        assert.is_false(view.menu_open, "menu is closed")
        assert.is_true(g.timer.running, "timer resumes after cancel")

        -- Test confirm give up
        view:openMenu()
        give_up_button.callback()
        confirm_box.ok_callback()
        assert.is_true(g:is_finished(), "confirming finishes the game as give up")
    end)

    it("opens the statistics screen from the pause menu", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        local UIManager = require("ui/uimanager")
        local dialog
        local shown, refreshtype
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget, mode)
            if widget and widget.buttons then
                dialog = widget
            elseif widget and widget.item_table then
                shown = widget
                refreshtype = mode
            end
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)
        view:openMenu()
        assert.is_not_nil(dialog)
        dialog.buttons[1][2].callback()
        assert.is_not_nil(shown, "Statistics must open the stats view")
        assert.is_not_nil(shown.item_table, "the stats dashboard is a menu")
        assert.are.equal("full", refreshtype, "the stats page must refresh the whole screen")
    end)

    it("opens the help menu from the pause menu", function()
        local g = new_game(PUZZLE, SOLUTION)
        local view = new_view(g)
        local UIManager = require("ui/uimanager")
        local dialog
        local shown, refreshtype
        local original_show = UIManager.show
        local original_close = UIManager.close
        UIManager.show = function(_, widget, mode)
            if widget and widget.buttons then
                dialog = widget
            elseif widget and widget.item_table then
                shown = widget
                refreshtype = mode
            end
        end
        finally(function()
            UIManager.show = original_show
            UIManager.close = original_close
        end)
        view:openMenu()
        assert.is_not_nil(dialog)
        local help_button
        for _, row in ipairs(dialog.buttons) do
            for _, button in ipairs(row) do
                if button.text == "Help" then
                    help_button = button
                end
            end
        end
        assert.is_not_nil(help_button, "pause menu offers Help")
        help_button.callback()
        assert.is_not_nil(shown, "Help must open the help menu")
        assert.is_not_nil(shown.item_table, "the help widget is a menu")
        assert.are.equal("full", refreshtype, "the help page must refresh the whole screen")
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
                if call.region and call.region.y == view.layout.tool_row.y then
                    return call
                end
            end
            return nil
        end

        local function rect_key(rect)
            return rect.x .. "," .. rect.y .. "," .. rect.w .. "," .. rect.h
        end

        -- The set of refreshed region keys, without the bar strips.
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

        -- The single cell region of a frame (all dirty cells coalesce into
        -- one bounding-box update), or nil when no cell is dirty.
        local function grid_region(view)
            local grid_bottom = view.layout.grid.y + view.layout.grid.h
            for _, call in ipairs(calls) do
                if call.region and call.region.y < grid_bottom then
                    return call.region
                end
            end
            return nil
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

        it("refreshes only the selected cell on selection of an empty cell", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 3) -- an empty cell: no digit to highlight
            local call = last_call()
            assert.are.equal("ui", call.mode)
            assert_rect(call.region, layout.cell_rect(view.layout, 0, 3))
        end)

        it("refreshes the old and new cell in one bounding-box region when the selection moves", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 3) -- both cells empty: no digit highlight involved
            calls = {}
            tap_cell(view, 0, 5)
            assert.are.equal(1, #calls, "one refresh region per interaction, never per cell")
            local expected = layout.cells_region(view.layout, { [0 * 9 + 3] = true, [0 * 9 + 5] = true })
            assert_rect(last_call().region, expected)
        end)

        it("refreshes all matching cells in one region when a digit cell is selected", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 1, 0) -- a given 6: the match highlight turns on
            assert.are.equal(1, #calls, "a single region covers the whole match highlight")
            local expected = layout.cells_region(view.layout, {
                [1 * 9 + 0] = true,
                [2 * 9 + 7] = true,
                [3 * 9 + 4] = true,
                [5 * 9 + 8] = true,
                [6 * 9 + 1] = true,
            })
            assert_rect(last_call().region, expected)
        end)

        it("refreshes the number row and the matching cells in one region when a digit is armed", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_button(view, "number_row", 3)
            assert.are.equal(2, #calls, "one region for the cells, one for the number row")
            local expected = layout.cells_region(view.layout, {
                [0 * 9 + 1] = true,
                [3 * 9 + 8] = true,
                [4 * 9 + 5] = true,
            })
            assert_rect(grid_region(view), expected)
            local number_call
            for _, c in ipairs(calls) do
                if c.region and c.region.y == view.layout.number_row.y then
                    number_call = c
                end
            end
            assert.is_not_nil(number_call, "the number row refreshes when arming")
            assert.are.equal("ui", number_call.mode)
        end)

        it("repaints the previously selected cell when a digit is armed", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_cell(view, 0, 1) -- select a given 3
            calls = {}
            tap_button(view, "number_row", 3)
            local set = grid_region_set(view)
            assert.is_not_nil(set[rect_key(layout.cell_rect(view.layout, 0, 1))], "the unselected cell repaints")
        end)

        it("refreshes the number row when a digit becomes fully placed", function()
            -- Blank one 5: placing it back completes digit 5, which must
            -- repaint the number row (the button greys out).
            local r, c = first_cell_with(5)
            local view = new_view(new_game(blank_solution({ { r, c } }), SOLUTION))
            paint_view(view)
            calls = {}
            tap_button(view, "number_row", 5)
            tap_cell(view, r, c)
            local number_call
            for _, call in ipairs(calls) do
                if call.region and call.region.y == view.layout.number_row.y then
                    number_call = call
                end
            end
            assert.is_not_nil(number_call, "the number row must refresh when a digit completes")
            assert.are.equal("ui", number_call.mode)
        end)

        it("refreshes the affected cells in one region when placing a digit", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_button(view, "number_row", 3) -- arm 3
            calls = {}
            tap_cell(view, 0, 5)
            -- 3 sits at (0,1) in the row and (4,5) in the column: the target
            -- cell and both peers refresh as one bounding-box update.
            local expected = layout.cells_region(view.layout, {
                [0 * 9 + 5] = true,
                [0 * 9 + 1] = true,
                [4 * 9 + 5] = true,
            })
            assert_rect(grid_region(view), expected)
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
            tap_button(view, "number_row", 3) -- arm 3
            tap_cell(view, 0, 5) -- first move enables undo
            tap_button(view, "number_row", 4) -- switch to 4: arming, no undo change
            calls = {}
            tap_cell(view, 0, 5) -- replace 3 with 4: (0,5), (0,1), (4,5) refresh
            -- the second move replaces 3 with 4: (0,5), (0,1) and (4,5) (peers
            -- holding the replaced 3, whose conflicts disappear) refresh
            local expected = layout.cells_region(view.layout, {
                [0 * 9 + 5] = true,
                [0 * 9 + 1] = true,
                [4 * 9 + 5] = true,
            })
            assert_rect(grid_region(view), expected, "the replaced cell and its conflict peers refresh")
            assert.is_nil(last_tool_call(view), "tool row must not refresh on the second move")
        end)

        it("refreshes the cells an undo or redo can affect in one region", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_button(view, "number_row", 2) -- arm 2
            tap_cell(view, 0, 6) -- (6,6) holds 2
            calls = {}
            tap_button(view, "tool_row", "undo")
            local expected = layout.cells_region(view.layout, { [0 * 9 + 6] = true, [6 * 9 + 6] = true })
            assert_rect(grid_region(view), expected)
            assert.is_not_nil(last_tool_call(view), "undo/redo state changed")
            calls = {}
            tap_button(view, "tool_row", "redo")
            assert_rect(grid_region(view), expected)
            assert.is_not_nil(last_tool_call(view))
        end)

        it("refreshes only the newly revealed cells on check", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            paint_view(view)
            tap_button(view, "number_row", 2) -- arm 2
            tap_cell(view, 0, 3) -- (0,3) is wrong: solution digit is 6
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
            local dialog
            local original_show = UIManager.show
            UIManager.show = function(_, widget)
                dialog = widget
            end
            view:openMenu()
            UIManager.show = original_show
            calls = {}
            local Geom = require("ui/geometry")
            dialog:onTapClose({}, { pos = Geom:new { x = -100, y = -100 } })
            local coarse
            for _, call in ipairs(calls) do
                if call.mode == "ui" and call.region == nil then
                    coarse = call
                end
            end
            assert.is_not_nil(coarse, "closing the pause menu must issue a coarse ui refresh")
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
            assert.are.equal("hold", view.ges_events.Hold[1].ges)
            assert.are.equal(1000, view.ges_events.Hold[1].range.w)
            assert.are.equal(1200, view.ges_events.Hold[1].range.h)
            assert.are.equal("full", last_call().mode)
        end)

        it("caches conflicts scan across repaints until board mutation occurs (UI-3)", function()
            local g = new_game(PUZZLE, SOLUTION)
            local view = new_view(g)

            local conflicts_count = 0
            local orig_conflicts = g.conflicts
            g.conflicts = function(self_g)
                conflicts_count = conflicts_count + 1
                return orig_conflicts(self_g)
            end

            -- 1. Initial paint calculates conflicts (count = 1)
            paint_view(view)
            assert.are.equal(1, conflicts_count, "initial paint must scan conflicts once")

            -- 2. Non-mutating UI interactions (repaints, selecting cell, arming digit, notes toggle)
            -- must NOT re-scan conflicts
            paint_view(view)
            tap_cell(view, 0, 2)
            paint_view(view)
            tap_button(view, "number_row", 2) -- arm digit 2
            paint_view(view)
            tap_button(view, "number_row", 2) -- disarm digit 2
            paint_view(view)
            tap_button(view, "tool_row", "notes")
            paint_view(view)
            tap_button(view, "tool_row", "notes")
            paint_view(view)
            assert.are.equal(1, conflicts_count, "non-mutating UI interactions must reuse cached conflicts")

            -- 3. Placing conflicting digit 5 at empty cell (0,3) mutates board revision
            -- (conflicting with given '5' at (0,0)).
            local ok, place_err = g:place(0, 3, 5)
            assert.is_true(ok, place_err)
            assert.are.equal(1, g:revision(), "place must mutate board revision")
            assert.are.equal(1, conflicts_count, "placement must defer conflict scan until paint")

            paint_view(view)
            assert.are.equal(2, conflicts_count, "paint after board placement must refresh conflicts")

            -- 4. Verify conflict cell background fill was rendered into blitbuffer
            local rect_0_0 = layout.cell_rect(view.layout, 0, 0)
            local rect_0_3 = layout.cell_rect(view.layout, 0, 3)
            local bb = Blitbuffer.new(758, 1024, Blitbuffer.TYPE_BB8)
            view:paintTo(bb, 0, 0)
            assert.are.equal(
                tonumber(theme.wrong_fill.a),
                tonumber(bb:getPixel(rect_0_0.x + 2, rect_0_0.y + 2).a),
                "conflict cell (0,0) must render wrong_fill background"
            )
            assert.are.equal(
                tonumber(theme.wrong_fill.a),
                tonumber(bb:getPixel(rect_0_3.x + 2, rect_0_3.y + 2).a),
                "conflict cell (0,3) must render wrong_fill background"
            )
            bb:free()
        end)
    end)

    describe("hardware key support", function()
        local Event
        local Key
        local scheduled
        local original_schedule_in

        local function press_key(view, name)
            view:handleEvent(Event:new("KeyPress", Key:new(name, {})))
        end

        local function release_key(view, name)
            view:handleEvent(Event:new("KeyRelease", Key:new(name, {})))
        end

        local function repeat_key(view, name)
            view:handleEvent(Event:new("KeyRepeat", Key:new(name, {})))
        end

        setup(function()
            Event = require("ui/event")
            Key = require("device/key")
        end)

        -- Captures UIManager:scheduleIn instead of waiting on the real clock,
        -- and always restores it (also when an assertion fails).
        before_each(function()
            local UIManager = require("ui/uimanager")
            original_schedule_in = UIManager.scheduleIn
            scheduled = {}
            UIManager.scheduleIn = function(_, seconds, action)
                table.insert(scheduled, { seconds = seconds, action = action })
            end
        end)

        after_each(function()
            local UIManager = require("ui/uimanager")
            UIManager.scheduleIn = original_schedule_in
        end)

        it("arms digit 1 with the first page-turn key press", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, view.armed)
            assert.are.equal(0, view.game:revision(), "cycling never mutates the board")
        end)

        it("iterates the armed digit forward and wraps from 9 to 1", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "RPgFwd")
            assert.are.equal(1, view.armed)
            press_key(view, "LPgFwd")
            assert.are.equal(2, view.armed)
            press_key(view, "Down")
            assert.are.equal(3, view.armed, "Down advances too")
            press_key(view, "Right")
            assert.are.equal(4, view.armed, "Right advances too")
            press_key(view, "LPgFwd")
            assert.are.equal(5, view.armed)
            press_key(view, "LPgFwd")
            assert.are.equal(6, view.armed)
            press_key(view, "LPgFwd")
            assert.are.equal(7, view.armed)
            press_key(view, "LPgFwd")
            assert.are.equal(8, view.armed)
            press_key(view, "LPgFwd")
            assert.are.equal(9, view.armed)
            press_key(view, "LPgFwd")
            assert.are.equal(1, view.armed, "forward cycles wrap from 9 back to 1")
        end)

        it("iterates the armed digit backward and wraps from 1 to 9", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "RPgBack")
            assert.are.equal(9, view.armed, "a backward press arms 9 when nothing is armed")
            press_key(view, "LPgBack")
            assert.are.equal(8, view.armed)
            press_key(view, "Up")
            assert.are.equal(7, view.armed, "Up goes backward too")
            press_key(view, "Left")
            assert.are.equal(6, view.armed, "Left goes backward too")
            press_key(view, "RPgBack")
            assert.are.equal(5, view.armed)
            press_key(view, "RPgBack")
            assert.are.equal(4, view.armed)
            press_key(view, "RPgBack")
            assert.are.equal(3, view.armed)
            press_key(view, "RPgBack")
            assert.are.equal(2, view.armed)
            press_key(view, "RPgBack")
            assert.are.equal(1, view.armed)
            press_key(view, "RPgBack")
            assert.are.equal(9, view.armed, "backward cycles wrap from 1 back to 9")
        end)

        it("continues from the current digit when switching direction", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            press_key(view, "LPgFwd")
            press_key(view, "LPgFwd")
            assert.are.equal(3, view.armed)
            press_key(view, "RPgBack")
            assert.are.equal(2, view.armed, "backward from an armed digit goes to the previous")
            press_key(view, "LPgFwd")
            assert.are.equal(3, view.armed, "forward resumes from the current digit")
        end)

        it("places the key-armed digit on a tapped cell", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            press_key(view, "LPgFwd")
            assert.are.equal(2, view.armed)
            tap_cell(view, 0, 3)
            assert.are.equal(2, view.game:get(0, 3))
            assert.are.equal(2, view.armed, "the digit stays armed after placing")
        end)

        it("writes a note with the key-armed digit in notes mode", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            tap_button(view, "tool_row", "notes")
            local value = solution_cell(0, 3)
            for _ = 1, value do
                press_key(view, "LPgFwd")
            end
            assert.are.equal(value, view.armed)
            tap_cell(view, 0, 3)
            assert.is_true(bit.band(view.game:get_notes(0, 3), bit.lshift(1, value - 1)) ~= 0)
        end)

        it("does not advance the digit on key repeats", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            repeat_key(view, "LPgFwd")
            repeat_key(view, "LPgFwd")
            assert.are.equal(1, view.armed, "auto-repeat must not cycle the digit")
            press_key(view, "RPgBack")
            repeat_key(view, "RPgBack")
            assert.are.equal(9, view.armed, "auto-repeat must not cycle backward either")
        end)

        it("toggles notes mode when a backward key is held past the delay", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "RPgBack")
            assert.are.equal(9, view.armed)
            scheduled[1].action()
            assert.is_true(view.notes_mode, "a backward hold toggles notes too")
        end)

        it("cancels the notes toggle when a backward key is released before the hold delay", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "RPgBack")
            release_key(view, "RPgBack")
            scheduled[1].action()
            assert.is_false(view.notes_mode)
        end)

        it("cancels the notes toggle when the key is released before the hold delay", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled, "a press schedules the hold check")
            release_key(view, "LPgFwd")
            scheduled[1].action()
            assert.is_false(view.notes_mode, "release before the delay cancels the hold")
        end)

        it("toggles notes mode when a cycling key is held past the delay", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            scheduled[1].action()
            assert.is_true(view.notes_mode, "hold past the delay enables notes")
            press_key(view, "LPgFwd")
            assert.are.equal(2, view.armed)
            scheduled[2].action()
            assert.is_false(view.notes_mode, "a second hold disables notes again")
        end)

        it("invalidates a stale hold when the key is pressed again", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd") -- hold candidate 1
            release_key(view, "LPgFwd")
            press_key(view, "LPgFwd") -- hold candidate 2
            scheduled[1].action() -- the stale candidate must be inert
            assert.is_false(view.notes_mode)
            scheduled[2].action()
            assert.is_true(view.notes_mode, "the fresh hold still toggles")
        end)

        it("toggles notes mode only for cycling keys", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            release_key(view, "SomeOtherKey")
            scheduled[1].action()
            assert.is_true(view.notes_mode, "a foreign key release must not cancel the hold")
        end)

        it("does not cycle the digit or arm a hold while the pause menu is open", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            view.menu_open = true
            press_key(view, "LPgFwd")
            assert.is_nil(view.armed, "key presses must not leak into the paused game")
            assert.are.equal(0, #scheduled, "no hold may be armed while paused")
        end)

        it("does not cycle the digit while the game is finished", function()
            local g = new_game(PUZZLE, SOLUTION)
            local view = new_view(g)
            g.is_finished = function()
                return true
            end
            press_key(view, "LPgFwd")
            assert.is_nil(view.armed, "key presses must not leak into a finished game")
            assert.are.equal(0, #scheduled)
        end)

        it("invalidates a pending notes hold when the pause menu opens", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled)
            local dialog
            local UIManager = require("ui/uimanager")
            local original_show = UIManager.show
            UIManager.show = function(_, widget)
                dialog = widget
            end
            view:openMenu()
            UIManager.show = original_show
            assert.is_not_nil(dialog)
            scheduled[1].action()
            assert.is_false(view.notes_mode, "the hold must not fire behind the menu")
        end)

        it("invalidates a pending notes hold on suspend", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled)
            view:onSuspend()
            scheduled[1].action()
            assert.is_false(view.notes_mode, "the hold must not fire after suspend")
        end)

        it("keeps the hold of a key pressed while another cycling key is released", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            press_key(view, "RPgFwd")
            assert.are.equal(2, view.armed)
            release_key(view, "LPgFwd")
            scheduled[2].action()
            assert.is_true(view.notes_mode, "releasing the other key must not cancel the hold")
        end)

        it("does not fire the pending hold after the game is finished", function()
            local g = new_game(PUZZLE, SOLUTION)
            local view = new_view(g)
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled)
            g.is_finished = function()
                return true
            end
            scheduled[1].action()
            assert.is_false(view.notes_mode, "the hold must not fire on a finished game")
        end)

        it("invalidates a pending notes hold when the game is won", function()
            local puzzle = blank_solution({ { 0, 3 }, { 8, 0 } })
            local view = new_view(new_game(puzzle, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled)
            tap_button(view, "number_row", solution_cell(0, 3))
            tap_cell(view, 0, 3)
            tap_button(view, "number_row", solution_cell(8, 0))
            tap_cell(view, 8, 0)
            assert.is_true(view.game:is_finished())
            scheduled[1].action()
            assert.is_false(view.notes_mode, "the hold must not fire behind the win dialog")
        end)

        it("invalidates a pending notes hold when the game is given up", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled)
            view:onGiveUp()
            scheduled[1].action()
            assert.is_false(view.notes_mode, "the hold must not fire after giving up")
        end)

        it("invalidates a pending notes hold on quit", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(1, #scheduled)
            view:onClose()
            scheduled[1].action()
            assert.is_false(view.notes_mode, "the hold must not fire after quitting")
        end)

        it("does not crash on key release and repeat payloads without a key", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            view:handleEvent(Event:new("KeyRelease"))
            view:handleEvent(Event:new("KeyRepeat"))
            assert.is_nil(view.armed)
        end)

        it("does not consume or cancel a hold on keyless releases", function()
            local view = new_view(new_game(PUZZLE, SOLUTION))
            -- No key held: a keyless release must not be consumed (both
            -- sides nil would otherwise match as nil == nil).
            local consumed = view:handleEvent(Event:new("KeyRelease", {}))
            assert.is_nil(consumed, "a keyless release with nothing held must not be consumed")
            -- With a hold pending, a keyless release must not cancel it.
            press_key(view, "LPgFwd")
            consumed = view:handleEvent(Event:new("KeyRelease", {}))
            assert.is_nil(consumed, "a keyless release must not be consumed")
            scheduled[1].action()
            assert.is_true(view.notes_mode, "a keyless release must not cancel the hold")
        end)

        it("skips digits already placed nine times when cycling", function()
            local r, c = first_cell_with(2)
            local view = new_view(new_game(blank_solution({ { r, c } }), SOLUTION))
            press_key(view, "LPgFwd")
            assert.are.equal(2, view.armed, "forward cycling skips the completed digits")
            press_key(view, "LPgFwd")
            assert.are.equal(2, view.armed, "with one digit left, cycling stays on it")
            press_key(view, "RPgBack")
            assert.are.equal(2, view.armed, "backward cycling skips the completed digits too")
        end)

        it("skips the armed digit once it completes", function()
            local r2, c2 = first_cell_with(2)
            local r5, c5 = first_cell_with(5)
            local view = new_view(new_game(blank_solution({ { r2, c2 }, { r5, c5 } }), SOLUTION))
            tap_button(view, "number_row", 2)
            tap_cell(view, r2, c2)
            assert.is_not_nil(view._completed_digits[2], "placing the last 2 completes it")
            press_key(view, "LPgFwd")
            assert.are.equal(5, view.armed, "cycling skips the just-completed 2 and lands on 5")
        end)

        it("does nothing when every digit is already placed nine times", function()
            -- Blank one cell holding a 6 and one holding a 5, then fill them
            -- with each other's digits: every digit still appears nine times
            -- (so all are complete) but the board is wrong (duplicates, and
            -- not won).
            local r6, c6 = first_cell_with(6)
            local r5, c5 = first_cell_with(5)
            local view = new_view(new_game(blank_solution({ { r6, c6 }, { r5, c5 } }), SOLUTION))
            tap_button(view, "number_row", 5)
            tap_cell(view, r6, c6)
            tap_button(view, "number_row", 6)
            tap_cell(view, r5, c5)
            assert.is_not_nil(view._completed_digits[5])
            assert.is_not_nil(view._completed_digits[6])
            press_key(view, "LPgFwd")
            assert.are.equal(6, view.armed, "cycling cannot move off the armed digit")
            tap_button(view, "number_row", 6) -- disarm
            press_key(view, "LPgFwd")
            assert.is_nil(view.armed, "no digit is available, nothing is armed")
        end)
    end)
end)
