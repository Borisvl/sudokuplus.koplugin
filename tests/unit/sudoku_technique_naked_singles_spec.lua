package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local board = require("core.board")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu naked single example (single empty cell at (8,8), only candidate 6).
local HODOKU = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"

describe("core.techniques.naked_singles", function()
    it("places the single candidate and records the step", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))

        assert.are.equal(1, #path.steps)
        local step = path.steps[1]
        assert.are.equal("place", step.type)
        assert.are.equal(8, step.row)
        assert.are.equal(8, step.col)
        assert.are.equal(6, step.value)
        assert.are.equal(flags.NAKED_SINGLES, step.flags)
        assert.are.equal(0, step.step_number)
    end)

    it("records pattern metadata for the single", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        local pattern = path.steps[1].pattern
        assert.are.equal("naked_single", pattern.kind)
        assert.are.same({ { 8, 8 } }, pattern.cells)
        assert.are.same({ 6 }, pattern.values)
        assert.is_nil(pattern.unit)
    end)

    it("completes the board", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        assert.are.equal(81, board.count_clues(s.board))
        assert.is_not_nil(solver.validate(s.board))
    end)

    it("does not alter the givens", function()
        local original = board.from_string(HODOKU)
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        for r = 0, 8 do
            for c = 0, 8 do
                local orig = board.get(original, r, c)
                if orig ~= 0 then
                    assert.are.equal(orig, board.get(s.board, r, c))
                end
            end
        end
    end)

    it("produces no steps when no single is present", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.NAKED_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        assert.are.equal(81, board.count_clues(s.board))
        assert.are.equal(1, #path.steps)

        local s2 = solver.new(board.new(), { techniques = flags.NAKED_SINGLES })
        local path2 = solve_path.new()
        s2:propagate(path2)
        assert.are.equal(0, #path2.steps)
    end)
end)
