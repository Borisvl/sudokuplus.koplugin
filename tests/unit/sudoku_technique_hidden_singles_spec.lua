package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu hidden single example: https://hodoku.sourceforge.net/en/show_example.php?file=h101&tech=Hidden+Single
local HODOKU = "008007000016083000000000051107290000000000000000046307290000000000860140000300700"

describe("core.techniques.hidden_singles", function()
    it("produces at least one hidden single placement", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.HIDDEN_SINGLES })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))

        local placements = 0
        for _, step in ipairs(path.steps) do
            assert.are.equal("place", step.type)
            assert.are.equal(flags.HIDDEN_SINGLES, step.flags)
            placements = placements + 1
        end
        assert.is_true(placements > 0)
    end)

    it("records pattern metadata with the hiding unit", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.HIDDEN_SINGLES })
        local path = solve_path.new()
        s:propagate(path)

        for _, step in ipairs(path.steps) do
            local pattern = step.pattern
            assert.are.equal("hidden_single", pattern.kind)
            assert.are.equal(1, #pattern.cells)
            assert.are.same({ step.value }, pattern.values)
            assert.is_not_nil(pattern.unit)
            assert.is_true(pattern.unit.type == "row" or pattern.unit.type == "col" or pattern.unit.type == "box")
            assert.is_true(pattern.unit.index >= 0 and pattern.unit.index <= 8)
        end
    end)

    it("places valid values that land in the board", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.HIDDEN_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(path.steps) do
            assert.are.equal(step.value, board.get(s.board, step.row, step.col))
        end
    end)

    it("does not alter the givens", function()
        local original = board.from_string(HODOKU)
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.HIDDEN_SINGLES })
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

    it("each hidden single value appears nowhere else in its recorded unit", function()
        local units = require("core.techniques.units")
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.HIDDEN_SINGLES })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(path.steps) do
            local unit = step.pattern.unit
            local cells
            if unit.type == "row" then
                cells = units.row_cells(unit.index)
            elseif unit.type == "col" then
                cells = units.col_cells(unit.index)
            else
                cells = units.box_cells(unit.index)
            end
            local count = 0
            for _, cell in ipairs(cells) do
                local r, c = cell[1], cell[2]
                if r ~= step.row or c ~= step.col then
                    if bit.band(candidates.get(s.candidates, r, c), bit.lshift(1, step.value - 1)) ~= 0 then
                        count = count + 1
                    end
                end
            end
            assert.are.equal(0, count)
        end
    end)
end)
