package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local candidates = require("sudokuplus.core.candidates")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")
local flags = require("sudokuplus.core.techniques.flags")
local units = require("sudokuplus.core.techniques.units")

-- HoDoKu XY-Wing example: https://hodoku.sourceforge.net/en/show_example.php?file=y101&tech=XY-Wing
local HODOKU = "000060000000010863003009000904000000300000704570820000000006580690007000000040030"
local techniques = bit.bor(flags.EASY, flags.MEDIUM, flags.XY_WING)

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function xy_wing_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.XY_WING then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.xy_wing", function()
    it("produces xy-wing eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = xy_wing_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata with pivot and pincers", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(xy_wing_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("xy_wing", pattern.kind)
            assert.are.equal(3, #pattern.cells)
            assert.are.equal(1, #pattern.values)
            assert.is_not_nil(pattern.pivot)
            assert.are.equal(2, #pattern.pincers)
            -- The pivot sees both pincers; the pincers do not see each other.
            local pivot = pattern.pivot
            local p1, p2 = pattern.pincers[1], pattern.pincers[2]
            assert.is_true(units.sees(pivot[1], pivot[2], p1[1], p1[2]))
            assert.is_true(units.sees(pivot[1], pivot[2], p2[1], p2[2]))
            assert.is_false(units.sees(p1[1], p1[2], p2[1], p2[2]))
            assert.are.equal(pattern.values[1], step.value)
        end
    end)

    it("eliminates only the z value from cells seeing both pincers", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(xy_wing_steps(path)) do
            local pattern = step.pattern
            local p1, p2 = pattern.pincers[1], pattern.pincers[2]
            assert.is_true(units.sees(step.row, step.col, p1[1], p1[2]))
            assert.is_true(units.sees(step.row, step.col, p2[1], p2[2]))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
            assert.are.equal(pattern.values[1], step.value)
        end
    end)

    it("does not alter the givens", function()
        local original = board.from_string(HODOKU)
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
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

    it("solves the example guess-free with easy and medium techniques", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert.are.equal(81, board.count_clues(s.board))
        assert.is_not_nil(solver.validate(s.board))
    end)
end)
