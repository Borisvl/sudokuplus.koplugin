package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu X-Wing example: https://hodoku.sourceforge.net/en/show_example.php?file=bf201&tech=X-Wing
local HODOKU = "000000000760003002002640009403900070000004903005000020010560000370090041000000060"
local techniques = bit.bor(flags.EASY, flags.MEDIUM, flags.X_WING)

local function is_in_lines(lines, r, c)
    for _, unit in ipairs(lines) do
        if unit.type == "row" and r == unit.index then
            return true
        end
        if unit.type == "col" and c == unit.index then
            return true
        end
    end
    return false
end

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function x_wing_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.X_WING then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.x_wing", function()
    it("produces x-wing eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = x_wing_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata with base and cover line units", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(x_wing_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("x_wing", pattern.kind)
            assert.are.equal(4, #pattern.cells)
            assert.are.equal(1, #pattern.values)
            assert.are.equal(2, #pattern.base)
            assert.are.equal(2, #pattern.cover)
            for _, unit in ipairs(pattern.base) do
                assert.is_true(unit.type == "row" or unit.type == "col")
            end
            for _, unit in ipairs(pattern.cover) do
                assert.is_true(unit.type == "row" or unit.type == "col")
            end
            assert.is_true(pattern.base[1].type ~= pattern.cover[1].type)
        end
    end)

    it("eliminates only from cover lines outside the base lines", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(x_wing_steps(path)) do
            local pattern = step.pattern
            assert.is_true(is_in_lines(pattern.cover, step.row, step.col))
            assert.is_false(is_in_lines(pattern.base, step.row, step.col))
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
    end)
end)
